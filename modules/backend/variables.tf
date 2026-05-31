variable "compartment_id" {
  type        = string
  description = "OCID do compartment."
}

variable "name_prefix" {
  type        = string
  description = "Prefixo de nome (ex.: ost-dev) para display_name dos recursos."
}

variable "availability_domain" {
  type        = string
  description = "Nome do AD onde a VM será criada (ex.: 'kEdT:SA-SAOPAULO-1-AD-1')."
}

# ──────────────────────────────────────────────────────────────
# Rede (este módulo cria VCN + subnet pública + IGW)
# ──────────────────────────────────────────────────────────────
variable "vcn_cidr" {
  type        = string
  description = "CIDR primário do VCN."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR da subnet pública (VM)."
  default     = "10.0.1.0/24"
}

variable "vcn_dns_label" {
  type        = string
  description = "Label DNS do VCN (≤15 chars alfanuméricos). Usado em FQDNs internos."
  default     = "ostvcn"
}

variable "public_subnet_dns_label" {
  type        = string
  description = "Label DNS da subnet pública."
  default     = "pub"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR autorizado a abrir SSH na VM. Use o IP do seu escritório/laptop; '0.0.0.0/0' libera mundo (não recomendado em prod)."
  default     = "0.0.0.0/0"
}

# ──────────────────────────────────────────────────────────────
# VM
# ──────────────────────────────────────────────────────────────
variable "shape" {
  type        = string
  description = "Shape da VM. Default = AMD x86 Flex (pago — sai do Always Free, mas evita dor de cabeça com imagens ARM)."
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  type        = number
  description = "OCPUs da VM."
  default     = 2
}

variable "memory_gbs" {
  type        = number
  description = "Memória em GB."
  default     = 12
}

variable "boot_volume_gbs" {
  type        = number
  description = "Tamanho do boot volume em GB."
  default     = 50
}

variable "ssh_public_key" {
  type        = string
  description = "Chave pública SSH OpenSSH para acesso como usuário 'opc'."
}

variable "freeform_tags" {
  type        = map(string)
  description = "Tags simples aplicadas aos recursos do módulo."
  default     = {}
}
