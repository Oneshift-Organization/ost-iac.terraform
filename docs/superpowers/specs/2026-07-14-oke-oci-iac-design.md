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
terraform/                 # root único: compartment + rede + OKE + token
                            # da Cloudflare + secret no cluster + bootstrap
                            # do FluxCD
  00-provider.tf
  01-compartment.tf
  02-oke.tf
  03-cloudflare-token.tf
  04-fluxcd.tf
fluxcd/
  kustomization.yaml       # raiz: agrega shared-services/ e apps/
  shared-services/          # infra compartilhada do cluster (namespace shared-services)
    kustomization.yaml
    ingress-nginx.yaml      # HelmRelease
    external-dns.yaml       # HelmRelease
  apps/                      # apps da oneshift (vazio por enquanto, populado depois)
    kustomization.yaml
.github/
  workflows/
    infra.yml              # plan + apply automático em push na main
    infra-destroy.yml      # destroy manual, com confirmação
README.md                  # inclui o passo manual de bootstrap do bucket de state
```

Root único de Terraform, não dois separados por provider: o token da
Cloudflare precisa virar um `kubernetes_secret` dentro do cluster OKE, então
manter `oci` e `cloudflare` em states separados forçaria usar
`terraform_remote_state` só pra cruzar essa referência — complexidade
desnecessária para um único recurso. Com um root só, os providers `oci`,
`cloudflare`, `kubernetes` e `helm` convivem no mesmo `00-provider.tf` e o
dado flui direto, sem cruzar states.

Não há overlays por cloud (só existe OCI) — este repositório cobre
infraestrutura, o bootstrap do GitOps e os manifests que o Flux reconcilia
no cluster (`fluxcd/`). O path `fluxcd/apps/` é o destino das aplicações da
oneshift; por enquanto fica vazio (só o `kustomization.yaml`), e passa a ser
populado quando o deploy dessas apps via GitOps começar.

## Nomenclatura

Padrão: `<recurso>-<project>-<env>`, com `project = oneshift` e `env = prd`.

Exceção: o **compartment** se chama apenas `oneshift` — ele é o container do
projeto inteiro, não um recurso tipado dentro dele, então o padrão não se
aplica a ele.

Exemplos de recursos dentro do compartment:
- `oke-oneshift-prd` (cluster OKE)
- `np-oneshift-prd` (node pool)

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

Dentro de `fluxcd/`, um `kustomization.yaml` raiz agrega dois paths por
`resources:`:
- **`shared-services/`** — infraestrutura compartilhada do cluster:
  `ingress-nginx` e `external-dns`, ambos no namespace `shared-services`.
  A namespace em si é criada pelo Terraform (`03-cloudflare-token.tf`), não
  pelo Flux — ela precisa existir antes do secret do token ser criado nela,
  e não faz sentido a namespace ter dois donos (Terraform e Flux) disputando
  o mesmo objeto.
- **`apps/`** — reservado para as aplicações da oneshift. Vazio por
  enquanto (só um `kustomization.yaml` sem `resources`), populado quando
  essas apps começarem a ser deployadas via GitOps.

Sem SOPS por enquanto — ainda não existe segredo de aplicação para
gerenciar; entra quando for necessário (YAGNI).

## DNS (Cloudflare) + external-dns

Problema a resolver: o IP do Load Balancer do ingress só existe depois que o
FluxCD instala o `ingress-nginx` — não dá pra criar o registro DNS
diretamente no Terraform sem dependência circular ou um apply em duas fases.

Solução: **external-dns** rodando no cluster (deployado via FluxCD), que cria
e atualiza os registros DNS automaticamente a partir das anotações dos
Ingress/Services.

- `03-cloudflare-token.tf` cria a namespace `shared-services`
  (`kubernetes_namespace`) e um `cloudflare_api_token`, com permissão
  restrita de editar DNS na zona, injetando o valor direto como
  `kubernetes_secret` dentro dessa namespace (via provider `kubernetes` do
  Terraform, configurado com o endpoint do OKE criado em `02-oke.tf`) —
  mesmo root module, sem cruzar states.
- O FluxCD (`fluxcd/shared-services/`) deployará o `external-dns` (namespace
  `shared-services`), que consome esse secret, e o `ingress-nginx` (mesmo
  namespace).
- **Zona Cloudflare assumida como já existente** (domínio já apontado pra
  lá), referenciada via `data "cloudflare_zone"` — o Terraform não cria a
  zona.

### Limpeza de DNS no destroy

O `external-dns` usa registros TXT de "ownership" e remove o DNS quando o
Ingress/Service correspondente é deletado — mas num `terraform destroy`
direto, o cluster (e o pod do external-dns) some junto com tudo, sem chance
de fazer essa limpeza sozinho. Por isso o pipeline de destroy tem um passo
extra explícito antes do `terraform destroy` (ver seção de pipelines).

## Pipelines (GitHub Actions)

Fluxo trunk-based, sem PRs — conforme decidido: push direto na `main`
dispara o pipeline.

**`infra.yml`** (dispara em push na `main`, paths `terraform/**`):
1. `terraform plan`
2. `terraform apply` automático (sem gate manual)

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
- SOPS / secrets criptografados no git.
- Bastion ou operator host.
- Cluster autoscaler, observability stack (Prometheus/Grafana), service mesh.
- Aprovação manual no apply (fluxo é auto-apply por decisão do usuário).
- Apps de exemplo rodando no cluster — isso é responsabilidade de outro
  repositório, este cobre só infra + bootstrap do GitOps.
