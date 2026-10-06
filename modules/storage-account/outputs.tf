output "id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary blob service endpoint (e.g. `https://stmyappprod.blob.core.windows.net/`)."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_dfs_endpoint" {
  description = "Primary Data Lake (DFS) endpoint (e.g. `https://stmyappprod.dfs.core.windows.net/`)."
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "containers" {
  description = <<-EOT
    Containers created, keyed like `var.containers`, with:

    - `id` - Azure Resource Manager ID of the container.
    - `name` - container name.
    - `data_lake_filesystem_id` - the container's Data Lake file system ID
      (`https://<account>.dfs.core.windows.net/<name>`), as expected by e.g.
      `azurerm_synapse_workspace.storage_data_lake_gen2_filesystem_id`.
      `null` unless `is_hns_enabled` is `true`.
  EOT
  value = {
    for k, c in azurerm_storage_container.this : k => {
      id                      = c.id
      name                    = c.name
      data_lake_filesystem_id = var.is_hns_enabled ? "${azurerm_storage_account.this.primary_dfs_endpoint}${c.name}" : null
    }
  }
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

output "private_dns_records" {
  description = <<-EOT
    DNS records Azure registered for this module's private endpoints (one
    per record), e.g. to check name resolution or document the network:

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
  value = flatten([
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
  ])
}
