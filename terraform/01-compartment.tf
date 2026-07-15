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
