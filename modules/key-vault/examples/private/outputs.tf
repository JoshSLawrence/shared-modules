output "key_vault_id" {
  description = "Resource ID of the example Key Vault."
  value       = module.key_vault.id
}

output "key_vault_uri" {
  description = "Data plane URI of the example Key Vault."
  value       = module.key_vault.vault_uri
}

output "private_dns_records" {
  description = "DNS records Azure registered for the example's private endpoints."
  value       = module.key_vault.private_dns_records
}
