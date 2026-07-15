# Cluster OKE na OCI com GitOps (FluxCD) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the `ost-iac.terraform` repo from zero to a working IaC setup that provisions an OKE cluster on OCI (compartment `oneshift`, env `prd`), bootstraps FluxCD for in-cluster GitOps, and ships two GitHub Actions pipelines (apply on push to `main`, manual destroy).

**Architecture:** A single Terraform root module (`terraform/`) creates the OCI compartment, an OKE cluster via the official `oracle-terraform-modules/oke/oci` registry module, a Cloudflare API token for DNS automation, and bootstraps FluxCD via `helm_release`. FluxCD then reconciles `fluxcd/` from git: `shared-services/` (namespace + `ingress-nginx` + `external-dns`, each in its own self-contained folder) and `apps/` (empty, reserved for oneshift's own apps later). The Cloudflare token flows from Terraform output → SOPS-encrypted secret committed by the pipeline → decrypted and applied by Flux.

**Tech Stack:** Terraform >= 1.5, OCI provider (`oracle/oci`), Cloudflare provider (`cloudflare/cloudflare` v5), Helm provider (`hashicorp/helm` v3), `oracle-terraform-modules/oke/oci` v5.5.0, FluxCD (flux2 + flux2-sync Helm charts), SOPS + age, GitHub Actions.

## Global Constraints

- Regra do projeto: **MENOS É MAIS** — sempre a opção mais direta, evitar gambiarra e engenharia excessiva. Toda tarefa abaixo deve ser julgada por esse critério antes de adicionar qualquer coisa não pedida.
- Nomenclatura de recursos OCI: `<recurso>-<project>-<env>`, com `project = oneshift`, `env = prd` (único ambiente por enquanto). Exceção: o compartment se chama só `oneshift`.
- Sempre usar os módulos oficiais de `oracle-terraform-modules` para recursos OCI quando existir um módulo aplicável (aqui: `terraform-oci-oke`, que já cobre a VCN internamente).
- FluxCD é a única ferramenta de GitOps para assets do cluster — Terraform nunca cria objetos Kubernetes diretamente (sem provider `kubernetes` no Terraform).
- Zero PRs: pipeline dispara em push direto na `main` (trunk-based).
- Fonte de verdade do design: `docs/superpowers/specs/2026-07-14-oke-oci-iac-design.md` — qualquer dúvida de arquitetura durante a implementação, essa é a referência.
- Este ambiente de execução **não tem credenciais reais da OCI/Cloudflare** — a validação de cada tarefa usa `terraform validate`/`terraform init -backend=false`/`kubectl kustomize`, nunca `terraform apply` real. O primeiro `apply` de verdade só acontece quando o usuário configurar os GitHub Secrets reais e der push.

---

### Task 1: Scaffolding do repositório (.gitignore)

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: convenção de que `*.tfvars` (exceto `*.tfvars.example`), `backend.hcl` (exceto `.example`) e `age.key` nunca são commitados — todas as tasks seguintes dependem disso para não vazar segredo.

- [ ] **Step 1: Criar o .gitignore**

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
!*.tfvars.example
override.tf
override.tf.json
*_override.tf
*_override.tf.json
*tfplan*
.terraform.tfstate.lock.info
.terraformrc
terraform.rc
backend.hcl
!backend.hcl.example

# SOPS / age
age.key

# OS
.DS_Store
```

- [ ] **Step 2: Verificar que os padrões funcionam como esperado**

Run:
```bash
mkdir -p /tmp/gitignore-check && cd /tmp/gitignore-check
git -C /home/luandi/projects/pessoal/oneshift/ost-iac.terraform check-ignore -v terraform/terraform.tfvars terraform/backend.hcl age.key terraform/terraform.tfvars.example
```
Expected: as três primeiras linhas (`terraform.tfvars`, `backend.hcl`, `age.key`) aparecem como ignoradas (com a regra que casou); `terraform.tfvars.example` **não** aparece na saída (não ignorado, exit code diferente pra essa linha).

- [ ] **Step 3: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add .gitignore
git commit -m "chore: add .gitignore for terraform, sops and local secrets"
```

---

### Task 2: Bootstrap do SOPS (chave age + .sops.yaml)

**Files:**
- Create: `.sops.yaml`
- Create (local, gitignored): `age.key`

**Interfaces:**
- Produces: chave pública age referenciada em `.sops.yaml` — Task 11 (external-dns secret) depende dela pra criptografar de verdade.

- [ ] **Step 1: Gerar o par de chaves age**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
age-keygen -o age.key
```
Expected: arquivo `age.key` criado, com a saída do comando mostrando `Public key: age1...` (guarde esse valor para o próximo passo).

- [ ] **Step 2: Criar .sops.yaml com a chave pública**

```yaml
creation_rules:
  - path_regex: fluxcd/.*\.sops\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: <COLE_AQUI_A_PUBLIC_KEY_DO_PASSO_ANTERIOR>
```

(`encrypted_regex` restringe a criptografia aos campos `data`/`stringData` do Secret — `metadata.name`/`metadata.namespace` ficam em texto plano, exigido pelo Flux/kustomize pra rotear o recurso.)

- [ ] **Step 3: Validar que a config funciona de ponta a ponta**

Run:
```bash
mkdir -p fluxcd
cat > fluxcd/check.sops.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: check
  namespace: shared-services
stringData:
  foo: bar
EOF
sops --encrypt --in-place fluxcd/check.sops.yaml
cat fluxcd/check.sops.yaml
```
Expected: saída é um YAML válido, com `metadata.name: check` em texto plano e `stringData.foo` substituído por um valor `ENC[AES256_GCM,...]`, mais um bloco `sops:` no fim do arquivo com `age:` preenchido.

Note: o `sops` casa as `creation_rules` de `.sops.yaml` pelo **caminho do arquivo de entrada**, não pelo caminho de saída de um redirect `>`. Por isso o arquivo tem que ser escrito direto no caminho final (que bate com o `path_regex: fluxcd/.*\.sops\.ya?ml$`) e criptografado `--in-place` — `sops --encrypt /tmp/algo.yaml > fluxcd/algo.sops.yaml` falha com "no matching creation rules found", porque o `/tmp/...` não bate com o regex.

- [ ] **Step 4: Limpar o arquivo de teste e commitar só o necessário**

```bash
rm /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/fluxcd/check.sops.yaml
rmdir /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/fluxcd 2>/dev/null || true
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add .sops.yaml
git commit -m "chore: bootstrap sops with age key for fluxcd secrets"
```

**Important:** `age.key` (a chave privada) **não é commitada** — fica só localmente por enquanto. Ela precisa ser carregada no cluster como o secret `sops-age` antes do Flux conseguir decriptar qualquer coisa; isso é documentado como passo manual na Task 15 (README). Guarde o conteúdo de `age.key` em local seguro (gerenciador de senhas) — se perdê-lo, gera outro e re-criptografa os secrets existentes.

---

### Task 3: Terraform — variáveis e providers base

**Files:**
- Create: `terraform/variables.tf`
- Create: `terraform/00-provider.tf`
- Create: `terraform/terraform.tfvars.example`

**Interfaces:**
- Produces: `var.tenancy_ocid`, `var.user_ocid`, `var.fingerprint`, `var.private_key`, `var.region`, `var.home_region`, `var.cloudflare_account_api_token`, `var.cloudflare_zone_id` — usadas por todas as tasks seguintes de Terraform. Provider `oci` (default + alias `home`) e `cloudflare` configurados.

- [ ] **Step 1: Criar terraform/variables.tf**

```hcl
variable "tenancy_ocid" {
  description = "OCID da tenancy da OCI"
  type        = string
}

variable "user_ocid" {
  description = "OCID do usuário usado na autenticação via API key"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint da chave de assinatura da API da OCI"
  type        = string
}

variable "private_key" {
  description = "Conteúdo (não o path) da chave privada PEM de assinatura da API da OCI"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Região da OCI onde os recursos são criados"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "home_region" {
  description = "Home region da tenancy, exigida para operações de IAM"
  type        = string
}

variable "cloudflare_account_api_token" {
  description = "Token de API de conta da Cloudflare, com permissão de criar outros tokens"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID do domínio da oneshift já configurado na Cloudflare"
  type        = string
}
```

- [ ] **Step 2: Criar terraform/00-provider.tf**

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

provider "oci" {
  alias        = "home"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.home_region
}

provider "cloudflare" {
  api_token = var.cloudflare_account_api_token
}
```

Note: `backend "s3" {}` fica vazio de propósito — os valores reais (bucket, endpoint, credenciais) vêm de `-backend-config` no `terraform init`, nunca de variáveis (blocos de backend não aceitam interpolação). Ver `backend.hcl.example` no próximo passo e a Task 15 pro bootstrap real do bucket.

- [ ] **Step 3: Criar terraform/terraform.tfvars.example**

```hcl
tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaaexample"
user_ocid    = "ocid1.user.oc1..aaaaaaaaexample"
fingerprint  = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
private_key  = <<EOT
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
EOT
region      = "sa-saopaulo-1"
home_region = "us-ashburn-1"

cloudflare_account_api_token = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
cloudflare_zone_id           = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

- [ ] **Step 4: Validar formatação e sintaxe**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check
terraform init -backend=false
terraform validate
```
Expected: `terraform fmt -check` sem saída (nada pra formatar); `terraform init -backend=false` termina com "Terraform has been successfully initialized!"; `terraform validate` imprime `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add terraform/variables.tf terraform/00-provider.tf terraform/terraform.tfvars.example terraform/.terraform.lock.hcl
git commit -m "feat: terraform providers and base variables"
```

---

### Task 4: Terraform — compartment oneshift

**Files:**
- Create: `terraform/01-compartment.tf`

**Interfaces:**
- Consumes: `var.tenancy_ocid` (Task 3).
- Produces: `oci_identity_compartment.oneshift` (id via `oci_identity_compartment.oneshift.id`) — Task 5 (OKE) usa esse id como `compartment_id`. `locals.project = "oneshift"`, `locals.env = "prd"`.

- [ ] **Step 1: Criar terraform/01-compartment.tf**

```hcl
locals {
  project = "oneshift"
  env     = "prd"
}

resource "oci_identity_compartment" "oneshift" {
  compartment_id = var.tenancy_ocid
  name           = "oneshift"
  description    = "Compartment para todos os recursos ${local.env} da oneshift"
  enable_delete  = true
}
```

Note: `enable_delete = true` é necessário pra que `terraform destroy` realmente remova o compartment — sem isso o provider só marca ele como importado e nunca deleta (comportamento padrão do resource, pensado pra evitar deleção acidental de compartments compartilhados).

- [ ] **Step 2: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check
terraform validate
```
Expected: mesma saída de sucesso da Task 3.

- [ ] **Step 3: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add terraform/01-compartment.tf
git commit -m "feat: create oneshift compartment"
```

---

### Task 5: Terraform — cluster OKE (módulo oficial)

**Files:**
- Create: `terraform/02-oke.tf`

**Interfaces:**
- Consumes: `oci_identity_compartment.oneshift.id` (Task 4), `var.tenancy_ocid`, `var.region`, `var.home_region` (Task 3).
- Produces: `module.oke.cluster_id`, `module.oke.cluster_endpoints.public_endpoint`, `module.oke.cluster_ca_cert` — Task 7 (provider helm) e Task 6 (infra.yml/destroy, indiretamente) dependem desses outputs. Output `cluster_id` exposto na raiz.

- [ ] **Step 1: Criar terraform/02-oke.tf**

```hcl
module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.5.0"

  providers = {
    oci      = oci
    oci.home = oci.home
  }

  tenancy_id     = var.tenancy_ocid
  compartment_id = oci_identity_compartment.oneshift.id
  region         = var.region
  home_region    = var.home_region

  cluster_name       = "oke-oneshift-prd"
  kubernetes_version = "v1.34.2"

  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true

  create_bastion  = false
  create_operator = false

  worker_pools = {
    "np-oneshift-prd" = {
      size   = 2
      shape  = "VM.Standard.A1.Flex"
      ocpus  = 2
      memory = 12
    }
  }

  output_detail = true
}

output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = module.oke.cluster_id
}
```

Note: `output_detail = true` é necessário pra que o módulo exponha `cluster_ca_cert` (por padrão vem `null`) — a Task 7 precisa desse valor pro provider `helm` se conectar ao cluster. `create_bastion`/`create_operator` default pra `true` no módulo — setar `false` explicitamente é o que elimina esses dois hosts extras (ver spec: "sem bastion nem operator host").

- [ ] **Step 2: Validar (baixa o módulo do Terraform Registry)**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check
terraform init -backend=false -upgrade
terraform validate
```
Expected: `terraform init` mostra "Installing oracle-terraform-modules/oke/oci..." e termina com sucesso; `terraform validate` retorna `Success!`.

- [ ] **Step 3: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add terraform/02-oke.tf terraform/.terraform.lock.hcl
git commit -m "feat: provision OKE cluster via official oracle-terraform-modules"
```

---

### Task 6: Terraform — token da Cloudflare para o external-dns

**Files:**
- Create: `terraform/03-cloudflare-token.tf`

**Interfaces:**
- Consumes: `var.cloudflare_zone_id` (Task 3), provider `cloudflare` (Task 3).
- Produces: output sensível `cloudflare_api_token` — usado pelo passo de criptografia SOPS no `infra.yml` (Task 13).

- [ ] **Step 1: Criar terraform/03-cloudflare-token.tf**

```hcl
data "cloudflare_api_token_permission_groups_list" "dns_write" {
  name  = "DNS%20Write"
  scope = "com.cloudflare.api.account.zone"
}

resource "cloudflare_api_token" "external_dns" {
  name = "external-dns-oneshift-prd"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_api_token_permission_groups_list.dns_write.result[0].id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${var.cloudflare_zone_id}" = "*"
    })
  }]
}

output "cloudflare_api_token" {
  description = "Token usado pelo external-dns para editar DNS na zona da oneshift"
  value       = cloudflare_api_token.external_dns.value
  sensitive   = true
}
```

- [ ] **Step 2: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add terraform/03-cloudflare-token.tf
git commit -m "feat: create cloudflare api token scoped to dns edit"
```

---

### Task 7: Terraform — bootstrap do FluxCD

**Files:**
- Modify: `terraform/00-provider.tf` (adicionar `provider "helm"`)
- Create: `terraform/04-fluxcd.tf`

**Interfaces:**
- Consumes: `module.oke.cluster_id`, `module.oke.cluster_endpoints.public_endpoint`, `module.oke.cluster_ca_cert` (Task 5), `var.region` (Task 3).
- Produces: `helm_release.flux`, `helm_release.flux_sync` — instala o Flux e configura o `flux2-sync` pra reconciliar `./fluxcd` deste repo com decryption SOPS habilitado (chave `sops-age`, criada manualmente — ver Task 15).

- [ ] **Step 1: Adicionar o provider helm em terraform/00-provider.tf**

Adicionar ao final do arquivo (depois do `provider "cloudflare"` já existente):

```hcl

provider "helm" {
  kubernetes = {
    host                   = module.oke.cluster_endpoints.public_endpoint
    cluster_ca_certificate = base64decode(module.oke.cluster_ca_cert)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "oci"
      args = [
        "ce", "cluster", "generate-token",
        "--cluster-id", module.oke.cluster_id,
        "--region", var.region,
      ]
    }
  }
}
```

- [ ] **Step 2: Criar terraform/04-fluxcd.tf**

```hcl
resource "helm_release" "flux" {
  name             = "flux2"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "~> 2.19"
  namespace        = "flux-system"
  create_namespace = true
}

