data "azurerm_client_config" "current" {}

resource "azurerm_synapse_workspace" "this" {
  name                                 = var.name
  resource_group_name                  = var.resource_group_name
  location                             = var.location
  storage_data_lake_gen2_filesystem_id = local.data_lake_filesystem_id
  managed_resource_group_name          = var.managed_resource_group_name
  tags                                 = var.tags

  public_network_access_enabled = var.public_network_access_enabled
  # Always on: it can only be chosen at creation, and the workspace's Spark
  # pools, integration runtimes and managed private endpoints all need it
  managed_virtual_network_enabled      = true
  data_exfiltration_protection_enabled = var.data_exfiltration_protection_enabled
  linking_allowed_for_aad_tenant_ids   = var.linking_allowed_for_aad_tenant_ids

  azuread_authentication_only      = var.azuread_authentication_only
  sql_administrator_login          = var.sql_administrator_login
  sql_administrator_login_password = local.sql_administrator_password

  identity {
    type         = length(var.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  dynamic "github_repo" {
    for_each = var.github_repo == null ? [] : [var.github_repo]

    content {
      account_name    = github_repo.value.account_name
      repository_name = github_repo.value.repository_name
      branch_name     = github_repo.value.branch_name
      root_folder     = github_repo.value.root_folder
      git_url         = github_repo.value.git_url
      last_commit_id  = github_repo.value.last_commit_id
    }
  }
}

resource "azurerm_management_lock" "this" {
  count = var.lock == null ? 0 : 1

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_synapse_workspace.this.id
  lock_level = var.lock.kind
  notes      = var.lock.notes

  # A lock taken before these exist would block creating them
  depends_on = [
    azurerm_synapse_firewall_rule.allow_all,
    azurerm_synapse_firewall_rule.azure_services,
    azurerm_synapse_spark_pool.this,
    azurerm_synapse_workspace_aad_admin.this,
  ]
}

# var.access, expanded into the explicit assignment maps' shapes. Keys: the
# access key, and <key>_credential_user for Synapse Credential User.
locals {
  access_synapse_role_assignments = merge(
    {
      for k, a in var.access : k => {
        role_name      = a.synapse_role
        principal_id   = a.principal_id
        principal_type = a.principal_type
      } if a.synapse_role != null
    },
    {
      for k, a in var.access : "${k}_credential_user" => {
        role_name      = "Synapse Credential User"
        principal_id   = a.principal_id
        principal_type = a.principal_type
      } if a.credential_user
    },
  )

  access_role_assignments = {
    for k, a in var.access : k => {
      role_definition_id_or_name       = a.workspace_role
      principal_id                     = a.principal_id
      principal_type                   = a.principal_type
      description                      = null
      condition                        = null
      condition_version                = null
      skip_service_principal_aad_check = false
    } if a.workspace_role != null
  }

  role_assignments         = merge(var.role_assignments, local.access_role_assignments)
  synapse_role_assignments = merge(var.synapse_role_assignments, local.access_synapse_role_assignments)
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                            = azurerm_synapse_workspace.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id               = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  role_definition_name             = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

resource "azurerm_synapse_role_assignment" "this" {
  for_each = local.synapse_role_assignments

  synapse_workspace_id = azurerm_synapse_workspace.this.id
  role_name            = each.value.role_name
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type

  # Synapse RBAC is served by the workspace's dev endpoint, which is only
  # reachable once a firewall rule or private endpoints exist
  depends_on = [
    azurerm_synapse_firewall_rule.allow_all,
    azurerm_synapse_firewall_rule.azure_services,
    azurerm_private_endpoint.this,
    azurerm_private_endpoint.this_unmanaged_dns_zone_group,
  ]
}

locals {
  # null means "module default"; an explicit empty list means "none"
  diag_log_categories    = try(var.diagnostic_settings.log_categories, null)
  diag_metric_categories = try(var.diagnostic_settings.metric_categories, null) == null ? [] : var.diagnostic_settings.metric_categories
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostic_settings == null ? 0 : 1

  name                       = var.diagnostic_settings.name
  target_resource_id         = azurerm_synapse_workspace.this.id
  log_analytics_workspace_id = var.diagnostic_settings.log_analytics_workspace_id

  # Without an explicit list, allLogs covers every log category (a superset
  # of the audit group) and any added later
  dynamic "enabled_log" {
    for_each = local.diag_log_categories == null ? [{ category = null, category_group = "allLogs" }] : [for c in toset(local.diag_log_categories) : { category = c, category_group = null }]

    content {
      category       = enabled_log.value.category
      category_group = enabled_log.value.category_group
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(local.diag_metric_categories)

    content {
      category = enabled_metric.value
    }
  }
}
