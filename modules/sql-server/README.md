<!-- BEGIN_TF_DOCS -->
# sql-server

Azure SQL logical server with Entra ID authentication only, databases, private endpoints, auditing and diagnostics

## Usage

Reference this module from a root (or child) module, pinned to a released, module-scoped tag:

```hcl
module "sql-server" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/sql-server?ref=sql-server/vX.Y.Z"

  # module inputs...
}
```

Or over SSH:

```hcl
module "sql-server" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/sql-server?ref=sql-server/vX.Y.Z"

  # module inputs...
}
```

Always pin `ref` to a released tag — see [Versioning and Releases](../../CONTRIBUTING.md#versioning-and-releases) — rather than a branch. Released versions of this module are listed on the repo's [Releases](https://github.com/JoshSLawrence/shared-modules/releases) page as `sql-server/vX.Y.Z`.

See [CHANGELOG.md](./CHANGELOG.md) for version history and upgrade notes.

## Defaults

The server is private and locked down unless you opt out:

- **Entra ID authentication only**: SQL logins are always disabled. The
  `entra_admin` is the server's administrator; grant everyone else access
  inside each database (`CREATE USER [name] FROM EXTERNAL PROVIDER`).
- **Private** (`public_network_access_enabled = false`): no public
  endpoint; reach the server through `private_endpoints` (sub-resource
  `sqlServer`). `public_network_access_enabled = true` enables the public
  endpoint, but this module creates no firewall rules: Azure SQL denies
  every client until you add `azurerm_mssql_firewall_rule` resources for
  `id`.
- **TLS 1.2** minimum.
- Optional `diagnostic_settings` (database logs and metrics to Log
  Analytics), `auditing_enabled` (server auditing to the same workspace),
  `lock` (an Azure management lock against deletion) and `role_assignments`
  (Azure RBAC on the server).

Creating users and permissions inside a database uses the data plane: the
identity doing so needs network access to the server (e.g. through its
private endpoint).

## Auditing and diagnostics

Setting `diagnostic_settings` creates one diagnostic setting per database,
sending `log_categories` (all logs by default) and `metric_categories`
(`Basic`, `InstanceAndAppAdvanced` and `WorkloadManagement` by default).

Server auditing is opt-in with `auditing_enabled = true` (it needs
`diagnostic_settings` for the workspace and setting name). Azure Monitor
reads audit events (`SQLSecurityAuditEvents`) from a diagnostic setting on
the `master` database, so the module creates that setting and then the
server's extended auditing policy.

## Private DNS

Clients resolve a private endpoint through an A record in the service's
`privatelink.database.windows.net` private DNS zone. Either this module
registers it, or something else does:

- **Module-managed** (default): pass each endpoint's `private_dns_zone_ids`.
  The module adds a DNS zone group, and Azure writes, updates and deletes
  the A record with the endpoint.
- **Policy-managed**: set `private_endpoints_manage_dns_zone_group = false`
  and leave `private_dns_zone_ids` out. An Azure Policy (e.g. the built-in
  "Configure ... private endpoints to use private DNS zones" policies used by
  Azure landing zones) attaches the zone group after the endpoint is
  created, and the module leaves it alone on later applies.

Either way, the `private_dns_records` output lists the registered records
(zone, host name, type and IP).

## Example

```hcl
module "sql_server" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/sql-server?ref=sql-server/vX.Y.Z"

  name                = "sql-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus"

  entra_admin = {
    login     = "sg-sql-admins"
    object_id = "00000000-0000-0000-0000-000000000000"
  }

  databases = {
    app = {}
  }

  private_endpoints = {
    sqlServer = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.sql.id]
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = data.azurerm_log_analytics_workspace.this.id
  }
  auditing_enabled = true

  lock = {
    kind = "CanNotDelete"
  }
}
```

See [examples/](./examples) for complete root modules.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.audit](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.database](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_mssql_database.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_database) | resource |
| [azurerm_mssql_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_server) | resource |
| [azurerm_mssql_server_extended_auditing_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_server_extended_auditing_policy) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_auditing_enabled"></a> [auditing\_enabled](#input\_auditing\_enabled) | Audit the server to Log Analytics. Creates a diagnostic setting on the<br/>`master` database for `SQLSecurityAuditEvents` (Azure Monitor reads audit<br/>events from there) and the server's extended auditing policy. Uses the<br/>workspace and setting name from `diagnostic_settings`, which must be set.<br/>Database logs and metrics are controlled by `diagnostic_settings` alone. | `bool` | `false` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | Databases to create on the server, keyed by an arbitrary static name.<br/><br/>- `name` - database name. Defaults to the key.<br/>- `sku_name` - service objective, e.g. `S0`, `GP_Gen5_2` or `GP_S_Gen5_2`<br/>  (serverless).<br/>- `max_size_gb` - maximum size in GB. `null` (the default) lets Azure<br/>  use the default for the SKU.<br/>- `storage_account_type` - backup storage redundancy: `Geo`, `GeoZone`,<br/>  `Local` or `Zone`.<br/>- `collation` - database collation.<br/>- `zone_redundant` - spread replicas across availability zones.<br/>- `auto_pause_delay_in_minutes` - serverless General Purpose (`GP_S_*`)<br/>  only: pause after this many idle minutes (15-10080), or `-1` to never<br/>  pause. `null` keeps Azure's default.<br/>- `min_capacity` - serverless (`GP_S_*` or `HS_S_*`) only: minimum<br/>  vCores while running (e.g. `0.5`). `null` keeps Azure's default. | <pre>map(object({<br/>    name                 = optional(string)<br/>    sku_name             = optional(string, "S0")<br/>    max_size_gb          = optional(number)<br/>    storage_account_type = optional(string, "Geo")<br/>    collation            = optional(string, "SQL_Latin1_General_CP1_CI_AS")<br/>    zone_redundant       = optional(bool, false)<br/>    # Serverless only (GP_S_* / HS_S_* SKUs)<br/>    auto_pause_delay_in_minutes = optional(number)<br/>    min_capacity                = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Send the databases' logs and metrics to a Log Analytics workspace (and,<br/>with `auditing_enabled`, the server's audit events). `null` (the default)<br/>disables diagnostics.<br/><br/>- `log_analytics_workspace_id` - resource ID of the workspace.<br/>- `name` - name of every diagnostic setting created.<br/>- `log_categories` - database log categories to send. `null` (the<br/>  default) sends every category (`allLogs`); `[]` sends none.<br/>- `metric_categories` - database metric categories to send. `null` (the<br/>  default) sends `Basic`, `InstanceAndAppAdvanced` and<br/>  `WorkloadManagement`; `[]` sends none.<br/><br/>Each setting must send at least one log or metric category. | <pre>object({<br/>    log_analytics_workspace_id = string<br/>    name                       = optional(string, "diag-log-analytics")<br/>    log_categories             = optional(list(string))<br/>    metric_categories          = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_entra_admin"></a> [entra\_admin](#input\_entra\_admin) | Entra ID administrator of the server. The server accepts Entra ID<br/>authentication only; SQL logins are always disabled.<br/><br/>- `login` - display name or user principal name of the administrator.<br/>- `object_id` - object ID of the user, group or service principal.<br/>  Prefer a group so administrators can change without touching the server.<br/>- `tenant_id` - Entra ID tenant of the administrator. `null` (the<br/>  default) uses the tenant of the identity running OpenTofu. | <pre>object({<br/>    login     = string<br/>    object_id = string<br/>    tenant_id = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region to create the SQL server in (e.g. `eastus`). | `string` | n/a | yes |
| <a name="input_lock"></a> [lock](#input\_lock) | Management lock on the server, protecting it from accidental deletion<br/>(`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to<br/>`lock-<server name>`. `null` (the default) creates no lock.<br/><br/>Azure refuses to delete role assignments and diagnostic settings under a<br/>scope with a `CanNotDelete` lock, so revoking a grant or changing<br/>diagnostics needs the lock lifted first. | <pre>object({<br/>    kind  = string<br/>    name  = optional(string)<br/>    notes = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the SQL server (e.g. `sql-myapp-prod`). Must be globally unique; it becomes the `<name>.database.windows.net` host name. | `string` | n/a | yes |
| <a name="input_outbound_network_restriction_enabled"></a> [outbound\_network\_restriction\_enabled](#input\_outbound\_network\_restriction\_enabled) | Restrict the server's outbound connections to the allowed FQDNs (e.g. to<br/>limit data exfiltration through features such as `OPENROWSET`). This<br/>module can't set the allowed FQDNs, so enabling it blocks all outbound<br/>connections: add `azurerm_mssql_outbound_firewall_rule` resources for any<br/>FQDNs the server must reach. | `bool` | `false` | no |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints to create, keyed by target sub-resource. SQL server has<br/>a single sub-resource, `sqlServer`.<br/><br/>- `subnet_id` - subnet to place the endpoint's network interface in.<br/>- `private_dns_zone_ids` - private DNS zones to register the<br/>  endpoint in (normally the `privatelink.database.windows.net` zone).<br/>  Leave empty when DNS is managed elsewhere: set<br/>  `private_endpoints_manage_dns_zone_group = false` if an Azure<br/>  Policy registers the endpoints.<br/>- `private_ip_address` - static IP from the subnet (e.g.<br/>  `cidrhost(<subnet prefix>, 5)`). `null` lets Azure assign one.<br/>- `name` / `network_interface_name` - default to<br/>  `pep-<server name>-sqlserver` and `nic-pep-<server name>-sqlserver`.<br/>- `resource_group_name` / `location` - default to the server's. | <pre>map(object({<br/>    subnet_id              = string<br/>    private_dns_zone_ids   = optional(list(string), [])<br/>    private_ip_address     = optional(string)<br/>    name                   = optional(string)<br/>    network_interface_name = optional(string)<br/>    resource_group_name    = optional(string)<br/>    location               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Who registers `private_endpoints` in private DNS:<br/><br/>- `true` (the default) - this module: each endpoint gets a private DNS<br/>  zone group for its `private_dns_zone_ids`, and Azure writes the A<br/>  records.<br/>- `false` - something else, typically an Azure Policy that attaches a<br/>  zone group pointing at centrally managed zones after the endpoint is<br/>  created (as in Azure landing zones). The module leaves zone groups<br/>  alone so applies don't remove them, and `private_dns_zone_ids` must be<br/>  empty.<br/><br/>Changing this recreates the endpoints. | `bool` | `true` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Network access to the server:<br/><br/>- `false` (the default) - private: the public endpoint is disabled and<br/>  the server is reachable only through `private_endpoints`.<br/>- `true` - the public endpoint is enabled, but this module creates no<br/>  firewall rules: Azure SQL denies every client until you add<br/>  `azurerm_mssql_firewall_rule` resources for `id`. Clients still need<br/>  Entra ID authentication. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create the SQL server (and its private endpoints, unless overridden) in. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Azure RBAC role assignments scoped to the server, keyed by an arbitrary<br/>static name, e.g. to let an identity manage the server (not its data;<br/>data access is granted inside each database to Entra ID principals):<pre>hcl<br/>role_assignments = {<br/>  deployer_contributor = {<br/>    role_definition_id_or_name = "SQL Server Contributor"<br/>    principal_id               = data.azurerm_client_config.current.object_id<br/>  }<br/>}</pre>`role_definition_id_or_name` takes a built-in role name or a full role<br/>definition resource ID (starting with `/`). | <pre>map(object({<br/>    role_definition_id_or_name       = string<br/>    principal_id                     = string<br/>    principal_type                   = optional(string)<br/>    description                      = optional(string)<br/>    condition                        = optional(string)<br/>    condition_version                = optional(string)<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every resource this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_database_ids"></a> [database\_ids](#output\_database\_ids) | Resource IDs of the databases, keyed like `databases`. |
| <a name="output_fully_qualified_domain_name"></a> [fully\_qualified\_domain\_name](#output\_fully\_qualified\_domain\_name) | Fully qualified domain name of the SQL server (e.g. `sql-myapp-prod.database.windows.net`). |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the SQL server. |
| <a name="output_name"></a> [name](#output\_name) | Name of the SQL server. |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | DNS records Azure registered for this module's private endpoints (one<br/>per record), e.g. to check name resolution or document the network:<br/><br/>- `resource` / `subresource` - the resource and sub-resource (the<br/>  `private_endpoints` key) the record points at.<br/>- `zone_name` - private DNS zone holding the record (e.g.<br/>  `privatelink.database.windows.net`).<br/>- `name` / `fqdn` - host name within the zone and its fully qualified<br/>  name.<br/>- `type` - record type (`A`).<br/>- `ip_addresses` - the endpoint's private IP address(es).<br/>- `ttl` - time to live, in seconds.<br/><br/>Includes records registered by an Azure Policy when<br/>`private_endpoints_manage_dns_zone_group` is `false`, once the policy<br/>has run and state is refreshed. Known after apply. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`. |
<!-- END_TF_DOCS -->