variable "name" {
  type        = string
  description = "Name of the storage account (e.g. `stmyappprod`). Must be globally unique."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 lowercase letters and digits."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the storage account (and its private endpoints, unless overridden) in."
}

variable "location" {
  type        = string
  description = "Azure region to create the storage account in (e.g. `eastus`)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to every resource this module creates."
  default     = {}
  nullable    = false
}

variable "account_kind" {
  type        = string
  description = "Storage account kind: `StorageV2` (general purpose v2), `BlockBlobStorage` or `FileStorage` (both Premium only)."
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "account_kind must be \"StorageV2\", \"BlockBlobStorage\" or \"FileStorage\"."
  }
}

variable "account_tier" {
  type        = string
  description = "Performance tier: `Standard` or `Premium`."
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be \"Standard\" or \"Premium\"."
  }
}

variable "account_replication_type" {
  type        = string
  description = "Replication: `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS` or `RAGZRS`."
  default     = "RAGRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "access_tier" {
  type        = string
  description = "Default access tier for blob data: `Hot`, `Cool` or `Cold`. Ignored for Premium accounts."
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Cold"], var.access_tier)
    error_message = "access_tier must be \"Hot\", \"Cool\" or \"Cold\"."
  }
}

variable "is_hns_enabled" {
  type        = bool
  description = "Enable the hierarchical namespace, making this an Azure Data Lake Storage Gen2 account (required for Synapse). Can't be changed after creation."
  default     = false
}

variable "infrastructure_encryption_enabled" {
  type        = bool
  description = "Encrypt data a second time at the infrastructure level, with a different algorithm and key. Can't be changed after creation."
  default     = true
}

variable "shared_access_key_enabled" {
  type        = bool
  description = <<-EOT
    Allow Shared Key (account key and SAS) authorization. `false` (the
    default) requires Entra ID for every request. Callers that manage data
    plane objects with OpenTofu then need `storage_use_azuread = true` in
    their azurerm provider block.
  EOT
  default     = false
}

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Network access to the account:

    - `false` (the default) - private: the public endpoints are disabled and
      the account is reachable only through `private_endpoints`.
    - `true` - public: the endpoints accept traffic from every network
      (still subject to Entra ID authorization).
  EOT
  default     = false
}

variable "blob_properties" {
  type = object({
    versioning_enabled              = optional(bool, false)
    change_feed_enabled             = optional(bool, false)
    delete_retention_days           = optional(number, 7)
    container_delete_retention_days = optional(number, 7)
  })
  description = <<-EOT
    Blob service data protection:

    - `versioning_enabled` - keep previous versions of overwritten blobs.
    - `change_feed_enabled` - log blob changes to the change feed.
    - `delete_retention_days` / `container_delete_retention_days` - soft
      delete retention (1-365 days) for blobs and containers; `0` disables
      it.

    Synapse's default storage doesn't support versioning or soft delete; the
    synapse-workspace module turns them off for the account it creates.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for d in [var.blob_properties.delete_retention_days, var.blob_properties.container_delete_retention_days] :
      d >= 0 && d <= 365 && floor(d) == d
    ])
    error_message = "blob_properties delete retention days must be whole numbers between 1 and 365, or 0 to disable soft delete."
  }
}

