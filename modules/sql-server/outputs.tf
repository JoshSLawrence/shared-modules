output "id" {
  description = "Resource ID of the SQL server."
  value       = azurerm_mssql_server.this.id
}

output "name" {
  description = "Name of the SQL server."
  value       = azurerm_mssql_server.this.name
}

output "fully_qualified_domain_name" {
  description = "Fully qualified domain name of the SQL server (e.g. `sql-myapp-prod.database.windows.net`)."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_ids" {
  description = "Resource IDs of the databases, keyed like `databases`."
  value       = { for k, db in azurerm_mssql_database.this : k => db.id }
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
