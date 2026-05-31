# ──────────────────────────────────────────────────────────────
# Credenciais OCI
# ──────────────────────────────────────────────────────────────
variable "tenancy_ocid" {
  type        = string
  description = "OCID do tenancy OCI."
}

variable "user_ocid" {
  type        = string
  description = "OCID do usuário IAM que executa o Terraform."
}

variable "fingerprint" {
  type        = string
  description = "Fingerprint da chave API do usuário."
}

variable "private_key_path" {
  type        = string
  description = "Caminho absoluto da chave privada da API OCI (PEM)."
}

variable "region" {
  type        = string
  description = "Região OCI alvo. Ex.: sa-saopaulo-1, us-ashburn-1."
  default     = "sa-saopaulo-1"
}

variable "compartment_id" {
  type        = string
  description = "OCID do compartment onde os recursos serão criados."
}

# ──────────────────────────────────────────────────────────────
# Convenção de nomes
# ──────────────────────────────────────────────────────────────
variable "project" {
  type        = string
  description = "Identificador curto do projeto."
  default     = "ost"
}

variable "environment" {
  type        = string
  description = "Nome do ambiente."
  default     = "dev"
}

# ──────────────────────────────────────────────────────────────
# Rede
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

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR da subnet privada (Postgres)."
  default     = "10.0.2.0/24"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR autorizado a SSH na VM. Recomendado: IP fixo do dev/escritório."
  default     = "0.0.0.0/0"
}

# ──────────────────────────────────────────────────────────────
# VM (módulo backend)
# ──────────────────────────────────────────────────────────────
variable "vm_shape" {
  type        = string
  description = "Shape da VM. Default = AMD x86 Flex. Para Always Free use 'VM.Standard.A1.Flex' (ARM)."
  default     = "VM.Standard.E4.Flex"
}

variable "vm_ocpus" {
  type        = number
  description = "OCPUs da VM."
  default     = 2
}

variable "vm_memory_gbs" {
  type        = number
  description = "Memória da VM em GB."
  default     = 12
}

variable "vm_boot_volume_gbs" {
  type        = number
  description = "Boot volume em GB."
  default     = 50
}

variable "ssh_public_key" {
  type        = string
  description = "Chave pública SSH para acesso à VM como 'opc'."
}

# ──────────────────────────────────────────────────────────────
# Database (módulo database)
# ──────────────────────────────────────────────────────────────
variable "db_version" {
  type        = string
  description = "Versão major do Postgres. Spec exige 16."
  default     = "16"
}

variable "db_shape" {
  type        = string
  description = "Shape compute do DB."
  default     = "VM.Standard.E4.Flex"
}

variable "db_ocpus" {
  type        = number
  description = "OCPUs por instância de DB."
  default     = 2
}

variable "db_memory_gbs" {
  type        = number
  description = "Memória por instância de DB (GB)."
  default     = 8
}

variable "db_storage_gbs" {
  type        = number
  description = "Storage do DB em GB. Mínimo 50."
  default     = 50
}

variable "db_is_regionally_durable" {
  type        = bool
  description = "Storage regional (HA entre ADs) ou AD-local (mais barato)."
  default     = true
}

variable "db_instance_count" {
  type        = number
  description = "1 = single node; 3 = HA com 2 réplicas."
  default     = 1
}

variable "db_admin_username" {
  type        = string
  description = "Usuário admin do Postgres."
  default     = "ostadmin"
}

variable "db_backup_retention_days" {
  type        = number
  description = "Retenção de backup em dias."
  default     = 7
}

variable "db_name" {
  type        = string
  description = "Nome do database aplicação — usado para compor DATABASE_URL no output. Crie o DB e rode alembic após o provisionamento."
  default     = "ost"
}
