# ost-iac.terraform

Infraestrutura como código para o cluster Kubernetes (OKE) da oneshift na
Oracle Cloud Infrastructure (OCI), com DNS na Cloudflare e GitOps via FluxCD.

Design completo: `docs/superpowers/specs/2026-07-14-oke-oci-iac-design.md`.

## Estrutura

- `terraform/` — compartment, cluster OKE (módulo oficial
  `oracle-terraform-modules/oke/oci`), token da Cloudflare e bootstrap do
  FluxCD.
- `fluxcd/` — manifests reconciliados pelo Flux: `shared-services/`
  (ingress-nginx, external-dns) e `apps/` (reservado pras apps da oneshift).
- `.github/workflows/` — pipeline de apply (`infra.yml`) e destroy manual
  (`infra-destroy.yml`).

## Bootstrap manual (uma vez só)

Estes passos não são automatizados de propósito — são problemas reais de
ovo-e-galinha (a infra que os gerenciaria ainda não existe).

### 1. Bucket de state (OCI Object Storage)

```bash
oci os bucket create \
  --compartment-id <ocid-do-compartment-raiz-ou-tenancy> \
  --name oneshift-tfstate-prd \
  --region sa-saopaulo-1
```

Crie uma **Customer Secret Key** pro usuário que vai rodar o Terraform
(Console OCI → Identity → Users → seu usuário → Customer Secret Keys), copie
`backend.hcl.example` para `backend.hcl` (gitignored) e preencha com os
valores reais. Use localmente com:

```bash
cd terraform
terraform init -backend-config=../backend.hcl
```

No pipeline, os mesmos valores vêm dos secrets `TF_STATE_BUCKET`,
`TF_STATE_S3_ENDPOINT`, `TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY`.

### 2. Chave age para o SOPS

Já gerada em `age.key` (local, gitignored) durante a implementação inicial —
guarde o conteúdo em um gerenciador de senhas. Depois que o cluster existir
(primeiro `terraform apply` real), carregue-a como o secret que o Flux usa
pra decriptar:

```bash
kubectl create secret generic sops-age \
  --namespace flux-system \
  --from-file=age.agekey=age.key
```

Se perder `age.key`, gere um novo par com `age-keygen -o age.key`, atualize
a chave pública em `.sops.yaml`, re-criptografe os secrets existentes em
`fluxcd/` e recrie o secret `sops-age` no cluster.

### 3. Token de API de conta da Cloudflare

Criado manualmente no dashboard da Cloudflare (Profile → API Tokens),
permissão mínima de **"Account API Tokens" → Edit** (é o token usado pelo
Terraform pra criar o token específico do external-dns, escopado só a DNS).
Guarde o valor no secret `CLOUDFLARE_ACCOUNT_API_TOKEN` do GitHub.

### 4. Credencial de git para o Flux (repositório privado)

O repositório `Oneshift-Organization/ost-iac.terraform` é **privado**, então o
`GitRepository` do Flux precisa de credenciais pra clonar. Gere um GitHub
Personal Access Token (fine-grained, permissão de leitura em "Contents" só
pra este repositório; um PAT clássico com escopo `repo` também funciona se o
fine-grained não estiver disponível). Depois que o cluster existir, crie o
secret que o `flux2-sync` referencia (`gitRepository.spec.secretRef.name =
flux-git-auth`):

```bash
kubectl create secret generic flux-git-auth \
  --namespace flux-system \
  --from-literal=username=<qualquer-valor-ex-git> \
  --from-literal=password=<o-token-gerado>
```

Mesma categoria de bootstrap manual do secret `sops-age`: ambos vivem em
`flux-system` e são pré-requisitos pra o `GitRepository`/`Kustomization`
funcionarem.

## GitHub Secrets necessários

| Secret | Descrição |
|---|---|
| `OCI_TENANCY_OCID` | OCID da tenancy |
| `OCI_USER_OCID` | OCID do usuário de API key |
| `OCI_FINGERPRINT` | Fingerprint da chave de API |
| `OCI_PRIVATE_KEY` | Conteúdo da chave privada PEM |
| `OCI_REGION` | Região da OCI (ex: `sa-saopaulo-1`) |
| `OCI_HOME_REGION` | Home region da tenancy |
| `CLOUDFLARE_ACCOUNT_API_TOKEN` | Token de conta Cloudflare (bootstrap manual acima) |
| `CLOUDFLARE_ZONE_ID` | Zone ID do domínio da oneshift |
| `TF_STATE_BUCKET` | Nome do bucket de state |
| `TF_STATE_S3_ENDPOINT` | Endpoint S3-compatible do Object Storage |
| `TF_STATE_ACCESS_KEY` | Customer Secret Key — access key |
| `TF_STATE_SECRET_KEY` | Customer Secret Key — secret key |

## Rodando localmente

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # preencha com valores reais
terraform init -backend-config=../backend.hcl
terraform plan
```

## Pipelines

- **`infra.yml`** — push na `main` que toque `terraform/**` dispara plan +
  apply automático, e re-criptografa `fluxcd/shared-services/external-dns/secret.sops.yaml`
  se o token da Cloudflare mudou.
- **`infra-destroy.yml`** — manual (`workflow_dispatch`), exige digitar
  `oneshift` para confirmar. Limpa os Ingress e o Service do ingress-nginx
  do cluster antes do destroy (dá tempo do external-dns remover os
  registros DNS e da OCI desprovisionar o Load Balancer associado ao
  Service, que não é gerenciado pelo Terraform).