resource "helm_release" "flux_sync" {
  name       = "flux2-sync"
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "~> 1.15"
  namespace  = "flux-system"

  set = [
    {
      name  = "gitRepository.spec.url"
      value = "https://github.com/Oneshift-Organization/ost-iac.terraform"
    },
    {
      name  = "gitRepository.spec.ref.branch"
      value = "main"
    },
    {
      name  = "kustomization.spec.path"
      value = "./fluxcd"
    },
    {
      name  = "kustomization.spec.decryption.provider"
      value = "sops"
    },
    {
      name  = "kustomization.spec.decryption.secretRef.name"
      value = "sops-age"
    },
    {
      name  = "gitRepository.spec.secretRef.name"
      value = "flux-git-auth"
    },
  ]

  depends_on = [helm_release.flux]
}
```

O repositório é **privado**, então o `GitRepository` precisa de credenciais
(`gitRepository.spec.secretRef.name = flux-git-auth`) — secret criado
manualmente no cluster (ver Task 15), mesmo padrão do `sops-age`.

Note: `set` no `helm_release` é uma **lista de objetos** (`set = [{...}, ...]`) no provider `hashicorp/helm` v3, não blocos repetidos `set {}` (isso mudou do v2 pro v3 — confirmado rodando `terraform validate` contra o provider v3.2.0 real).

- [ ] **Step 3: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check
terraform init -backend=false
terraform validate
```
Expected: `Success! The configuration is valid.` Isso fecha a validação estática de todo o Terraform — os próximos passos que precisam de `apply` real só podem ser feitos pelo usuário com credenciais reais (ver Task 15).

