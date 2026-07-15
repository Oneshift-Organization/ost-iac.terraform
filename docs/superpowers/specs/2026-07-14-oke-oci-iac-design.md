# Design: Cluster OKE na OCI com GitOps (FluxCD)

## Contexto

Repositório de IaC para subir um cluster Kubernetes (OKE) na Oracle Cloud
Infrastructure (OCI), com DNS gerenciado na Cloudflare, seguindo o mesmo
espírito do repositório de referência
[`gs01-multicloud.fiap`](https://github.com/luizbrito7/gs01-multicloud.fiap):
arquivos Terraform numerados e enxutos, módulos oficiais, FluxCD para os
assets do cluster.

Regra do projeto, válida para toda decisão de design e implementação:
**MENOS É MAIS**. Preferir sempre a opção mais direta e simples, mesmo que
uma opção "mais robusta" exista. Evitar gambiarras, mas também evitar
engenharia excessiva.

Ambiente único neste momento: **prd** (produção). Projeto: **oneshift**.

## Estrutura do repositório

```
terraform/                 # root único: compartment + rede + OKE + token da
                            # Cloudflare + bootstrap do FluxCD
  00-provider.tf            # oci + helm + cloudflare
  01-compartment.tf
  02-oke.tf
  03-cloudflare-token.tf     # só o recurso cloud (cloudflare_api_token)
  04-fluxcd.tf
fluxcd/
  kustomization.yaml        # raiz: agrega shared-services/ e apps/
  shared-services/           # infra compartilhada do cluster (namespace shared-services)
    kustomization.yaml
    namespace.yaml            # namespace shared-services, compartilhada pelos serviços abaixo
    ingress-nginx/
      kustomization.yaml
      helmrepository.yaml     # fonte do chart
      helmrelease.yaml
    external-dns/
      kustomization.yaml
      helmrepository.yaml     # fonte do chart
      helmrelease.yaml
      secret.sops.yaml       # token da Cloudflare, criptografado via SOPS
  apps/                       # apps da oneshift (vazio por enquanto, populado depois)
    kustomization.yaml
.sops.yaml                   # regra de criptografia (chave age pública)
.github/
  workflows/
    infra.yml               # plan + apply automático em push na main
    infra-destroy.yml       # destroy manual, com confirmação
README.md                   # bootstrap manual: bucket de state + chave age (secret sops-age)
```

`03-cloudflare-token.tf` cria só o `cloudflare_api_token` (permissão
restrita de editar DNS na zona) — um recurso de conta Cloudflare como
qualquer outro, sem o problema de ovo-e-galinha que justifica os bootstraps
manuais (bucket de state, chave age): nada precisa desse token pra existir
antes dele. O provider `cloudflare` é autenticado com um API Token de conta
(permissão de criar outros tokens), via GitHub Secret.

Terraform continua **sem provider `kubernetes`**: o `helm_release` do Flux
usa o **provider `helm`** configurado com um bloco
`kubernetes { host = module.oke..., exec {...} }` (mesmo padrão do
repositório de referência) — a conexão fica na config do provider, não
precisa de um provider `kubernetes` à parte. O token da Cloudflare também
não vira `kubernetes_secret` via Terraform (ver seção de DNS) — ele sai do
`terraform output` direto pro pipeline, que o entrega ao cluster via
GitOps + SOPS.

Não há overlays por cloud (só existe OCI) — este repositório cobre
infraestrutura, o bootstrap do GitOps e os manifests que o Flux reconcilia
no cluster (`fluxcd/`). Cada serviço em `shared-services/` tem sua própria
pasta, autocontida (fonte do chart, HelmRelease e secrets daquele serviço).
O path `fluxcd/apps/` é o destino das aplicações da oneshift; por enquanto
fica vazio (só o `kustomization.yaml`), e passa a ser populado quando o
deploy dessas apps via GitOps começar.

Importante: mudanças dentro de `fluxcd/` **não passam pelo pipeline de
Terraform** — o Flux fica de olho no repositório sozinho (polling) e
reconcilia direto no cluster a cada push na `main`. Só mudanças em
`terraform/` disparam `infra.yml`.

## Nomenclatura

Padrão: `<recurso>-<project>-<env>`, com `project = oneshift` e `env = prd`.

Exceção: o **compartment** se chama apenas `oneshift` — ele é o container do
projeto inteiro, não um recurso tipado dentro dele, então o padrão não se
aplica a ele.

Exemplos de recursos dentro do compartment:
- `oke-oneshift-prd` (cluster OKE)
- `np-oneshift-prd` (node pool)

Esse padrão vale para recursos **OCI** dentro do compartment. Objetos
Kubernetes (namespace `shared-services`, releases do Flux, etc.) seguem
convenção própria do ecossistema k8s/Flux, não esse padrão — não faz
sentido versionar `env` num namespace quando o cluster inteiro já é de um
único ambiente (`prd`).

## Compartment & IAM

- Compartment único `oneshift`, criado como recurso nativo
  `oci_identity_compartment` — direto, sem módulo. Usar o módulo oficial
  `terraform-oci-iam` completo (que cria grupos, usuários, políticas) seria
  overkill para um único recurso.
- Autenticação do Terraform (local e no pipeline): **API Key da OCI**
  (`tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key`, `region`),
  armazenada como GitHub Secrets. É o método padrão do provider `oci`, sem
  federação OIDC.

## Rede + Cluster — módulo oficial `terraform-oci-oke`

Módulo: [`oracle-terraform-modules/terraform-oci-oke`](https://github.com/oracle-terraform-modules/terraform-oci-oke).

Esse módulo já provisiona a VCN internamente (subnets, gateways, NSGs), então
**não** usamos o módulo `terraform-oci-vcn` separado — seria redundante.

Configuração:
- **Basic Cluster** (control plane gratuito), API endpoint público — sem
  bastion nem operator host. O pipeline de CI acessa o cluster direto (via
  API Key + OCI CLI/kubeconfig), um recurso a menos pra manter.
- 1 node pool, shape `VM.Standard.A1.Flex` (Always Free), ex.: 2 nodes x 2
  OCPU / 12 GB — dentro do limite do Always Free tier da OCI (4 OCPU / 24 GB
  no total). Shape e contagem ficam como variáveis, ajustáveis depois.
- Extensões do módulo (Cilium, Prometheus, ArgoCD, Cluster Autoscaler,
  Karpenter, Gatekeeper etc.) **todas desligadas** — gestão de add-ons no
  cluster é responsabilidade do FluxCD, não do Terraform.

## State backend remoto

**OCI Object Storage via API S3-compatible** — método documentado
oficialmente pela Oracle para usar Terraform CLI padrão com state remoto na
OCI, sem depender de nenhum serviço externo à OCI (matando as alternativas de
Terraform Cloud/HCP) e sem trocar o fluxo de pipeline por OCI Resource
Manager.

- `backend "s3"` no Terraform, apontando pro endpoint S3-compatible da OCI
  (`https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`),
  autenticado com **Customer Secret Keys** (par access key/secret key —
  diferente da API Key usada pelo provider `oci`), também via GitHub Secrets.
- O bucket é criado **manualmente, uma única vez, via OCI CLI**
  (`oci os bucket create ...`) — não pelo Terraform. Evita o problema do
  ovo-e-galinha de gerenciar o próprio backend de state com o Terraform que
  depende dele. Comando documentado no README.
- Root único de Terraform (ver seção de estrutura) → um único bucket, uma
  única key de state.

## FluxCD bootstrap

Mesmo padrão do repositório de referência: em `04-fluxcd.tf`,
`helm_release` do `flux2` + `flux2-sync`, apontando para o path `./fluxcd`
(raiz) deste mesmo repositório (branch `main`) — um único Flux
`Kustomization` reconciliando a raiz, sem múltiplos CRs pra gerenciar.

A autenticação do provider `helm` com o cluster usa `oci ce cluster
generate-token` no bloco `exec` (equivalente ao `aws eks get-token` do
repositório de referência) — exige a **OCI CLI instalada no runner** do
pipeline, além do provider `oci` já configurado.

Dentro de `fluxcd/`, um `kustomization.yaml` raiz agrega dois paths por
`resources:`:
- **`shared-services/`** — infraestrutura compartilhada do cluster, tudo no
  namespace `shared-services` (criado pelo `namespace.yaml` na raiz dessa
  pasta, compartilhado pelos serviços abaixo dela). Cada serviço tem sua
  própria subpasta autocontida (fonte do chart + HelmRelease):
  `ingress-nginx/` e `external-dns/` (que também leva o secret SOPS do
  token da Cloudflare).
- **`apps/`** — reservado para as aplicações da oneshift. Vazio por
  enquanto (só um `kustomization.yaml` sem `resources`), populado quando
  essas apps começarem a ser deployadas via GitOps.

**SOPS entra desde já** (não é YAGNI — já existe um segredo real pra
gerenciar, o token do external-dns): a `flux2-sync` é configurada com
`kustomization.spec.decryption.provider = sops` e
`secretRef.name = sops-age`, igual ao repositório de referência.

O par de chaves **age** usado pelo SOPS é gerado e o secret `sops-age` é
criado **manualmente, uma única vez** (`age-keygen` + `kubectl create secret
generic sops-age --from-file=... -n flux-system`), documentado no README —
mesmo padrão de bootstrap manual do bucket de state: evita o
ovo-e-galinha de gerenciar via Terraform/Flux a própria chave que eles
precisam pra decriptar segredos. A chave pública fica em `.sops.yaml` na
raiz do repo.

## DNS (Cloudflare) + external-dns

Problema a resolver: o IP do Load Balancer do ingress só existe depois que o
FluxCD instala o `ingress-nginx` — não dá pra criar o registro DNS
diretamente no Terraform sem dependência circular ou um apply em duas fases.

Solução: **external-dns** rodando no cluster (deployado via FluxCD), que cria
e atualiza os registros DNS automaticamente a partir das anotações dos
Ingress/Services.

Fluxo, nessa ordem:
1. `03-cloudflare-token.tf` cria o `cloudflare_api_token`, escopado pra
   editar DNS só na zona da oneshift (via `data "cloudflare_zone"` — a zona
   é assumida como já existente, o Terraform não a cria). Output sensível
   `cloudflare_api_token`.
2. No `infra.yml`, depois do `terraform apply`, um passo pega esse output
   (`terraform output -raw cloudflare_api_token`), criptografa com `sops`
   (usando a chave pública em `.sops.yaml`) e escreve/commita
   `fluxcd/shared-services/external-dns/secret.sops.yaml` — só se o
   conteúdo mudou (token não muda a cada apply, só na criação/rotação).
3. O Flux decripta esse arquivo (chave `sops-age`, ver seção de FluxCD
   bootstrap) e aplica o secret no cluster antes de instalar o
   `external-dns`.
4. O FluxCD (`fluxcd/shared-services/`) deployará o `external-dns`, que
   consome esse secret, e o `ingress-nginx` — ambos no namespace
   `shared-services`.

Isso fecha o ciclo sem passo manual: criar o token, entregar pro cluster e
usar no external-dns tudo acontece sozinho a cada push na `main`. O runner
do `infra.yml` precisa ter o `sops` CLI instalado, além da OCI CLI (ver
seção de FluxCD bootstrap), e permissão de escrita no repo pra commitar o
secret atualizado.

### Limpeza de DNS no destroy

O `external-dns` usa registros TXT de "ownership" e remove o DNS quando o
Ingress/Service correspondente é deletado — mas num `terraform destroy`
direto, o cluster (e o pod do external-dns) some junto com tudo, sem chance
de fazer essa limpeza sozinho. Por isso o pipeline de destroy tem um passo
extra explícito antes do `terraform destroy` (ver seção de pipelines).

Efeito colateral aceito: depois de um `terraform destroy`, o
`cloudflare_api_token` é revogado, então `secret.sops.yaml` fica com um
token órfão no git. Inofensivo — no próximo `terraform apply`, o pipeline
gera um token novo e sobrescreve o arquivo automaticamente (passo 2 da
seção de DNS), sem intervenção manual.

## Pipelines (GitHub Actions)

Fluxo trunk-based, sem PRs — conforme decidido: push direto na `main`
dispara o pipeline.

**`infra.yml`** (dispara em push na `main`, paths `terraform/**`):
1. `terraform plan`
2. `terraform apply` automático (sem gate manual)
3. Criptografa o output `cloudflare_api_token` com `sops` e commita
   `fluxcd/shared-services/external-dns/secret.sops.yaml` (só se mudou).

**`infra-destroy.yml`** (manual, `workflow_dispatch`, exige digitar o nome do
compartment `oneshift` como confirmação):
1. Configura kubeconfig do OKE.
2. `kubectl delete ingress --all -A` e aguarda alguns segundos — dá tempo do
   external-dns reconciliar e limpar os registros DNS antes do cluster sumir.
3. `terraform destroy` (compartment, OKE e o token da Cloudflare, tudo no
   mesmo root module).

## Fora de escopo agora (YAGNI)

Adicionar apenas quando a necessidade aparecer de fato:
- Múltiplos ambientes (dev/staging) — só prd por enquanto.
- Bastion ou operator host.
- Cluster autoscaler, observability stack (Prometheus/Grafana), service mesh.
- Aprovação manual no apply (fluxo é auto-apply por decisão do usuário).
- Apps reais da oneshift rodando no cluster — o path `fluxcd/apps/` já
  existe, mas fica vazio até o deploy delas via GitOps começar de fato.
