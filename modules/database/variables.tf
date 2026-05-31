variable "compartment_id" {
  type        = string
  description = "OCID do compartment."
}

variable "name_prefix" {
  type        = string
  description = "Prefixo de nome (ex.: ost-dev)."
}

variable "availability_domain" {
  type        = string
  description = "AD onde o DB nasce (storage AD-local). Para regional storage o valor é informativo apenas."
}

# ──────────────────────────────────────────────────────────────
# Rede — vem do módulo backend
# ──────────────────────────────────────────────────────────────
variable "vcn_id" {
  type        = string
  description = "OCID do VCN (output do módulo backend)."
}

variable "vcn_cidr" {
  type        = string
  description = "CIDR do VCN (usado para liberar acesso intra-VCN no security list de fallback, se necessário)."
}

variable "vm_nsg_id" {
  type        = string
  description = "OCID do NSG da VM (output do módulo backend). DB-NSG libera 5432 apenas a partir dele."
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR da subnet privada onde o endpoint do Postgres vai morar."
  default     = "10.0.2.0/24"
}

variable "private_subnet_dns_label" {
  type        = string
  description = "Label DNS da subnet privada."
  default     = "db"
}

# ──────────────────────────────────────────────────────────────
# Postgres gerenciado
# ──────────────────────────────────────────────────────────────
variable "db_version" {
  type        = string
  description = "Versão major do Postgres. Spec de arquitetura exige '16'."
  default     = "16"
}

variable "shape" {
  type        = string
  description = "Shape compute do DB. Ex.: VM.Standard.E4.Flex (AMD)."
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  type        = number
  description = "OCPUs por instância."
  default     = 2
}

variable "memory_gbs" {
  type        = number
  description = "Memória por instância (GB)."
  default     = 8
}

variable "storage_gbs" {
  type        = number
  description = "Storage em GB. Mínimo do serviço = 50."
  default     = 50
}

variable "is_regionally_durable" {
  type        = bool
  description = "true = storage regional (HA entre ADs); false = AD-local (mais barato, exige availability_domain)."
  default     = true
}

variable "system_type" {
  type        = string
  description = "Tipo do DB system. 'OCI_OPTIMIZED_STORAGE' é o suportado para PG gerenciado."
  default     = "OCI_OPTIMIZED_STORAGE"
}

variable "instance_count" {
  type        = number
  description = "Número de instâncias (1 = single node, 3 = HA com 2 réplicas)."
  default     = 1
}

variable "admin_username" {
  type        = string
  description = "Usuário admin do Postgres."
  default     = "ostadmin"
}

variable "backup_retention_days" {
  type        = number
  description = "Dias de retenção de backup automático."
  default     = 7
}

variable "freeform_tags" {
  type        = map(string)
  description = "Tags simples."
  default     = {}
}