- [ ] **Step 4: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add terraform/00-provider.tf terraform/04-fluxcd.tf
git commit -m "feat: bootstrap fluxcd via helm_release with sops decryption"
```

---

### Task 8: FluxCD — path apps (placeholder)

**Files:**
- Create: `fluxcd/apps/kustomization.yaml`

**Interfaces:**
- Produces: path vazio, buildável, que a Task 12 (kustomization raiz) vai referenciar.

- [ ] **Step 1: Criar fluxcd/apps/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

- [ ] **Step 2: Validar que builda (mesmo vazio)**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd/apps
```
Expected: sem erro, saída vazia (nenhum recurso).

- [ ] **Step 3: Commit**

```bash
git add fluxcd/apps/kustomization.yaml
git commit -m "feat: reserve fluxcd/apps path for future oneshift apps"
```

---

### Task 9: FluxCD — namespace shared-services

**Files:**
- Create: `fluxcd/shared-services/kustomization.yaml`
- Create: `fluxcd/shared-services/namespace.yaml`

**Interfaces:**
- Produces: namespace `shared-services`. Task 10 e 11 vão adicionar entradas em `fluxcd/shared-services/kustomization.yaml`.

- [ ] **Step 1: Criar fluxcd/shared-services/namespace.yaml**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shared-services
```

- [ ] **Step 2: Criar fluxcd/shared-services/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
```

