variable "name" {
  type        = string
  description = "Name of the Synapse workspace (e.g. `synw-myapp-prod`). Must be globally unique."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$", var.name)) && !strcontains(var.name, "-ondemand")
    error_message = "name must be 1-50 lowercase letters, digits and hyphens, start and end with a letter or digit, and not contain \"-ondemand\"."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the workspace (and, unless overridden, its storage account and private endpoints) in."
}

variable "location" {
  type        = string
  description = "Azure region to create the workspace and its storage account in (e.g. `eastus`)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to every resource this module creates, including the storage account."
  default     = {}
  nullable    = false
}

# --- Default (primary) storage ------------------------------------------------

variable "storage_account" {
  type = object({
    name                                    = string
    filesystem_name                         = optional(string, "synapse")
    account_replication_type                = optional(string, "RAGRS")
    infrastructure_encryption_enabled       = optional(bool, true)
    public_network_access_enabled           = optional(bool)
    private_endpoints_manage_dns_zone_group = optional(bool)
    private_endpoints = optional(map(object({
      subnet_id              = string
      private_dns_zone_ids   = optional(list(string), [])
      private_ip_address     = optional(string)
      name                   = optional(string)
      network_interface_name = optional(string)
      resource_group_name    = optional(string)
      location               = optional(string)
    })), {})
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string)
      description                      = optional(string)
      condition                        = optional(string)
      condition_version                = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
  })
  description = <<-EOT
    Create the workspace's default ADLS Gen2 storage account with the
    storage-account module (in the same resource group and region, with the
    same tags, `lock` and `diagnostic_settings`). Set this or
    `existing_storage`, not both.

    - `name` - storage account name (e.g. `stsynwmyappprod`).
    - `filesystem_name` - file system (container) for the workspace; default
      `synapse`.
    - `public_network_access_enabled` - defaults to the workspace's
      `public_network_access_enabled`, so a public workspace gets public
      storage it can use straight away and a private workspace gets private
      storage.
    - `private_endpoints_manage_dns_zone_group` - defaults to the
      workspace's `private_endpoints_manage_dns_zone_group`.
    - `private_endpoints`, `account_replication_type`,
      `infrastructure_encryption_enabled` - passed to the storage-account
      module; see its README.
    - `role_assignments` - extra Azure RBAC role assignments on the storage
      account, keyed by an arbitrary static name; the same shape as the
      storage-account module's `role_assignments`. The workspace identity's
      `Storage Blob Data Contributor` is always granted separately.

    Blob versioning and soft delete are always disabled on this account:
    Synapse doesn't support them on its default storage.
  EOT
  default     = null

  # The storage-account module validates these too, but checking here
  # reports the error against the caller's input instead of this module's
  # internal module call.
  validation {
    condition = var.storage_account == null || alltrue([
      for k in keys(try(var.storage_account.private_endpoints, {})) :
      contains(["blob", "blob_secondary", "dfs", "dfs_secondary", "file", "file_secondary", "queue", "queue_secondary", "table", "table_secondary", "web", "web_secondary"], k)
    ])
    error_message = "storage_account.private_endpoints keys must be storage sub-resources: blob, dfs, file, queue, table or web (optionally with a _secondary suffix)."
  }

  validation {
    condition = var.storage_account == null || alltrue([
      for pe in values(try(var.storage_account.private_endpoints, {})) :
      pe.private_ip_address == null || can(cidrnetmask("${coalesce(pe.private_ip_address, "invalid")}/32"))
    ])
    error_message = "storage_account.private_endpoints[*].private_ip_address must be an IPv4 address."
  }

  validation {
    condition = var.storage_account == null || (
      coalesce(try(var.storage_account.private_endpoints_manage_dns_zone_group, null), var.private_endpoints_manage_dns_zone_group) ||
      alltrue([for pe in values(try(var.storage_account.private_endpoints, {})) : length(pe.private_dns_zone_ids) == 0])
    )
    error_message = "storage_account.private_endpoints[*].private_dns_zone_ids must be empty when the storage account's DNS zone groups are managed outside this module (private_endpoints_manage_dns_zone_group is false)."
  }

  validation {
    condition     = var.storage_account == null || alltrue([for ra in values(try(var.storage_account.role_assignments, {})) : contains(["User", "Group", "ServicePrincipal"], coalesce(ra.principal_type, "User"))])
    error_message = "storage_account.role_assignments[*].principal_type must be \"User\", \"Group\" or \"ServicePrincipal\"."
  }
}

