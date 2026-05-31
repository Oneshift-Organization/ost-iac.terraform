locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

# AD disponível na região
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# ──────────────────────────────────────────────────────────────
# Módulo backend: VCN + IGW + subnet pública + VM-NSG + VM
# ──────────────────────────────────────────────────────────────
module "backend" {
  source = "../../modules/backend"

  compartment_id      = var.compartment_id
  name_prefix         = local.name_prefix
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

  vcn_cidr           = var.vcn_cidr
  public_subnet_cidr = var.public_subnet_cidr
  ssh_allowed_cidr   = var.ssh_allowed_cidr

  shape           = var.vm_shape
  ocpus           = var.vm_ocpus
  memory_gbs      = var.vm_memory_gbs
  boot_volume_gbs = var.vm_boot_volume_gbs
  ssh_public_key  = var.ssh_public_key

  freeform_tags = local.tags
}

# ──────────────────────────────────────────────────────────────
# Módulo database: subnet privada + DB-NSG + Postgres gerenciado
# Recebe VCN + VM-NSG do backend para isolar 5432.
# ──────────────────────────────────────────────────────────────
module "database" {
  source = "../../modules/database"

  compartment_id      = var.compartment_id
  name_prefix         = local.name_prefix
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

  vcn_id              = module.backend.vcn_id
  vcn_cidr            = module.backend.vcn_cidr
  vm_nsg_id           = module.backend.vm_nsg_id
  private_subnet_cidr = var.private_subnet_cidr

  db_version            = var.db_version
  shape                 = var.db_shape
  ocpus                 = var.db_ocpus
  memory_gbs            = var.db_memory_gbs
  storage_gbs           = var.db_storage_gbs
  is_regionally_durable = var.db_is_regionally_durable
  instance_count        = var.db_instance_count
  admin_username        = var.db_admin_username
  backup_retention_days = var.db_backup_retention_days

  freeform_tags = local.tags
}
