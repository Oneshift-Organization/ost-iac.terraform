# ost-iac.terraform

Infraestrutura como código para o cluster Kubernetes (OKE) da oneshift na
Oracle Cloud Infrastructure (OCI), com DNS na Cloudflare e GitOps via FluxCD.

Design completo: `docs/superpowers/specs/2026-07-14-oke-oci-iac-design.md`.

## Estrutura

- `terraform/` — cluster OKE (módulo oficial
  `oracle-terraform-modules/oke/oci`), token da Cloudflare e bootstrap do
  FluxCD, dentro do compartment `oneshift` (criado manualmente, ver
  `backend.md`). Também cria os secrets `sops-age` e `flux-git-auth` no
  cluster, via provider `kubernetes`.
- `fluxcd/` — manifests reconciliados pelo Flux: `shared-services/`
  (ingress-nginx, external-dns, cada um com um único `values-fluxcd.yaml`
  multi-doc) e `apps/` (reservado pras apps da oneshift).
- `.github/workflows/` — pipeline de apply (`infra-apply.yml`) e destroy
  manual (`infra-destroy.yml`).

## Bootstrap manual (uma vez só)

Estes passos não são automatizados de propósito — são problemas reais de
ovo-e-galinha (a infra que os gerenciaria ainda não existe).

### 1. Compartment + bucket de state

Ver `backend.md` pro passo a passo completo (comandos `oci` CLI pro
compartment `oneshift` e o bucket `oneshift-tfstate-prd`, Customer Secret
Key e como ligar tudo em `backend.hcl`/GitHub Secrets).

### 2. Chave age para o SOPS

Já gerada em `age.key` (local, gitignored) durante a implementação inicial —
guarde o conteúdo em um gerenciador de senhas. A chave pública vai em
`.sops.yaml` (na raiz do repo, inalterado). O conteúdo da chave **privada**
vai no secret `SOPS_AGE_PRIVATE_KEY` do GitHub — o Terraform cria o secret
`sops-age` no cluster automaticamente em todo `apply` (via provider
`kubernetes`, ver `04-cluster-secrets.tf`), não precisa mais de
`kubectl create secret` manual.

Se perder `age.key`, gere um novo par com `age-keygen -o age.key`, atualize
a chave pública em `.sops.yaml`, re-criptografe os secrets existentes em
`fluxcd/` e atualize o valor do secret `SOPS_AGE_PRIVATE_KEY` no GitHub.

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
fine-grained não estiver disponível). O usuário e o token vão nos secrets
`FLUX_GIT_USERNAME`/`FLUX_GIT_TOKEN` do GitHub — o Terraform cria o secret
`flux-git-auth` no cluster automaticamente em todo `apply`, mesmo mecanismo
do `sops-age` acima. Isso importa porque o cluster é destruído e recriado
repetidamente pelos pipelines, não só uma vez — um passo manual por cluster
não seria sustentável.

## GitHub Secrets necessários

| Secret | Descrição |
|---|---|
| `OCI_TENANCY_OCID` | OCID da tenancy |
| `OCI_USER_OCID` | OCID do usuário de API key |
| `OCI_FINGERPRINT` | Fingerprint da chave de API |
| `OCI_PRIVATE_KEY` | Conteúdo da chave privada PEM |
| `OCI_REGION` | Região da OCI (ex: `us-ashburn-1`) |
| `OCI_HOME_REGION` | Home region da tenancy |
| `CLOUDFLARE_ACCOUNT_API_TOKEN` | Token de conta Cloudflare (bootstrap manual acima) |
| `CLOUDFLARE_ZONE_ID` | Zone ID do domínio da oneshift |
| `TF_STATE_BUCKET` | Nome do bucket de state |
| `TF_STATE_S3_ENDPOINT` | Endpoint S3-compatible do Object Storage |
| `TF_STATE_ACCESS_KEY` | Customer Secret Key — access key |
| `TF_STATE_SECRET_KEY` | Customer Secret Key — secret key |
| `OCI_COMPARTMENT_ID` | OCID do compartment `oneshift` (ver `backend.md`) |
| `SOPS_AGE_PRIVATE_KEY` | Conteúdo da chave privada age (bootstrap manual acima) |
| `FLUX_GIT_USERNAME` | Usuário pro git auth do Flux (ex: `git`) |
| `FLUX_GIT_TOKEN` | PAT do GitHub pro Flux clonar o repo privado |

## Rodando localmente

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # preencha com valores reais
terraform init -backend-config=../backend.hcl
terraform plan
```

`terraform.tfvars.example` cresceu com os últimos ajustes (compartment e os
dois secrets declarativos) — mesma mecânica, só mais variáveis pra
preencher.

## Pipelines

- **`infra-apply.yml`** — push na `main` que toque `terraform/**` dispara
  plan + apply automático, e re-criptografa
  `fluxcd/shared-services/external-dns/secret.sops.yaml` se o token da
  Cloudflare mudou. Autentica a OCI CLI via variáveis de ambiente nativas
  (`OCI_CLI_USER`, `OCI_CLI_TENANCY` etc.), sem escrever `~/.oci/config`.
- **`infra-destroy.yml`** — manual (`workflow_dispatch`), exige digitar
  `oneshift` para confirmar. Limpa os Ingress e o Service do ingress-nginx
  do cluster antes do destroy (dá tempo do external-dns remover os
  registros DNS e da OCI desprovisionar o Load Balancer associado ao
  Service, que não é gerenciado pelo Terraform). Usa a action oficial
  `oracle-actions/configure-kubectl-oke` pra configurar o `kubectl`, em vez
  de rodar `oci ce cluster create-kubeconfig` manualmente.
