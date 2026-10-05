output "synapse_workspace_id" {
  description = "Resource ID of the example Synapse workspace."
  value       = module.synapse_workspace.id
}

output "storage_account_name" {
  description = "Name of the workspace's default storage account."
  value       = module.synapse_workspace.storage_account_name
}

output "private_endpoint_ips" {
  description = "Private IPs of the workspace's private endpoints, keyed by sub-resource."
  value       = { for k, pe in module.synapse_workspace.private_endpoints : k => pe.private_ip_address }
}

output "private_dns_records" {
  description = "DNS records Azure registered for the example's private endpoints."
  value       = module.synapse_workspace.private_dns_records
}
