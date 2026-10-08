variable "name" {
  type        = string
  description = "Name of the SQL server (e.g. `sql-myapp-prod`). Must be globally unique; it becomes the `<name>.database.windows.net` host name."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be 1-63 characters of lowercase letters, digits and hyphens, and not start or end with a hyphen."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the SQL server (and its private endpoints, unless overridden) in."
}

variable "location" {
  type        = string
  description = "Azure region to create the SQL server in (e.g. `eastus`)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to every resource this module creates."
  default     = {}
  nullable    = false
}

variable "entra_admin" {
  type = object({
    login     = string
    object_id = string
    tenant_id = optional(string)
  })
  description = <<-EOT
    Entra ID administrator of the server. The server accepts Entra ID
    authentication only; SQL logins are always disabled.

    - `login` - display name or user principal name of the administrator.
    - `object_id` - object ID of the user, group or service principal.
      Prefer a group so administrators can change without touching the server.
    - `tenant_id` - Entra ID tenant of the administrator. `null` (the
      default) uses the tenant of the identity running OpenTofu.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.entra_admin.object_id))
    error_message = "entra_admin.object_id must be a GUID."
  }

  validation {
    condition     = var.entra_admin.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", coalesce(var.entra_admin.tenant_id, "unset")))
    error_message = "entra_admin.tenant_id must be a GUID (or null to use the current tenant)."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Network access to the server:

    - `false` (the default) - private: the public endpoint is disabled and
      the server is reachable only through `private_endpoints`.
    - `true` - the public endpoint is enabled, but this module creates no
      firewall rules: Azure SQL denies every client until you add
      `azurerm_mssql_firewall_rule` resources for `id`. Clients still need
      Entra ID authentication.
  EOT
  default     = false
  nullable    = false
}

variable "outbound_network_restriction_enabled" {
  type        = bool
  description = <<-EOT
    Restrict the server's outbound connections to the allowed FQDNs (e.g. to
    limit data exfiltration through features such as `OPENROWSET`). This
    module can't set the allowed FQDNs, so enabling it blocks all outbound
    connections: add `azurerm_mssql_outbound_firewall_rule` resources for any
    FQDNs the server must reach.
  EOT
  default     = false
  nullable    = false
}

variable "databases" {
  type = map(object({
    name                 = optional(string)
    sku_name             = optional(string, "S0")
    max_size_gb          = optional(number)
    storage_account_type = optional(string, "Geo")
    collation            = optional(string, "SQL_Latin1_General_CP1_CI_AS")
    zone_redundant       = optional(bool, false)
    # Serverless only (GP_S_* / HS_S_* SKUs)
    auto_pause_delay_in_minutes = optional(number)
    min_capacity                = optional(number)
  }))
  description = <<-EOT
    Databases to create on the server, keyed by an arbitrary static name.

    - `name` - database name. Defaults to the key.
    - `sku_name` - service objective, e.g. `S0`, `GP_Gen5_2` or `GP_S_Gen5_2`
      (serverless).
    - `max_size_gb` - maximum size in GB. `null` (the default) lets Azure
      use the default for the SKU.
    - `storage_account_type` - backup storage redundancy: `Geo`, `GeoZone`,
      `Local` or `Zone`.
    - `collation` - database collation.
    - `zone_redundant` - spread replicas across availability zones.
    - `auto_pause_delay_in_minutes` - serverless General Purpose (`GP_S_*`)
      only: pause after this many idle minutes (15-10080), or `-1` to never
      pause. `null` keeps Azure's default.
    - `min_capacity` - serverless (`GP_S_*` or `HS_S_*`) only: minimum
      vCores while running (e.g. `0.5`). `null` keeps Azure's default.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for db in values(var.databases) : contains(["Geo", "GeoZone", "Local", "Zone"], db.storage_account_type)])
    error_message = "databases[*].storage_account_type must be \"Geo\", \"GeoZone\", \"Local\" or \"Zone\"."
  }

  # OpenTofu 1.9 doesn't short-circuit || or &&, so nulls are defaulted
  # rather than guarded
  validation {
    condition     = alltrue([for db in values(var.databases) : db.auto_pause_delay_in_minutes == null || startswith(db.sku_name, "GP_S_")])
    error_message = "databases[*].auto_pause_delay_in_minutes only applies to serverless General Purpose SKUs (GP_S_*)."
  }

  validation {
    condition     = alltrue([for db in values(var.databases) : coalesce(db.auto_pause_delay_in_minutes, -1) == -1 || (coalesce(db.auto_pause_delay_in_minutes, -1) >= 15 && coalesce(db.auto_pause_delay_in_minutes, -1) <= 10080)])
    error_message = "databases[*].auto_pause_delay_in_minutes must be -1 (never pause) or between 15 and 10080."
  }

  validation {
    condition     = alltrue([for db in values(var.databases) : db.min_capacity == null || startswith(db.sku_name, "GP_S_") || startswith(db.sku_name, "HS_S_")])
    error_message = "databases[*].min_capacity only applies to serverless SKUs (GP_S_* or HS_S_*)."
  }

  validation {
    condition     = alltrue([for db in values(var.databases) : coalesce(db.min_capacity, 1) > 0])
    error_message = "databases[*].min_capacity must be greater than 0."
  }
}

