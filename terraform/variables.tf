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

variable "compartment_id" {
  description = "OCID do compartment oneshift (criado manualmente — ver backend.md)"
  type        = string
}

variable "sops_age_private_key" {
  description = "Conteúdo da chave privada age usada pelo SOPS (gerada uma vez via age-keygen, ver README)"
  type        = string
  sensitive   = true
}

variable "flux_git_username" {
  description = "Usuário para autenticação HTTPS do Flux no repositório git privado (qualquer valor não-vazio, ex: git)"
  type        = string
  sensitive   = true
}

variable "flux_git_token" {
  description = "Personal Access Token do GitHub usado pelo Flux para clonar o repositório privado"
  type        = string
  sensitive   = true
}
