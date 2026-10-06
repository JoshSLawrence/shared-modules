output "data_factory_id" {
  description = "Resource ID of the example Data Factory."
  value       = module.data_factory.id
}

output "managed_private_endpoint_ids" {
  description = "Managed private endpoints to approve on the data lake and Key Vault."
  value       = module.data_factory.managed_private_endpoint_ids
}

output "private_dns_records" {
  description = "DNS records Azure registered for the example's private endpoints."
  value = concat(
    module.data_factory.private_dns_records,
    module.data_lake.private_dns_records,
    module.key_vault.private_dns_records,
  )
}