variable "private_endpoints" {
  type = map(object({
    subnet_id              = string
    private_dns_zone_ids   = optional(list(string), [])
    private_ip_address     = optional(string)
    name                   = optional(string)
    network_interface_name = optional(string)
    resource_group_name    = optional(string)
    location               = optional(string)
  }))
  description = <<-EOT
    Private endpoints to create, keyed by target sub-resource. SQL server has
    a single sub-resource, `sqlServer`.

    - `subnet_id` - subnet to place the endpoint's network interface in.
    - `private_dns_zone_ids` - private DNS zones to register the
      endpoint in (normally the `privatelink.database.windows.net` zone).
      Leave empty when DNS is managed elsewhere: set
      `private_endpoints_manage_dns_zone_group = false` if an Azure
      Policy registers the endpoints.
    - `private_ip_address` - static IP from the subnet (e.g.
      `cidrhost(<subnet prefix>, 5)`). `null` lets Azure assign one.
    - `name` / `network_interface_name` - default to
      `pep-<server name>-sqlserver` and `nic-pep-<server name>-sqlserver`.
    - `resource_group_name` / `location` - default to the server's.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : k == "sqlServer"])
    error_message = "private_endpoints keys must be the sub-resource \"sqlServer\"."
  }

  validation {
    condition     = alltrue([for pe in values(var.private_endpoints) : pe.private_ip_address == null || can(cidrnetmask("${coalesce(pe.private_ip_address, "invalid")}/32"))])
    error_message = "private_endpoints[*].private_ip_address must be an IPv4 address."
  }

  validation {
    condition     = var.private_endpoints_manage_dns_zone_group || alltrue([for pe in values(var.private_endpoints) : length(pe.private_dns_zone_ids) == 0])
    error_message = "private_endpoints[*].private_dns_zone_ids must be empty when private_endpoints_manage_dns_zone_group is false (DNS is then managed outside this module, e.g. by Azure Policy)."
  }
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  description = <<-EOT
    Who registers `private_endpoints` in private DNS:

    - `true` (the default) - this module: each endpoint gets a private DNS
      zone group for its `private_dns_zone_ids`, and Azure writes the A
      records.
    - `false` - something else, typically an Azure Policy that attaches a
      zone group pointing at centrally managed zones after the endpoint is
      created (as in Azure landing zones). The module leaves zone groups
      alone so applies don't remove them, and `private_dns_zone_ids` must be
      empty.

    Changing this recreates the endpoints.
  EOT
  default     = true
  nullable    = false
}

variable "diagnostic_settings" {
  type = object({
    log_analytics_workspace_id = string
    name                       = optional(string, "diag-log-analytics")
    log_categories             = optional(list(string))
    metric_categories          = optional(list(string))
  })
  description = <<-EOT
    Send the databases' logs and metrics to a Log Analytics workspace (and,
    with `auditing_enabled`, the server's audit events). `null` (the default)
    disables diagnostics.

    - `log_analytics_workspace_id` - resource ID of the workspace.
    - `name` - name of every diagnostic setting created.
    - `log_categories` - database log categories to send. `null` (the
      default) sends every category (`allLogs`); `[]` sends none.
    - `metric_categories` - database metric categories to send. `null` (the
      default) sends `Basic`, `InstanceAndAppAdvanced` and
      `WorkloadManagement`; `[]` sends none.

    Each setting must send at least one log or metric category.
  EOT
  default     = null

  validation {
    condition     = var.diagnostic_settings == null || !(try(length(var.diagnostic_settings.log_categories) == 0, false) && try(length(var.diagnostic_settings.metric_categories) == 0, false))
    error_message = "diagnostic_settings must send at least one log or metric category: log_categories and metric_categories can't both be empty."
  }
}

variable "auditing_enabled" {
  type        = bool
  description = <<-EOT
    Audit the server to Log Analytics. Creates a diagnostic setting on the
    `master` database for `SQLSecurityAuditEvents` (Azure Monitor reads audit
    events from there) and the server's extended auditing policy. Uses the
    workspace and setting name from `diagnostic_settings`, which must be set.
    Database logs and metrics are controlled by `diagnostic_settings` alone.
  EOT
  default     = false
  nullable    = false

  validation {
    condition     = !var.auditing_enabled || var.diagnostic_settings != null
    error_message = "auditing_enabled requires diagnostic_settings (it provides the Log Analytics workspace)."
  }
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string)
    notes = optional(string)
  })
  description = <<-EOT
    Management lock on the server, protecting it from accidental deletion
    (`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to
    `lock-<server name>`. `null` (the default) creates no lock.

    A `CanNotDelete` lock also blocks deleting role assignments and diagnostic
    settings under its scope, so revoking a grant or removing a diagnostic
    setting needs the lock lifted first.
  EOT
  default     = null

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string)
    description                      = optional(string)
    condition                        = optional(string)
    condition_version                = optional(string)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  description = <<-EOT
    Azure RBAC role assignments scoped to the server, keyed by an arbitrary
    static name, e.g. to let an identity manage the server (not its data;
    data access is granted inside each database to Entra ID principals):

    ```hcl
    role_assignments = {
      deployer_contributor = {
        role_definition_id_or_name = "SQL Server Contributor"
        principal_id               = data.azurerm_client_config.current.object_id
      }
    }
    ```

    `role_definition_id_or_name` takes a built-in role name or a full role
    definition resource ID (starting with `/`).
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal"], coalesce(ra.principal_type, "User"))])
    error_message = "role_assignments[*].principal_type must be \"User\", \"Group\" or \"ServicePrincipal\"."
  }
}
