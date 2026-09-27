variable "github_owner" {
  description = "GitHub user that owns the repository."
  type        = string
}

variable "repository_name" {
  description = "Name of the repository to create and manage."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.repository_name))
    error_message = "repository_name must be 1-100 characters of letters, digits, '.', '-' or '_'."
  }
}

variable "ruleset_enforcement" {
  description = <<-EOT
    Enforcement for the repository rulesets: "active" or "disabled". Only set
    "disabled" temporarily -- e.g. to push the initial history to a brand-new
    repository before the main ruleset starts requiring pull requests (see
    README.md).
  EOT
  type        = string

  validation {
    condition     = contains(["active", "disabled"], var.ruleset_enforcement)
    error_message = "ruleset_enforcement must be \"active\" or \"disabled\"."
  }
}

# The Azure identity for integration tests is managed outside this root
# module. These are identifiers, not secrets. While azure_client_id is null,
# the AZURE_* repository variables aren't created and PR validation skips
# integration tests.
variable "azure_client_id" {
  description = "Client ID of the Entra ID app registration / managed identity integration tests authenticate as. null disables integration tests."
  type        = string

  validation {
    condition     = var.azure_client_id == null || can(regex("^[0-9a-fA-F-]{36}$", var.azure_client_id))
    error_message = "azure_client_id must be a GUID."
  }
}

variable "azure_tenant_id" {
  description = "Entra ID tenant ID for integration tests. Required when azure_client_id is set."
  type        = string

  validation {
    condition     = var.azure_client_id == null || can(regex("^[0-9a-fA-F-]{36}$", coalesce(var.azure_tenant_id, "unset")))
    error_message = "azure_tenant_id must be a GUID when azure_client_id is set."
  }
}

variable "azure_subscription_id" {
  description = "Azure subscription ID integration tests deploy into. Required when azure_client_id is set."
  type        = string

  validation {
    condition     = var.azure_client_id == null || can(regex("^[0-9a-fA-F-]{36}$", coalesce(var.azure_subscription_id, "unset")))
    error_message = "azure_subscription_id must be a GUID when azure_client_id is set."
  }
}

# The identity the iac workflow (plan and apply) uses for this root module's
# state is also managed outside this root module. It only needs access to
# the state container. While iac_azure_client_id is null, the IAC_*
# repository variables aren't created and the iac workflow is skipped.
variable "iac_azure_client_id" {
  description = "Client ID of the Entra ID app registration / managed identity the iac workflow uses to access this root module's state. null disables the iac workflow."
  type        = string

  validation {
    condition     = var.iac_azure_client_id == null || can(regex("^[0-9a-fA-F-]{36}$", var.iac_azure_client_id))
    error_message = "iac_azure_client_id must be a GUID."
  }
}

variable "iac_azure_tenant_id" {
  description = "Entra ID tenant ID of the iac workflow identity. Required when iac_azure_client_id is set."
  type        = string

  validation {
    condition     = var.iac_azure_client_id == null || can(regex("^[0-9a-fA-F-]{36}$", coalesce(var.iac_azure_tenant_id, "unset")))
    error_message = "iac_azure_tenant_id must be a GUID when iac_azure_client_id is set."
  }
}

variable "fork_pr_approval_policy" {
  description = "Which fork PR authors need a maintainer's approval before their workflows run: all_external_contributors, first_time_contributors, or first_time_contributors_new_to_github."
  type        = string
  default     = "all_external_contributors"

  validation {
    condition     = contains(["all_external_contributors", "first_time_contributors", "first_time_contributors_new_to_github"], var.fork_pr_approval_policy)
    error_message = "fork_pr_approval_policy must be all_external_contributors, first_time_contributors, or first_time_contributors_new_to_github."
  }
}
