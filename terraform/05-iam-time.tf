# Versionado aqui, e não em terraform.tfvars, porque o CI (infra-apply.yml)
# injeta variáveis só via TF_VAR_* de GitHub Secrets — um tfvars local nunca
# chegaria no apply.
variable "devs" {
  description = "Time com acesso kubectl ao OKE, no formato { apelido = \"email\" }"
  type        = map(string)

  default = {
    anderson_huang   = "rm565920@fiap.com.br"
    bruno_henrique   = "rm566277@fiap.com.br"
    ronaldo_attamah  = "rm564630@fiap.com.br"
    guylherme_miguel = "rm562374@fiap.com.br"
  }
}

resource "oci_identity_group" "devs" {
  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = "oneshift-devs"
  description    = "Time de desenvolvimento — acesso kubectl ao OKE"
}

# Verbo `use` (não `manage`): o time obtém o kubeconfig mas não deleta o
# cluster. O que cada pessoa pode fazer dentro do cluster é decidido pelo
# RBAC do Kubernetes, em fluxcd/shared-services/rbac.
resource "oci_identity_policy" "devs_oke" {
  provider       = oci.home
  compartment_id = var.compartment_id
  name           = "oneshift-devs-oke"
  description    = "Permite ao time obter o kubeconfig do OKE"

  statements = [
    "Allow group ${oci_identity_group.devs.name} to use clusters in compartment oneshift",
    "Allow group ${oci_identity_group.devs.name} to read cluster-node-pools in compartment oneshift",
  ]
}

resource "oci_identity_user" "devs" {
  for_each = var.devs

  provider       = oci.home
  compartment_id = var.tenancy_ocid
  name           = each.value
  email          = each.value
  description    = "Dev oneshift — ${each.key}"
}

resource "oci_identity_user_group_membership" "devs" {
  for_each = oci_identity_user.devs

  provider = oci.home
  user_id  = each.value.id
  group_id = oci_identity_group.devs.id
}

# Os OCIDs alimentam os subjects do RoleBinding — no OKE a identidade
# Kubernetes de uma pessoa é o OCID do usuário OCI, não o e-mail.
output "dev_user_ocids" {
  description = "OCIDs dos usuários do time, para os RoleBindings do cluster"
  value       = { for k, u in oci_identity_user.devs : k => u.id }
}