variable "existing_storage" {
  type = object({
    data_lake_filesystem_id      = string
    storage_account_id           = string
    assign_blob_data_contributor = optional(bool, true)
  })
  description = <<-EOT
    Use an existing ADLS Gen2 file system as the workspace's default storage
    instead of creating one. Set this or `storage_account`, not both.

    - `data_lake_filesystem_id` - `https://<account>.dfs.core.windows.net/<file system>`
      (e.g. the `data_lake_filesystem_id` of a storage-account module
      container, or `azurerm_storage_data_lake_gen2_filesystem.id`).
    - `storage_account_id` - resource ID of the account holding it.
    - `assign_blob_data_contributor` - grant the workspace's managed
      identity `Storage Blob Data Contributor` on the account (default
      `true`). Synapse needs it; set `false` only if it's granted elsewhere.
  EOT
  default     = null

  validation {
    condition     = (var.storage_account == null) != (var.existing_storage == null)
    error_message = "Set exactly one of storage_account (create the default storage) or existing_storage (use an existing file system)."
  }

  validation {
    condition     = var.existing_storage == null || can(regex("^https://[a-z0-9]{3,24}\\.dfs\\.[^/]+/[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", try(var.existing_storage.data_lake_filesystem_id, "")))
    error_message = "existing_storage.data_lake_filesystem_id must look like https://<account>.dfs.core.windows.net/<file system>."
  }
}

# --- Networking -----------------------------------------------------------------

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Network access to the workspace:

    - `false` (the default) - private: the public endpoints are disabled and
      the workspace (Studio, dev and SQL endpoints) is reachable only through
      `private_endpoints`.
    - `true` - public: the endpoints are enabled and an `AllowAll` firewall
      rule (0.0.0.0-255.255.255.255) admits every network (still subject to
      Entra ID or SQL authentication). Synapse's firewall otherwise blocks
      everything even with public access on.
  EOT
  default     = false
}

variable "azure_services_access_enabled" {
  type        = bool
  description = <<-EOT
    Add the `AllowAllWindowsAzureIps` firewall rule (0.0.0.0-0.0.0.0), which
    lets Azure services reach the workspace's public endpoints. Only valid
    with `public_network_access_enabled = true`; a private workspace is
    reached through `private_endpoints` instead. Default `false`.

    This is separate from `public_network_access_enabled`'s `AllowAll` rule
    (an IP range): it is the portal's "Allow Azure services and resources to
    access this workspace" setting, which also covers traffic the IP rule
    doesn't, such as Azure services reaching the workspace from Azure
    networks via service endpoints, and features and portal checks that look
    for this rule.
  EOT
  default     = false
  nullable    = false

  validation {
    condition     = !var.azure_services_access_enabled || var.public_network_access_enabled
    error_message = "azure_services_access_enabled requires public_network_access_enabled = true: the AllowAllWindowsAzureIps firewall rule only applies to the public endpoints."
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
    Private endpoints to create, keyed by target sub-resource:

    - `Dev` - Synapse Studio and the dev (REST/data plane) endpoint
      (`privatelink.dev.azuresynapse.net`).
    - `Sql` - dedicated SQL pools (`privatelink.sql.azuresynapse.net`).
    - `SqlOnDemand` - serverless SQL (`privatelink.sql.azuresynapse.net`).

    Per endpoint:

    - `subnet_id` - subnet to place the endpoint's network interface in.
    - `private_dns_zone_ids` - private DNS zones to register the
      endpoint in. Leave empty when DNS is managed elsewhere: set
      `private_endpoints_manage_dns_zone_group = false` if an Azure
      Policy registers the endpoints.
    - `private_ip_address` - static IP from the subnet. `null` lets Azure
      assign one.
    - `name` / `network_interface_name` - default to
      `pep-<workspace name>-<sub-resource>` and `nic-pep-<workspace name>-<sub-resource>`
      (sub-resource lowercased).
    - `resource_group_name` / `location` - default to the workspace's.

    Loading Synapse Studio itself privately also needs a Synapse private link
    hub (sub-resource `Web`), which isn't workspace-specific and isn't
    created by this module.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : contains(["Dev", "Sql", "SqlOnDemand"], k)])
    error_message = "private_endpoints keys must be Synapse sub-resources: Dev, Sql or SqlOnDemand (case-sensitive)."
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

variable "data_exfiltration_protection_enabled" {
  type        = bool
  description = <<-EOT
    Only allow outbound connections from the managed virtual network through
    approved managed private endpoints (to tenants in
    `linking_allowed_for_aad_tenant_ids`). Can't be changed after creation.
  EOT
  default     = false

}

