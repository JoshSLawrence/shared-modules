output "storage_account_id" {
  description = "Resource ID of the example storage account."
  value       = module.storage_account.id
}

output "data_lake_filesystem_ids" {
  description = "Data Lake file system IDs of the example containers."
  value       = { for k, c in module.storage_account.containers : k => c.data_lake_filesystem_id }
}

output "private_dns_records" {
  description = "DNS records Azure registered for the example's private endpoints."
  value       = module.storage_account.private_dns_records
}