- [ ] **Step 3: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd/shared-services
```
Expected: imprime o manifest YAML da `Namespace shared-services`, sem erro.

- [ ] **Step 4: Commit**

```bash
git add fluxcd/shared-services/kustomization.yaml fluxcd/shared-services/namespace.yaml
git commit -m "feat: create shared-services namespace via fluxcd"
```

---

### Task 10: FluxCD — serviço ingress-nginx

**Files:**
- Create: `fluxcd/shared-services/ingress-nginx/kustomization.yaml`
- Create: `fluxcd/shared-services/ingress-nginx/helmrepository.yaml`
- Create: `fluxcd/shared-services/ingress-nginx/helmrelease.yaml`
- Modify: `fluxcd/shared-services/kustomization.yaml`

**Interfaces:**
- Produces: `HelmRelease/ingress-nginx` no namespace `shared-services`, expondo um Service `LoadBalancer` (via `controller.publishService.enabled`, consumido pelo external-dns na Task 11).

- [ ] **Step 1: Criar fluxcd/shared-services/ingress-nginx/helmrepository.yaml**

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: shared-services
spec:
  interval: 1h
  url: https://kubernetes.github.io/ingress-nginx
```

- [ ] **Step 2: Criar fluxcd/shared-services/ingress-nginx/helmrelease.yaml**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: shared-services
spec:
  interval: 1h
  releaseName: ingress-nginx
  chart:
    spec:
      chart: ingress-nginx
      version: "4.15.1"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: shared-services
  values:
    controller:
      publishService:
        enabled: true
