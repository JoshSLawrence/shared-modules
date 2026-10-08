data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
  sku_name            = var.sku_name
  tags                = var.tags

  # RBAC only: access policies can't be scoped or audited like role
  # assignments, and mixing the two models is a common source of drift.
  rbac_authorization_enabled = true

  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.purge_protection_enabled
  public_network_access_enabled = var.public_network_access_enabled

  # Two states only: private (endpoint disabled; the ACL is moot) or public
  # to every network. Deny stays the default for the private case so the
  # vault never falls back to open if the endpoint is re-enabled outside
  # OpenTofu.
  network_acls {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_management_lock" "this" {
  count = var.lock == null ? 0 : 1

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_key_vault.this.id
  lock_level = var.lock.kind
  notes      = var.lock.notes
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                            = azurerm_key_vault.this.id
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
  target_resource_id         = azurerm_key_vault.this.id
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
