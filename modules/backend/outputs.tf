output "vcn_id" {
  description = "OCID do VCN criado por este módulo."
  value       = oci_core_vcn.this.id
}

output "vcn_cidr" {
  description = "CIDR do VCN."
  value       = var.vcn_cidr
}

output "vm_nsg_id" {
  description = "OCID do NSG da VM (consumido por database para permitir 5432)."
  value       = oci_core_network_security_group.vm.id
}

output "public_subnet_id" {
  description = "OCID da subnet pública."
  value       = oci_core_subnet.public.id
}

output "vm_public_ip" {
  description = "IP público da VM."
  value       = oci_core_instance.this.public_ip
}

output "vm_private_ip" {
  description = "IP privado da VM."
  value       = oci_core_instance.this.private_ip
}

output "vm_id" {
  description = "OCID da VM."
  value       = oci_core_instance.this.id
}