```

- [ ] **Step 3: Criar fluxcd/shared-services/ingress-nginx/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
```

- [ ] **Step 4: Adicionar ingress-nginx ao kustomization de shared-services**

Editar `fluxcd/shared-services/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - ingress-nginx
```

- [ ] **Step 5: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd/shared-services
```
Expected: imprime a `Namespace`, o `HelmRepository` e o `HelmRelease` do ingress-nginx, sem erro.

- [ ] **Step 6: Commit**

```bash
git add fluxcd/shared-services/ingress-nginx fluxcd/shared-services/kustomization.yaml
git commit -m "feat: deploy ingress-nginx via fluxcd in shared-services"
```

---

### Task 11: FluxCD — serviço external-dns (com secret SOPS)

**Files:**
- Create: `fluxcd/shared-services/external-dns/kustomization.yaml`
- Create: `fluxcd/shared-services/external-dns/helmrepository.yaml`
- Create: `fluxcd/shared-services/external-dns/helmrelease.yaml`
- Create: `fluxcd/shared-services/external-dns/secret.sops.yaml`
- Modify: `fluxcd/shared-services/kustomization.yaml`

**Interfaces:**
- Consumes: chave age gerada na Task 2 (`age.key`, `.sops.yaml`).
- Produces: `HelmRelease/external-dns`, secret `cloudflare-api-token` (namespace `shared-services`, chave `apiToken`) — sobrescrito automaticamente pelo `infra.yml` (Task 13) a cada rotação real do token.

- [ ] **Step 1: Criar fluxcd/shared-services/external-dns/helmrepository.yaml**

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: external-dns
  namespace: shared-services
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/external-dns/
```

- [ ] **Step 2: Criar fluxcd/shared-services/external-dns/helmrelease.yaml**

Substitua `oneshift.com.br` pelo domínio real da oneshift antes do primeiro deploy de verdade.

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-dns
  namespace: shared-services
spec:
  interval: 1h
  releaseName: external-dns
  chart:
    spec:
      chart: external-dns
      version: "1.21.1"
      sourceRef:
        kind: HelmRepository
        name: external-dns
        namespace: shared-services
  values:
    provider:
      name: cloudflare
    policy: sync
    env:
      - name: CF_API_TOKEN
        valueFrom:
          secretKeyRef:
            name: cloudflare-api-token
            key: apiToken
    domainFilters:
      - oneshift.com.br
    txtOwnerId: oneshift-prd
```

`policy: sync` é obrigatório — o default do chart é `upsert-only` (só
cria/atualiza registros DNS, nunca deleta), o que quebraria a limpeza de DNS
na exclusão de um Ingress (ver seção "Limpeza de DNS no destroy" do design).

- [ ] **Step 3: Gerar o secret.sops.yaml (placeholder, sobrescrito na primeira apply real)**

Run:
```bash
cat > fluxcd/shared-services/external-dns/secret.sops.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: shared-services
stringData:
  apiToken: changeme-placeholder-token
EOF
sops --encrypt --in-place fluxcd/shared-services/external-dns/secret.sops.yaml
cat fluxcd/shared-services/external-dns/secret.sops.yaml
```
Expected: YAML com `metadata` em texto plano e `stringData.apiToken` criptografado (`ENC[AES256_GCM,...]`), mais o bloco `sops:` no final.

Note: escreva o arquivo já no caminho final (que bate com o `path_regex` do `.sops.yaml`) e criptografe `--in-place` — `sops` casa as `creation_rules` pelo caminho de entrada, então `sops --encrypt /tmp/algo.yaml > caminho/final.sops.yaml` falha com "no matching creation rules found".

- [ ] **Step 4: Criar fluxcd/shared-services/external-dns/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
  - secret.sops.yaml
```

- [ ] **Step 5: Adicionar external-dns ao kustomization de shared-services**

Editar `fluxcd/shared-services/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - ingress-nginx
  - external-dns
```

