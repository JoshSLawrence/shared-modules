resource "azurerm_data_factory" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  location               = var.location
  public_network_enabled = var.public_network_access_enabled
  # Always on, so pipelines can reach private data stores through managed
  # private endpoints; it can't be turned off once enabled
  managed_virtual_network_enabled = true
  tags                            = var.tags

  identity {
    type         = length(var.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : null
  }

  dynamic "github_configuration" {
    for_each = var.github_configuration == null ? [] : [var.github_configuration]

    content {
      account_name       = github_configuration.value.account_name
      repository_name    = github_configuration.value.repository_name
      branch_name        = github_configuration.value.branch_name
      root_folder        = github_configuration.value.root_folder
      git_url            = github_configuration.value.git_url
      publishing_enabled = github_configuration.value.publishing_enabled
    }
  }
}

resource "azurerm_data_factory_integration_runtime_azure" "managed" {
  count = var.managed_integration_runtime == null ? 0 : 1

  name                    = var.managed_integration_runtime.name
  data_factory_id         = azurerm_data_factory.this.id
  location                = var.managed_integration_runtime.location
  description             = var.managed_integration_runtime.description
  compute_type            = var.managed_integration_runtime.compute_type
  core_count              = var.managed_integration_runtime.core_count
  time_to_live_min        = var.managed_integration_runtime.time_to_live_min
  cleanup_enabled         = var.managed_integration_runtime.cleanup_enabled
  virtual_network_enabled = true
}

resource "azurerm_management_lock" "this" {
  count = var.lock == null ? 0 : 1

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_data_factory.this.id
  lock_level = var.lock.kind
  notes      = var.lock.notes

  # A lock taken before these exist would block creating them
  depends_on = [
    azurerm_data_factory_integration_runtime_azure.managed,
    azurerm_data_factory_managed_private_endpoint.this,
  ]
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                            = azurerm_data_factory.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id               = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  role_definition_name             = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

locals {
  # null means "module default"; an explicit empty list means "none"
  diag_log_categories    = try(var.diagnostic_settings.log_categories, null)
  diag_metric_categories = try(var.diagnostic_settings.metric_categories, null) == null ? ["AllMetrics"] : var.diagnostic_settings.metric_categories
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostic_settings == null ? 0 : 1

  name                       = var.diagnostic_settings.name
  target_resource_id         = azurerm_data_factory.this.id
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
