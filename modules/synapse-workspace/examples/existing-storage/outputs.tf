output "synapse_workspace_id" {
  description = "Resource ID of the example Synapse workspace."
  value       = module.synapse_workspace.id
}

output "synapse_dev_endpoint" {
  description = "The workspace's dev endpoint."
  value       = module.synapse_workspace.connectivity_endpoints["dev"]
}

output "sql_administrator_password_secret_id" {
  description = "Key Vault secret holding the workspace's SQL administrator password."
  value       = module.synapse_workspace.sql_administrator_password_secret_id
}
