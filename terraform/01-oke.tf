module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.5.0"

  providers = {
    oci      = oci
    oci.home = oci.home
  }

  tenancy_id     = var.tenancy_ocid
  compartment_id = var.compartment_id
  region         = var.region
  home_region    = var.home_region

  cluster_name       = "oke-oneshift-prd"
  kubernetes_version = "v1.34.2"

  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true
  control_plane_allowed_cidrs       = ["0.0.0.0/0"]

  create_bastion  = false
  create_operator = false

  worker_pools = {
    "np-oneshift-prd" = {
      size   = 1
      shape  = "VM.Standard.E5.Flex"
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
