output "sql_server_id" {
  description = "Resource ID of the example SQL server."
  value       = module.sql_server.id
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the example SQL server."
  value       = module.sql_server.fully_qualified_domain_name
}

output "database_ids" {
  description = "Resource IDs of the example's databases."
  value       = module.sql_server.database_ids
}

output "private_dns_records" {
  description = "DNS records Azure registered for the example's private endpoints."
  value       = module.sql_server.private_dns_records
}
