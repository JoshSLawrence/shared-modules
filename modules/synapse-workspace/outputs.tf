output "id" {
  description = "Resource ID of the Synapse workspace."
  value       = azurerm_synapse_workspace.this.id
}

output "name" {
  description = "Name of the Synapse workspace."
  value       = azurerm_synapse_workspace.this.name
}

output "connectivity_endpoints" {
  description = "The workspace's endpoints (`dev`, `sql`, `sqlOnDemand`, `web`)."
  value       = azurerm_synapse_workspace.this.connectivity_endpoints
}

output "identity_principal_id" {
  description = "Object ID of the workspace's system-assigned managed identity, e.g. to grant it access to other resources."
  value       = azurerm_synapse_workspace.this.identity[0].principal_id
}

output "managed_resource_group_name" {
  description = "Name of the resource group holding the workspace's managed resources."
  value       = azurerm_synapse_workspace.this.managed_resource_group_name
}

output "storage_account_id" {
  description = "Resource ID of the workspace's default storage account (created or existing)."
  value       = local.storage_account_id
}

output "storage_account_name" {
  description = "Name of the default storage account this module created. `null` when using `existing_storage`."
  value       = var.storage_account == null ? null : module.storage_account[0].name
}

output "storage_private_endpoints" {
  description = "Private endpoints of the default storage account this module created, keyed by sub-resource. Empty when using `existing_storage`."
  value       = var.storage_account == null ? {} : module.storage_account[0].private_endpoints
}

output "data_lake_filesystem_id" {
  description = "Data Lake file system the workspace uses as its default storage."
  value       = local.data_lake_filesystem_id
}

output "sql_administrator_login" {
  description = "SQL administrator login name."
  value       = azurerm_synapse_workspace.this.sql_administrator_login
}

output "sql_administrator_password" {
  description = "SQL administrator password (supplied or generated)."
  value       = local.sql_administrator_password
  sensitive   = true
}

output "sql_administrator_password_secret_id" {
  description = "Versionless ID of the Key Vault secret holding the SQL administrator password. `null` unless `sql_administrator_password_secret` is set."
  value       = one(azurerm_key_vault_secret.sql_administrator_password[*].versionless_id)
}

output "private_endpoints" {
  description = "Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`."
  value = {
    for k, pe in local.private_endpoints_created : k => {
      id                 = pe.id
      private_ip_address = pe.private_service_connection[0].private_ip_address
    }
  }
}

output "managed_private_endpoint_ids" {
  description = "IDs of the managed private endpoints created, keyed like `var.managed_private_endpoints`."
  value       = { for k, mpe in azurerm_synapse_managed_private_endpoint.this : k => mpe.id }
}

output "storage_managed_private_endpoint_ids" {
  description = "IDs of the managed private endpoints to the default storage account, keyed by sub-resource."
  value       = { for k, mpe in azurerm_synapse_managed_private_endpoint.storage : k => mpe.id }
}

output "spark_pool_ids" {
  description = "IDs of the Spark pools created, keyed like `var.spark_pools`."
  value       = { for k, p in azurerm_synapse_spark_pool.this : k => p.id }
}

output "private_dns_records" {
  description = <<-EOT
    DNS records Azure registered for this module's private endpoints,
    including those of the default storage account it creates (one per
    record), e.g. to check name resolution or document the network:

    - `resource` / `subresource` - the resource and sub-resource (the
      `private_endpoints` key) the record points at.
    - `zone_name` - private DNS zone holding the record (e.g.
      `privatelink.blob.core.windows.net`).
    - `name` / `fqdn` - host name within the zone and its fully qualified
      name.
    - `type` - record type (`A`).
    - `ip_addresses` - the endpoint's private IP address(es).
    - `ttl` - time to live, in seconds.

    Includes records registered by an Azure Policy when
    `private_endpoints_manage_dns_zone_group` is `false`, once the policy
    has run and state is refreshed. Known after apply.
  EOT
  value = concat(
    flatten([
      for subresource, pe in local.private_endpoints_created : [
        for zone in pe.private_dns_zone_configs : [
          for record in zone.record_sets : {
            resource     = var.name
            subresource  = subresource
            zone_name    = basename(zone.private_dns_zone_id)
            name         = record.name
            fqdn         = record.fqdn
            type         = record.type
            ip_addresses = record.ip_addresses
            ttl          = record.ttl
          }
        ]
      ]
    ]),
    var.storage_account == null ? [] : module.storage_account[0].private_dns_records,
  )
}
