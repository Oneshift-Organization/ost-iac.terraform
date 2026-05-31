# ──────────────────────────────────────────────────────────────
# Route table privada (sem rota default — DB não precisa de Internet)
# ──────────────────────────────────────────────────────────────
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name_prefix}-rt-private"
  freeform_tags  = var.freeform_tags
}

# ──────────────────────────────────────────────────────────────
# Subnet privada para o endpoint do Postgres
# ──────────────────────────────────────────────────────────────
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = var.vcn_id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "${var.name_prefix}-subnet-private"
  dns_label                  = var.private_subnet_dns_label
  route_table_id             = oci_core_route_table.private.id
  prohibit_public_ip_on_vnic = true
  prohibit_internet_ingress  = true
  freeform_tags              = var.freeform_tags
}

# ──────────────────────────────────────────────────────────────
# NSG do DB + regra (5432 só a partir do NSG da VM)
# ──────────────────────────────────────────────────────────────
resource "oci_core_network_security_group" "db" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = "${var.name_prefix}-nsg-db"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "db_ingress_postgres_from_vm" {
  network_security_group_id = oci_core_network_security_group.db.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = var.vm_nsg_id
  source_type               = "NETWORK_SECURITY_GROUP"
  description               = "Postgres 5432 a partir do NSG da VM do backend"
  tcp_options {
    destination_port_range {
      min = 5432
      max = 5432
    }
  }
}

# ──────────────────────────────────────────────────────────────
# Senha admin (gerada e marcada sensitive)
# ──────────────────────────────────────────────────────────────
resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?@^_"
}

# ──────────────────────────────────────────────────────────────
# Postgres gerenciado (oci_psql_db_system)
# ──────────────────────────────────────────────────────────────
resource "oci_psql_db_system" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.name_prefix}-pg"
  db_version     = var.db_version
  shape          = var.shape
  system_type    = var.system_type
  instance_count = var.instance_count

  instance_ocpu_count         = var.ocpus
  instance_memory_size_in_gbs = var.memory_gbs

  network_details {
    subnet_id                  = oci_core_subnet.private.id
    nsg_ids                    = [oci_core_network_security_group.db.id]
    is_reader_endpoint_enabled = false
  }

  storage_details {
    system_type           = var.system_type
    is_regionally_durable = var.is_regionally_durable
    availability_domain   = var.is_regionally_durable ? null : var.availability_domain
    iops                  = null
  }

  credentials {
    username = var.admin_username
    password_details {
      password_type = "PLAIN_TEXT"
      password      = random_password.admin.result
    }
  }

  management_policy {
    backup_policy {
      kind           = "DAILY"
      retention_days = var.backup_retention_days
      backup_start   = "03:00"
    }
  }

  freeform_tags = var.freeform_tags
}

# ──────────────────────────────────────────────────────────────
# Connection details (FQDN, IP, port, CA cert) — só ficam prontos
# depois que o db_system está ACTIVE.
# ──────────────────────────────────────────────────────────────
data "oci_psql_db_system_connection_detail" "this" {
  db_system_id = oci_psql_db_system.this.id
}