- [ ] **Step 6: Validar**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd/shared-services
```
Expected: imprime `Namespace`, os dois `HelmRepository`, os dois `HelmRelease` e o `Secret` (ainda criptografado — `kubectl kustomize` não decripta, só valida a estrutura YAML). Sem erro.

- [ ] **Step 7: Commit**

```bash
git add fluxcd/shared-services/external-dns fluxcd/shared-services/kustomization.yaml
git commit -m "feat: deploy external-dns via fluxcd with sops-encrypted cloudflare token"
```

---

### Task 12: FluxCD — kustomization raiz

**Files:**
- Create: `fluxcd/kustomization.yaml`

**Interfaces:**
- Consumes: `fluxcd/shared-services/` (Task 9-11), `fluxcd/apps/` (Task 8).
- Produces: path `./fluxcd` completo e buildável — é o path que `flux2-sync` (Task 7) aponta.

- [ ] **Step 1: Criar fluxcd/kustomization.yaml**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - shared-services
  - apps
```

- [ ] **Step 2: Validar a árvore completa**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd
```
Expected: imprime todos os recursos (Namespace, 2x HelmRepository, 2x HelmRelease, Secret) sem erro — é a mesma saída que o Flux vai gerar ao reconciliar esse path (exceto pela decriptação do Secret, que só o Flux faz em runtime).

- [ ] **Step 3: Commit**

```bash
git add fluxcd/kustomization.yaml
git commit -m "feat: aggregate shared-services and apps in fluxcd root kustomization"
```

---

### Task 13: Pipeline infra.yml (plan + apply + rotação do secret)

**Files:**
- Create: `.github/workflows/infra.yml`

**Interfaces:**
- Consumes: GitHub Secrets `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY`, `OCI_REGION`, `OCI_HOME_REGION`, `CLOUDFLARE_ACCOUNT_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `TF_STATE_BUCKET`, `TF_STATE_S3_ENDPOINT`, `TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY` (todos documentados na Task 15).
- Produces: atualização automática de `fluxcd/shared-services/external-dns/secret.sops.yaml` a cada rotação do token — consumido pelo Flux, não por outro pipeline.

- [ ] **Step 1: Criar .github/workflows/infra.yml**

```yaml
name: infra

on:
  push:
    branches: [main]
    paths:
      - "terraform/**"

permissions:
  contents: write

env:
  TF_VERSION: "1.5.7"

jobs:
  plan-and-apply:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Install OCI CLI and sops
        run: |
          curl -L -O https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh
          bash install.sh --accept-all-defaults
          echo "$HOME/bin" >> "$GITHUB_PATH"
          curl -Lo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64
          sudo chmod +x /usr/local/bin/sops

      - name: Configure OCI CLI credentials
        run: |
          mkdir -p ~/.oci
          cat > ~/.oci/config <<EOF
          [DEFAULT]
          user=${{ secrets.OCI_USER_OCID }}
          fingerprint=${{ secrets.OCI_FINGERPRINT }}
          tenancy=${{ secrets.OCI_TENANCY_OCID }}
          region=${{ secrets.OCI_REGION }}
          key_file=/home/runner/.oci/oci_api_key.pem
          EOF
          printf '%s' "${{ secrets.OCI_PRIVATE_KEY }}" > ~/.oci/oci_api_key.pem
          chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem

      - name: Terraform init
        run: |
          terraform init \
            -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}" \
            -backend-config="key=oneshift-prd/terraform.tfstate" \
            -backend-config="region=${{ secrets.OCI_REGION }}" \
            -backend-config="endpoints={s3=\"${{ secrets.TF_STATE_S3_ENDPOINT }}\"}" \
            -backend-config="access_key=${{ secrets.TF_STATE_ACCESS_KEY }}" \
            -backend-config="secret_key=${{ secrets.TF_STATE_SECRET_KEY }}" \
            -backend-config="skip_region_validation=true" \
            -backend-config="skip_credentials_validation=true" \
            -backend-config="skip_requesting_account_id=true" \
            -backend-config="skip_s3_checksum=true" \
            -backend-config="use_path_style=true"

      - name: Terraform plan
        run: terraform plan -out=tfplan
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_user_ocid: ${{ secrets.OCI_USER_OCID }}
          TF_VAR_fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          TF_VAR_private_key: ${{ secrets.OCI_PRIVATE_KEY }}
          TF_VAR_region: ${{ secrets.OCI_REGION }}
          TF_VAR_home_region: ${{ secrets.OCI_HOME_REGION }}
          TF_VAR_cloudflare_account_api_token: ${{ secrets.CLOUDFLARE_ACCOUNT_API_TOKEN }}
          TF_VAR_cloudflare_zone_id: ${{ secrets.CLOUDFLARE_ZONE_ID }}

      - name: Terraform apply
        run: terraform apply -auto-approve tfplan

      - name: Encrypt cloudflare token for external-dns
        run: |
          TOKEN=$(terraform output -raw cloudflare_api_token)
          cat > ../fluxcd/shared-services/external-dns/secret.sops.yaml <<EOF
          apiVersion: v1
          kind: Secret
          metadata:
            name: cloudflare-api-token
            namespace: shared-services
          stringData:
            apiToken: ${TOKEN}
          EOF
          sops --encrypt --in-place ../fluxcd/shared-services/external-dns/secret.sops.yaml

      - name: Commit updated secret if changed
        run: |
          cd ..
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add fluxcd/shared-services/external-dns/secret.sops.yaml
          git diff --cached --quiet || git commit -m "chore: rotate cloudflare token for external-dns"
          git diff --cached --quiet || git push
```

