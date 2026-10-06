variable "name" {
  type        = string
  description = "Name of the Key Vault (e.g. `kv-myapp-prod`). Must be globally unique."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-24 characters of letters, digits and hyphens, start with a letter, end with a letter or digit, and not contain consecutive hyphens."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create the Key Vault (and its private endpoints, unless overridden) in."
}

variable "location" {
  type        = string
  description = "Azure region to create the Key Vault in (e.g. `eastus`)."
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to every resource this module creates."
  default     = {}
  nullable    = false
}

variable "tenant_id" {
  type        = string
  description = "Entra ID tenant used to authenticate requests to the vault. `null` uses the tenant of the identity running OpenTofu."
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", coalesce(var.tenant_id, "unset")))
    error_message = "tenant_id must be a GUID (or null to use the current tenant)."
  }
}

variable "sku_name" {
  type        = string
  description = "Key Vault SKU: `standard` or `premium` (HSM-backed keys)."
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be \"standard\" or \"premium\"."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Days (7-90) that deleted vaults and objects are retained before they can be purged. Can't be changed after creation."
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days
    error_message = "soft_delete_retention_days must be a whole number between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  type        = bool
  description = <<-EOT
    Prevent deleted vaults and objects from being purged until the retention
    period ends. Required for customer-managed keys (e.g. Synapse or Storage
    encryption). Once enabled it can't be disabled.
  EOT
  default     = true
}

variable "public_network_access_enabled" {
  type        = bool
  description = <<-EOT
    Network access to the vault:

    - `false` (the default) - private: the public endpoint is disabled and
      the vault is reachable only through `private_endpoints`.
    - `true` - public: the endpoint accepts traffic from every network
      (still subject to Entra ID authorization).
  EOT
  default     = false
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
    Private endpoints to create, keyed by target sub-resource. Key Vault has a
    single sub-resource, `vault`.

    - `subnet_id` - subnet to place the endpoint's network interface in.
    - `private_dns_zone_ids` - private DNS zones to register the
      endpoint in (normally the `privatelink.vaultcore.azure.net` zone).
      Leave empty when DNS is managed elsewhere: set
      `private_endpoints_manage_dns_zone_group = false` if an Azure
      Policy registers the endpoints.
    - `private_ip_address` - static IP from the subnet (e.g.
      `cidrhost(<subnet prefix>, 5)`). `null` lets Azure assign one.
    - `name` / `network_interface_name` - default to `pep-<vault name>` and
      `nic-pep-<vault name>`.
    - `resource_group_name` / `location` - default to the vault's.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : k == "vault"])
    error_message = "private_endpoints keys must be the sub-resource \"vault\"."
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
  })
  description = "Send the vault's logs (including audit events) and metrics to a Log Analytics workspace. `null` (the default) disables diagnostics."
  default     = null
}

variable "lock" {
  type = object({
    kind  = string
    name  = optional(string)
    notes = optional(string)
  })
  description = <<-EOT
    Management lock on the vault, protecting it from accidental deletion
    (`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to
    `lock-<vault name>`. `null` (the default) creates no lock.
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
    Azure RBAC role assignments scoped to the vault, keyed by an arbitrary
    static name. The vault uses RBAC authorization (not access policies), so
    this is how identities get data access, e.g.:

    ```hcl
    role_assignments = {
      deployer_secrets_officer = {
        role_definition_id_or_name = "Key Vault Secrets Officer"
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
