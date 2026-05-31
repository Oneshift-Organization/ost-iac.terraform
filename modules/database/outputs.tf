output "db_id" {
  description = "OCID do DB system."
  value       = oci_psql_db_system.this.id
}

output "primary_endpoint_fqdn" {
  description = "FQDN do endpoint primário (alcançável apenas de dentro do VCN)."
  value       = data.oci_psql_db_system_connection_detail.this.primary_db_endpoint[0].fqdn
}

output "primary_endpoint_ip" {
  description = "IP privado do endpoint primário."
  value       = data.oci_psql_db_system_connection_detail.this.primary_db_endpoint[0].ip_address
}

output "primary_endpoint_port" {
  description = "Porta do endpoint primário (5432 por padrão)."
  value       = data.oci_psql_db_system_connection_detail.this.primary_db_endpoint[0].port
}

output "ca_certificate" {
  description = "CA certificate do PostgreSQL Service Private CA, para clientes que querem verificar identidade do servidor."
  value       = data.oci_psql_db_system_connection_detail.this.ca_certificate
  sensitive   = true
}

output "admin_username" {
  description = "Usuário admin do Postgres."
  value       = var.admin_username
}

output "admin_password" {
  description = "Senha admin gerada (sensitive)."
  value       = random_password.admin.result
  sensitive   = true
}

output "private_subnet_id" {
  description = "OCID da subnet privada criada para o DB."
  value       = oci_core_subnet.private.id
}

output "db_nsg_id" {
  description = "OCID do NSG do DB."
  value       = oci_core_network_security_group.db.id
}