variable "linking_allowed_for_aad_tenant_ids" {
  type        = list(string)
  description = "Entra ID tenants that managed private endpoints may connect to while data exfiltration protection is enabled. Requires `data_exfiltration_protection_enabled`."
  default     = []
  nullable    = false

  validation {
    condition     = var.data_exfiltration_protection_enabled || length(var.linking_allowed_for_aad_tenant_ids) == 0
    error_message = "linking_allowed_for_aad_tenant_ids only applies when data_exfiltration_protection_enabled is true."
  }
}

variable "managed_private_endpoints" {
  type = map(object({
    target_resource_id = string
    subresource_name   = string
    name               = optional(string)
  }))
  description = <<-EOT
    Managed private endpoints from the workspace's managed virtual network,
    keyed by an arbitrary static name (the default endpoint name), e.g. so
    Spark can reach a private storage account:

    ```hcl
    managed_private_endpoints = {
      default-storage-dfs = {
        target_resource_id = module.storage_account.id
        subresource_name   = "dfs"
      }
    }
    ```

    Each endpoint is created pending approval: approve it on the target
    resource's private endpoint connections before it carries traffic.
  EOT
  default     = {}
  nullable    = false


  validation {
    condition     = alltrue([for k, mpe in var.managed_private_endpoints : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,78}[a-zA-Z0-9_]$", coalesce(mpe.name, k)))])
    error_message = "Managed private endpoint names must be 2-80 letters, digits, '_', '.' or '-', starting with a letter or digit and ending with a letter, digit or '_'."
  }
}

variable "storage_managed_private_endpoints" {
  type        = list(string)
  description = <<-EOT
    Sub-resources of the default storage account (`dfs` and/or `blob`) to
    create managed private endpoints to, so Spark and serverless SQL can
    reach it from the managed virtual network when its public access is
    disabled. Named `<storage account name>-<sub-resource>`.

    Like any managed private endpoint, each is created pending approval and
    through the workspace's dev endpoint (see `managed_private_endpoints`).
  EOT
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.storage_managed_private_endpoints : contains(["blob", "dfs"], s)])
    error_message = "storage_managed_private_endpoints may only contain \"blob\" and \"dfs\"."
  }

}

variable "managed_resource_group_name" {
  type        = string
  description = "Name of the resource group Azure creates to hold the workspace's managed resources. `null` lets Azure generate one."
  default     = null
}

# --- Authentication -------------------------------------------------------------

variable "azuread_authentication_only" {
  type        = bool
  description = <<-EOT
    Allow only Entra ID authentication to the workspace's SQL endpoints
    (`true`, the default), disabling the SQL administrator login. Some
    deployment tooling still needs SQL auth; set `false` if so.
  EOT
  default     = true
}

variable "sql_administrator_login" {
  type        = string
  description = <<-EOT
    SQL administrator login name. Synapse requires one even when
    `azuread_authentication_only` is `true`. Can't be changed after
    creation.
  EOT
  default     = "sqladminuser"

  validation {
    condition = (
      can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,127}$", var.sql_administrator_login)) &&
      !contains(["admin", "administrator", "sa", "root", "dbmanager", "loginmanager", "dbo", "guest", "public"], lower(var.sql_administrator_login))
    )
    error_message = "sql_administrator_login must be 1-128 letters, digits or '_', start with a letter, and not be a reserved name (admin, administrator, sa, root, dbmanager, loginmanager, dbo, guest, public)."
  }
}

variable "sql_administrator_password" {
  type        = string
  description = <<-EOT
    SQL administrator password to use, e.g. one managed outside OpenTofu.
    8-128 characters with at least three of: lowercase, uppercase, digits and
    symbols. `null` (the default) generates a 32-character password. Synapse
    requires one even when `azuread_authentication_only` is `true`.
  EOT
  default     = null
  sensitive   = true

  validation {
    condition = var.sql_administrator_password == null || (
      length(coalesce(var.sql_administrator_password, "x")) >= 8 &&
      length(coalesce(var.sql_administrator_password, "x")) <= 128 &&
      length([
        for pattern in ["[a-z]", "[A-Z]", "[0-9]", "[^a-zA-Z0-9]"] : pattern
        if can(regex(pattern, coalesce(var.sql_administrator_password, "x")))
      ]) >= 3
    )
    error_message = "sql_administrator_password must be 8-128 characters with at least three of: lowercase letters, uppercase letters, digits and symbols."
  }
}