Note: o commit no último passo só toca `fluxcd/**`, então não re-dispara esse mesmo workflow (que escuta só `terraform/**`) — sem risco de loop.

- [ ] **Step 2: Validar sintaxe YAML**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/infra.yml'))" && echo "YAML válido"
```
Expected: `YAML válido`, sem exceção.

- [ ] **Step 3: Commit**

```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git add .github/workflows/infra.yml
git commit -m "ci: add infra pipeline (plan, apply, rotate cloudflare secret)"
```

---

### Task 14: Pipeline infra-destroy.yml (destroy manual com confirmação)

**Files:**
- Create: `.github/workflows/infra-destroy.yml`

**Interfaces:**
- Consumes: mesmos GitHub Secrets da Task 13, mais `kubectl` configurado via `oci ce cluster create-kubeconfig`.

- [ ] **Step 1: Criar .github/workflows/infra-destroy.yml**

```yaml
name: infra-destroy

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Digite "oneshift" para confirmar a destruição de toda a infra'
        required: true

permissions:
  contents: read

jobs:
  destroy:
    if: github.event.inputs.confirm == 'oneshift'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.5.7"

      - name: Install OCI CLI
        run: |
          curl -L -O https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh
          bash install.sh --accept-all-defaults
          echo "$HOME/bin" >> "$GITHUB_PATH"

      - name: Configure OCI CLI credentials
        run: |
          mkdir -p ~/.oci
          cat > ~/.oci/config <<EOF
          [DEFAULT]
          user=${{ secrets.OCI_USER_OCID }}
          fingerprint=${{ secrets.OCI_FINGERPRINT }}
          tenancy=${{ secrets.OCI_TENANCY_OCID }}
          region=${{ secrets.OCI_REGION }}
          key_file=/home/runner/.oci/oci_api_key.pem
          EOF
          printf '%s' "${{ secrets.OCI_PRIVATE_KEY }}" > ~/.oci/oci_api_key.pem
          chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem

      - name: Terraform init
        run: |
          terraform init \
            -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}" \
            -backend-config="key=oneshift-prd/terraform.tfstate" \
            -backend-config="region=${{ secrets.OCI_REGION }}" \
            -backend-config="endpoints={s3=\"${{ secrets.TF_STATE_S3_ENDPOINT }}\"}" \
            -backend-config="access_key=${{ secrets.TF_STATE_ACCESS_KEY }}" \
            -backend-config="secret_key=${{ secrets.TF_STATE_SECRET_KEY }}" \
            -backend-config="skip_region_validation=true" \
            -backend-config="skip_credentials_validation=true" \
            -backend-config="skip_requesting_account_id=true" \
            -backend-config="skip_s3_checksum=true" \
            -backend-config="use_path_style=true"
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_user_ocid: ${{ secrets.OCI_USER_OCID }}
          TF_VAR_fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          TF_VAR_private_key: ${{ secrets.OCI_PRIVATE_KEY }}
          TF_VAR_region: ${{ secrets.OCI_REGION }}
          TF_VAR_home_region: ${{ secrets.OCI_HOME_REGION }}
          TF_VAR_cloudflare_account_api_token: ${{ secrets.CLOUDFLARE_ACCOUNT_API_TOKEN }}
          TF_VAR_cloudflare_zone_id: ${{ secrets.CLOUDFLARE_ZONE_ID }}

      - name: Delete ingress resources (let external-dns clean up DNS)
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_user_ocid: ${{ secrets.OCI_USER_OCID }}
          TF_VAR_fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          TF_VAR_private_key: ${{ secrets.OCI_PRIVATE_KEY }}
          TF_VAR_region: ${{ secrets.OCI_REGION }}
          TF_VAR_home_region: ${{ secrets.OCI_HOME_REGION }}
          TF_VAR_cloudflare_account_api_token: ${{ secrets.CLOUDFLARE_ACCOUNT_API_TOKEN }}
          TF_VAR_cloudflare_zone_id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
        run: |
          CLUSTER_ID=$(terraform output -raw cluster_id)
          oci ce cluster create-kubeconfig \
            --cluster-id "$CLUSTER_ID" \
            --file "$HOME/.kube/config" \
            --region "${{ secrets.OCI_REGION }}" \
            --token-version 2.0.0
          kubectl delete ingress --all -A --ignore-not-found
          kubectl delete svc -n shared-services -l app.kubernetes.io/instance=ingress-nginx --ignore-not-found
          sleep 60

      - name: Terraform destroy
        run: terraform destroy -auto-approve
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_user_ocid: ${{ secrets.OCI_USER_OCID }}
          TF_VAR_fingerprint: ${{ secrets.OCI_FINGERPRINT }}
          TF_VAR_private_key: ${{ secrets.OCI_PRIVATE_KEY }}
          TF_VAR_region: ${{ secrets.OCI_REGION }}
          TF_VAR_home_region: ${{ secrets.OCI_HOME_REGION }}
          TF_VAR_cloudflare_account_api_token: ${{ secrets.CLOUDFLARE_ACCOUNT_API_TOKEN }}
          TF_VAR_cloudflare_zone_id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
```

O `kubectl delete svc` do ingress-nginx é necessário porque o Service
`type: LoadBalancer` provisiona um Load Balancer OCI que não é gerenciado
pelo Terraform — sem essa limpeza, ele pode sobreviver ao `terraform
destroy` e bloquear a exclusão da VCN/subnets.

- [ ] **Step 2: Validar sintaxe YAML**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/infra-destroy.yml'))" && echo "YAML válido"
```
Expected: `YAML válido`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/infra-destroy.yml
git commit -m "ci: add manual destroy pipeline with confirmation and dns cleanup"
```

---

### Task 15: README com bootstrap manual e documentação de secrets

**Files:**
- Create: `README.md`
- Create: `backend.hcl.example`

**Interfaces:**
- Nenhuma (documentação) — mas é o único lugar que lista todos os GitHub Secrets consumidos pelas Tasks 13/14, e os passos manuais das Tasks 2/6/13.

- [ ] **Step 1: Criar backend.hcl.example**

```hcl
bucket = "oneshift-tfstate-prd"
key    = "oneshift-prd/terraform.tfstate"
region = "sa-saopaulo-1"

endpoints = {
  s3 = "https://<object-storage-namespace>.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"
}

access_key = "<customer-secret-key-access-key>"
secret_key = "<customer-secret-key-secret-key>"

skip_region_validation      = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_s3_checksum             = true
use_path_style               = true
```

- [ ] **Step 2: Criar README.md**

```markdown
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

O repositório `Oneshift-Organization/ost-iac.terraform` é **privado**, então
o `GitRepository` do Flux precisa de credenciais pra clonar. Gere um GitHub
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
```

- [ ] **Step 3: Validar que os arquivos existem e são markdown/hcl válidos**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
test -f README.md && test -f backend.hcl.example && echo "arquivos OK"
```
Expected: `arquivos OK`.

- [ ] **Step 4: Commit**

```bash
git add README.md backend.hcl.example
git commit -m "docs: add readme with manual bootstrap steps and secrets list"
```

---

### Task 16: Validação final de ponta a ponta

**Files:** nenhum (só validação)

- [ ] **Step 1: Terraform — fmt, init, validate no root inteiro**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform/terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```
Expected: `terraform fmt -check` sem saída; `terraform validate` → `Success! The configuration is valid.`

- [ ] **Step 2: FluxCD — árvore completa builda**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
kubectl kustomize fluxcd > /tmp/fluxcd-build.yaml
grep -c "^kind:" /tmp/fluxcd-build.yaml
```
Expected: comando roda sem erro; contagem de `kind:` bate com o esperado (1 Namespace + 2 HelmRepository + 2 HelmRelease + 1 Secret = 6).

- [ ] **Step 3: Workflows — sintaxe YAML válida**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
for f in .github/workflows/*.yml; do
  python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print(sys.argv[1], 'OK')" "$f"
done
```
Expected: `infra.yml OK` e `infra-destroy.yml OK`.

- [ ] **Step 4: Conferir que nenhum segredo real vazou pro git**

Run:
```bash
cd /home/luandi/projects/pessoal/oneshift/ost-iac.terraform
git ls-files | grep -E "\.tfvars$|backend\.hcl$|age\.key$" || echo "nenhum arquivo sensível rastreado"
```
Expected: `nenhum arquivo sensível rastreado`.

- [ ] **Step 5: git log final**

Run:
```bash
git log --oneline -20
```
Expected: uma sequência de commits, um por task, terminando no commit da Task 15/16.

**Limitação conhecida desta implementação:** nenhuma Task acima roda `terraform apply`/`terraform init` com backend real ou testa contra um cluster de verdade — este ambiente não tem credenciais da OCI/Cloudflare. O primeiro `apply` de verdade acontece quando o usuário preencher os GitHub Secrets (Task 15) e der push na `main`, ou rodar localmente com `terraform.tfvars` + `backend.hcl` reais.