variable "containers" {
  type = map(object({
    name     = optional(string)
    metadata = optional(map(string), {})
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string)
      description                      = optional(string)
      condition                        = optional(string)
      condition_version                = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
  }))
  description = <<-EOT
    Private blob containers (Data Lake file systems when `is_hns_enabled` is
    `true`) to create, keyed by an arbitrary static name. `name` defaults to
    the key.

    `role_assignments` grants Azure RBAC roles scoped to the container alone
    (same shape as the account-level `role_assignments`), e.g. Storage Blob
    Data Reader on one container, so a principal sees that container's data
    and no other's.

    Containers are created through Azure Resource Manager, not the storage
    data plane, so OpenTofu doesn't need network access to a private account
    or Shared Key auth to manage them.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, c in var.containers :
      can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9]){2,62}$", coalesce(c.name, k)))
    ])
    error_message = "Container names must be 3-63 lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = alltrue(flatten([for c in values(var.containers) : [for ra in values(c.role_assignments) : contains(["User", "Group", "ServicePrincipal"], coalesce(ra.principal_type, "User"))]]))
    error_message = "containers[*].role_assignments[*].principal_type must be \"User\", \"Group\" or \"ServicePrincipal\"."
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
    Private endpoints to create, keyed by target sub-resource: `blob`, `dfs`,
    `file`, `queue`, `table` or `web` (or their `_secondary` variants for
    RA-GRS/RA-GZRS accounts). Data Lake clients need both `blob` and `dfs`.

    - `subnet_id` - subnet to place the endpoint's network interface in.
    - `private_dns_zone_ids` - private DNS zones to register the
      endpoint in (e.g. `privatelink.blob.core.windows.net` for `blob`,
      `privatelink.dfs.core.windows.net` for `dfs`). Leave empty when
      DNS is managed elsewhere: set
      `private_endpoints_manage_dns_zone_group = false` if an Azure
      Policy registers the endpoints.
    - `private_ip_address` - static IP from the subnet (e.g.
      `cidrhost(<subnet prefix>, 4)`). `null` lets Azure assign one.
    - `name` / `network_interface_name` - default to
      `pep-<account name>-<sub-resource>` and `nic-pep-<account name>-<sub-resource>`.
    - `resource_group_name` / `location` - default to the account's.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k in keys(var.private_endpoints) :
      contains(["blob", "blob_secondary", "dfs", "dfs_secondary", "file", "file_secondary", "queue", "queue_secondary", "table", "table_secondary", "web", "web_secondary"], k)
    ])
    error_message = "private_endpoints keys must be storage sub-resources: blob, dfs, file, queue, table or web (optionally with a _secondary suffix)."
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
    Send the account's metrics, and the blob service's logs and metrics, to a
    Log Analytics workspace. `null` (the default) disables diagnostics.

    - `log_categories`: blob service log categories to enable. `null`
      (the default) enables `StorageRead`, `StorageWrite` and `StorageDelete`;
      `[]` enables none.
    - `metric_categories`: metric categories to enable on both the account
      and the blob service. `null` (the default) enables `Transaction`; `[]`
      enables none. The account-level setting is only created when at least
      one metric category is enabled.

    At least one log or metric category must end up enabled.
  EOT
  default     = null

  validation {
    condition = var.diagnostic_settings == null || (
      length(try(var.diagnostic_settings.log_categories, null) == null ? ["StorageRead", "StorageWrite", "StorageDelete"] : var.diagnostic_settings.log_categories) +
      length(try(var.diagnostic_settings.metric_categories, null) == null ? ["Transaction"] : var.diagnostic_settings.metric_categories) > 0
    )
    error_message = "diagnostic_settings must enable at least one log or metric category: set log_categories and/or metric_categories to a non-empty list (or leave them null for the defaults), or set diagnostic_settings to null."
  }
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string)
    notes = optional(string)
  })
  description = <<-EOT
    Management lock on the storage account, protecting it from accidental
    deletion (`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to
    `lock-<account name>`. `null` (the default) creates no lock.

    A `ReadOnly` lock also blocks listing account keys and creating
    containers through Azure Resource Manager.

    Azure refuses to delete role assignments and diagnostic settings under a
    scope with a `CanNotDelete` lock, so revoking a grant or changing
    diagnostics needs the lock lifted first.
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
    Azure RBAC role assignments scoped to the storage account, keyed by an
    arbitrary static name, e.g. to give a Data Factory access to blob data:

    ```hcl
    role_assignments = {
      adf_blob_contributor = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = module.data_factory.identity_principal_id
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
