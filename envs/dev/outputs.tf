output "vm_public_ip" {
  description = "IP público da VM do backend. SSH: ssh opc@<este_ip>"
  value       = module.backend.vm_public_ip
}

output "vm_private_ip" {
  description = "IP privado da VM no VCN."
  value       = module.backend.vm_private_ip
}

output "vcn_id" {
  description = "OCID do VCN."
  value       = module.backend.vcn_id
}

output "db_primary_endpoint_fqdn" {
  description = "FQDN do endpoint primário do Postgres (alcançável só de dentro do VCN)."
  value       = module.database.primary_endpoint_fqdn
}

output "db_primary_endpoint_ip" {
  description = "IP privado do endpoint primário."
  value       = module.database.primary_endpoint_ip
}

output "db_admin_username" {
  description = "Usuário admin do Postgres."
  value       = module.database.admin_username
}

output "db_admin_password" {
  description = "Senha admin gerada (sensitive)."
  value       = module.database.admin_password
  sensitive   = true
}

output "database_url" {
  description = "Connection string async para `DATABASE_URL` do backend. SSL obrigatório."
  value = format(
    "postgresql+asyncpg://%s:%s@%s:5432/%s?ssl=require",
    module.database.admin_username,
    module.database.admin_password,
    module.database.primary_endpoint_fqdn,
    var.db_name,
  )
  sensitive = true
}