variable "sql_administrator_password_secret" {
  type = object({
    key_vault_id    = string
    name            = optional(string)
    expiration_date = optional(string)
  })
  description = <<-EOT
    Store the SQL administrator password (generated or supplied) as a Key
    Vault secret
    (e.g. in a vault from the key-vault module). `name` defaults to
    `<workspace name>-sql-admin-password`. `expiration_date` is an optional
    RFC 3339 UTC timestamp (e.g. `2027-01-01T00:00:00Z`). `null` (the
    default) stores it nowhere but state and the sensitive
    `sql_administrator_password` output.

    Writing the secret uses the Key Vault data plane: the identity running
    OpenTofu needs a role like `Key Vault Secrets Officer` on the vault, and
    network access to it (e.g. through its private endpoint).
  EOT
  default     = null

  validation {
    condition     = var.sql_administrator_password_secret == null || can(regex("^[0-9a-zA-Z-]{1,127}$", coalesce(try(var.sql_administrator_password_secret.name, null), "default-name")))
    error_message = "sql_administrator_password_secret.name must be 1-127 letters, digits or hyphens."
  }

  validation {
    condition     = var.sql_administrator_password_secret == null || try(var.sql_administrator_password_secret.expiration_date, null) == null || can(formatdate("YYYY", coalesce(try(var.sql_administrator_password_secret.expiration_date, null), "invalid")))
    error_message = "sql_administrator_password_secret.expiration_date must be an RFC 3339 timestamp (e.g. 2027-01-01T00:00:00Z)."
  }
}

variable "entra_admin" {
  type = object({
    login     = string
    object_id = string
    tenant_id = optional(string)
  })
  description = <<-EOT
    Entra ID administrator for the workspace's SQL endpoints (a user or,
    preferably, a group). `login` is the user principal name or group
    display name. `tenant_id` defaults to the tenant of the identity running
    OpenTofu. `null` (the default) sets no Entra administrator.

    This is the SQL administrator only. Grant Synapse RBAC roles (e.g.
    `Synapse Administrator`) with `synapse_role_assignments`.
  EOT
  default     = null

  validation {
    condition     = var.entra_admin == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", try(var.entra_admin.object_id, "")))
    error_message = "entra_admin.object_id must be a GUID."
  }
}

# --- Compute and source control -------------------------------------------------

variable "spark_pools" {
  type = map(object({
    name                                = optional(string)
    spark_version                       = optional(string, "3.5")
    node_size_family                    = optional(string, "MemoryOptimized")
    node_size                           = optional(string, "Small")
    node_count                          = optional(number)
    auto_scale_min_node_count           = optional(number, 3)
    auto_scale_max_node_count           = optional(number, 10)
    auto_pause_delay_in_minutes         = optional(number, 15)
    cache_size                          = optional(number)
    dynamic_executor_allocation_enabled = optional(bool, false)
    session_level_packages_enabled      = optional(bool, false)
    spark_events_folder                 = optional(string, "/events")
    spark_log_folder                    = optional(string, "/logs")
  }))
  description = <<-EOT
    Apache Spark pools, keyed by an arbitrary static name. `name` defaults to
    the key; keep it free of environment names, since notebooks reference
    pools by name and are promoted between environments unchanged.

    Pools auto-scale between `auto_scale_min_node_count` and
    `auto_scale_max_node_count` nodes (default 3-10) unless `node_count`
    sets a fixed size, and pause after `auto_pause_delay_in_minutes` idle
    (default 15; `0` never pauses).
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, p in var.spark_pools : can(regex("^[a-zA-Z][a-zA-Z0-9]{0,14}$", coalesce(p.name, k)))])
    error_message = "Spark pool names must be 1-15 letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for p in values(var.spark_pools) : contains(["MemoryOptimized", "HardwareAcceleratedFPGA", "HardwareAcceleratedGPU"], p.node_size_family)])
    error_message = "spark_pools[*].node_size_family must be MemoryOptimized, HardwareAcceleratedFPGA or HardwareAcceleratedGPU."
  }

  validation {
    condition     = alltrue([for p in values(var.spark_pools) : contains(["Small", "Medium", "Large", "XLarge", "XXLarge", "XXXLarge"], p.node_size)])
    error_message = "spark_pools[*].node_size must be Small, Medium, Large, XLarge, XXLarge or XXXLarge."
  }

  validation {
    condition     = alltrue([for p in values(var.spark_pools) : p.auto_scale_min_node_count >= 3 && p.auto_scale_min_node_count <= p.auto_scale_max_node_count && p.auto_scale_max_node_count <= 200])
    error_message = "spark_pools auto-scale node counts must satisfy 3 <= min <= max <= 200."
  }

  validation {
    condition     = alltrue([for p in values(var.spark_pools) : p.node_count == null || (coalesce(p.node_count, 0) >= 3 && coalesce(p.node_count, 0) <= 200)])
    error_message = "spark_pools[*].node_count must be between 3 and 200."
  }
}

