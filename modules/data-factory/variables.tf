variable "name" {
  type        = string
  description = "Name of the Data Factory (e.g. `adf-myapp-prod`). Must be globally unique."

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9]|-[a-zA-Z0-9]){2,62}$", var.name))
    error_message = "name must be 3-63 letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the Data Factory (and its private endpoints, unless overridden) in."
}

variable "location" {
  type        = string
  description = "Azure region to create the Data Factory in (e.g. `eastus`)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to every resource this module creates."
  default     = {}
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Enable the factory's public endpoint. When `false` (the default) ADF
    Studio and the factory's APIs are reachable only through private
    endpoints, and self-hosted integration runtimes must connect privately.
  EOT
  default     = false
}

variable "managed_integration_runtime" {
  type = object({
    name             = optional(string, "ir-managed-vnet")
    location         = optional(string, "AutoResolve")
    compute_type     = optional(string, "General")
    core_count       = optional(number, 8)
    time_to_live_min = optional(number, 0)
    cleanup_enabled  = optional(bool, true)
    description      = optional(string, "Azure integration runtime in the managed virtual network.")
  })
  description = <<-EOT
    Create an Azure integration runtime inside the managed virtual network.
    Activities only use managed private endpoints when they run on such a
    runtime; the built-in AutoResolveIntegrationRuntime runs outside it.
    `location` is a region or `AutoResolve`; `compute_type` is `General` or
    `MemoryOptimized` (data flows); `core_count` is the data flow cluster
    size; `time_to_live_min` keeps a data flow cluster warm between runs.
    `null` (the default) creates none, e.g. when integration runtimes are
    published from Git instead.
  EOT
  default     = null


  validation {
    condition     = var.managed_integration_runtime == null || contains(["General", "MemoryOptimized"], try(var.managed_integration_runtime.compute_type, ""))
    error_message = "managed_integration_runtime.compute_type must be \"General\" or \"MemoryOptimized\"."
  }

  validation {
    condition     = var.managed_integration_runtime == null || contains([8, 16, 32, 48, 80, 144, 272], try(var.managed_integration_runtime.core_count, 0))
    error_message = "managed_integration_runtime.core_count must be one of 8, 16, 32, 48, 80, 144 or 272."
  }
}

variable "managed_private_endpoints" {
  type = map(object({
    target_resource_id = string
    subresource_name   = optional(string)
    fqdns              = optional(list(string))
    name               = optional(string)
  }))
  description = <<-EOT
    Managed private endpoints from the factory's managed virtual network,
    keyed by an arbitrary static name (the default endpoint name), e.g.:

    ```hcl
    managed_private_endpoints = {
      data-lake-dfs = {
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
    condition     = alltrue([for k, mpe in var.managed_private_endpoints : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,125}[a-zA-Z0-9_]$", coalesce(mpe.name, k)))])
    error_message = "Managed private endpoint names must be 2-127 letters, digits, '_', '.' or '-', starting with a letter or digit and ending with a letter, digit or '_'."
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

    - `dataFactory` - the factory's APIs, used by self-hosted integration
      runtimes and tooling (`privatelink.datafactory.azure.net`).
    - `portal` - ADF Studio (`privatelink.adf.azure.com`).

    Per endpoint:

    - `subnet_id` - subnet to place the endpoint's network interface in.
    - `private_dns_zone_ids` - private DNS zones to register the
      endpoint in. Leave empty when DNS is managed elsewhere: set
      `private_endpoints_manage_dns_zone_group = false` if an Azure
      Policy registers the endpoints.
    - `private_ip_address` - static IP from the subnet. `null` lets Azure
      assign one.
    - `name` / `network_interface_name` - default to
      `pep-<factory name>-<sub-resource>` and `nic-pep-<factory name>-<sub-resource>`
      (sub-resource lowercased).
    - `resource_group_name` / `location` - default to the factory's.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : contains(["dataFactory", "portal"], k)])
    error_message = "private_endpoints keys must be Data Factory sub-resources: dataFactory or portal (case-sensitive)."
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

variable "github_configuration" {
  type = object({
    account_name       = string
    repository_name    = string
    branch_name        = string
    root_folder        = optional(string, "/")
    git_url            = optional(string)
    publishing_enabled = optional(bool, true)
  })
  description = <<-EOT
    Connect ADF Studio to a GitHub repository for source control.
    `branch_name` is the collaboration branch and `root_folder` the folder
    holding factory artifacts (e.g. `/datafactory`). `git_url` is only
    needed for GitHub Enterprise Server. A repository admin still has to
    approve the Data Factory app's access. `null` (the default) leaves Git
    integration off.
  EOT
  default     = null
}

variable "identity_ids" {
  type        = list(string)
  description = "User-assigned managed identities to attach in addition to the always-on system-assigned identity."
  default     = []
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
    Send the factory's logs (pipeline, activity and trigger runs, and more)
    and metrics to a Log Analytics workspace. `null` (the default) disables
    diagnostics.

    - `log_categories`: log categories to enable. `null` (the default)
      enables the `allLogs` category group; `[]` enables no logs.
    - `metric_categories`: metric categories to enable. `null` (the default)
      enables `AllMetrics`; `[]` enables no metrics.

    At least one log or metric category must end up enabled.
  EOT
  default     = null

  validation {
    condition = var.diagnostic_settings == null || (
      length(try(var.diagnostic_settings.log_categories, null) == null ? ["allLogs"] : var.diagnostic_settings.log_categories) +
      length(try(var.diagnostic_settings.metric_categories, null) == null ? ["AllMetrics"] : var.diagnostic_settings.metric_categories) > 0
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
    Management lock on the factory, protecting it from accidental deletion
    (`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to
    `lock-<factory name>`. `null` (the default) creates no lock.

    A `ReadOnly` lock also blocks publishing pipelines and other factory
    changes.

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
    Azure RBAC role assignments scoped to the factory, keyed by an arbitrary
    static name (e.g. `Data Factory Contributor` for developers).
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