variable "github_repo" {
  type = object({
    account_name    = string
    repository_name = string
    branch_name     = string
    root_folder     = optional(string, "/")
    git_url         = optional(string)
    last_commit_id  = optional(string)
  })
  description = <<-EOT
    Connect Synapse Studio to a GitHub repository for source control.
    `branch_name` is the collaboration branch and `root_folder` the folder
    holding Synapse artifacts (e.g. `/synapse`). `git_url` is only needed for
    GitHub Enterprise Server. A repository admin still has to approve the
    Synapse app's access. `null` (the default) leaves Git integration off.
  EOT
  default     = null
}

variable "identity_ids" {
  type        = list(string)
  description = "User-assigned managed identities to attach in addition to the always-on system-assigned identity."
  default     = []
  nullable    = false
}

# --- Access, protection and monitoring ------------------------------------------

variable "synapse_role_assignments" {
  type = map(object({
    role_name      = string
    principal_id   = string
    principal_type = optional(string)
  }))
  description = <<-EOT
    Synapse RBAC role assignments (workspace-scoped roles inside Synapse,
    separate from Azure RBAC), keyed by an arbitrary static name, e.g.:

    ```hcl
    synapse_role_assignments = {
      admins = {
        role_name      = "Synapse Administrator"
        principal_id   = "<group object ID>"
        principal_type = "Group"
      }
    }
    ```

    These use the workspace's dev (data plane) endpoint: the identity running
    OpenTofu must be a Synapse Administrator (the workspace creator is one
    automatically) and able to reach the workspace (public access, or the
    `Dev` private endpoint).
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for ra in values(var.synapse_role_assignments) : contains(["User", "Group", "ServicePrincipal"], coalesce(ra.principal_type, "User"))])
    error_message = "synapse_role_assignments[*].principal_type must be \"User\", \"Group\" or \"ServicePrincipal\"."
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
    Azure RBAC role assignments scoped to the workspace, keyed by an
    arbitrary static name. `role_definition_id_or_name` takes a built-in role
    name or a full role definition resource ID (starting with `/`).
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal"], coalesce(ra.principal_type, "User"))])
    error_message = "role_assignments[*].principal_type must be \"User\", \"Group\" or \"ServicePrincipal\"."
  }
}

variable "diagnostic_settings" {
  type = object({
    log_analytics_workspace_id = string
    name                       = optional(string, "diag-log-analytics")
    log_categories             = optional(list(string))
    metric_categories          = optional(list(string))
    storage_log_categories     = optional(list(string))
    storage_metric_categories  = optional(list(string))
  })
  description = <<-EOT
    Send the workspace's logs (and, for a storage account this module
    creates, its storage logs and metrics) to a Log Analytics workspace.
    `null` (the default) disables diagnostics.

    - `log_categories`: workspace log categories to enable. `null` (the
      default) enables the `allLogs` category group; `[]` enables no logs.
    - `metric_categories`: workspace metric categories to enable. `null` or
      `[]` (the default) enables none; the workspace sets no metrics unless
      asked.
    - `storage_log_categories`, `storage_metric_categories`: the same for the
      storage account this module creates (passed as the storage-account
      module's `log_categories` and `metric_categories`). `null` (the
      default) uses that module's defaults; `[]` enables none. Ignored with
      `existing_storage`.

    The workspace's setting must end up with at least one log or metric
    category enabled.
  EOT
  default     = null

  validation {
    condition = var.diagnostic_settings == null || (
      try(length(var.diagnostic_settings.log_categories), 1) +
      try(length(var.diagnostic_settings.metric_categories), 0) > 0
    )
    error_message = "diagnostic_settings must enable at least one workspace log or metric category: leave log_categories null for the allLogs default or list at least one category, or set diagnostic_settings to null."
  }

  validation {
    condition = var.diagnostic_settings == null || (
      try(length(var.diagnostic_settings.storage_log_categories), 1) +
      try(length(var.diagnostic_settings.storage_metric_categories), 1) > 0
    )
    error_message = "diagnostic_settings must enable at least one storage log or metric category: leave storage_log_categories and/or storage_metric_categories null for the storage-account defaults, or list at least one category."
  }
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string)
    notes = optional(string)
  })
  description = <<-EOT
    Management lock on the workspace, and on the storage account this module
    creates, protecting them from accidental deletion (`CanNotDelete`) or any
    change (`ReadOnly`). `name` defaults to `lock-<resource name>`. `null`
    (the default) creates no lock.

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
