data "azurerm_client_config" "current" {}

# Approved exception: AZU-0027 wants an extended auditing policy on every
# server. Auditing is opt-in (var.auditing_enabled) because it needs a Log
# Analytics workspace (var.diagnostic_settings), which the module can't
# assume the caller has.
#trivy:ignore:AZU-0027
resource "azurerm_mssql_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "12.0"
  tags                = var.tags

  minimum_tls_version                  = "1.2"
  public_network_access_enabled        = var.public_network_access_enabled
  outbound_network_restriction_enabled = var.outbound_network_restriction_enabled

  # Entra ID only: no SQL logins. The administrator login Azure generates at
  # creation is unusable while Entra-only authentication is on, so no SQL
  # password ever needs to exist (or be stored in state).
  azuread_administrator {
    login_username              = var.entra_admin.login
    object_id                   = var.entra_admin.object_id
    tenant_id                   = coalesce(var.entra_admin.tenant_id, data.azurerm_client_config.current.tenant_id)
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "this" {
  for_each = var.databases

  name                 = coalesce(each.value.name, each.key)
  server_id            = azurerm_mssql_server.this.id
  sku_name             = each.value.sku_name
  max_size_gb          = each.value.max_size_gb
  storage_account_type = each.value.storage_account_type
  collation            = each.value.collation
  zone_redundant       = each.value.zone_redundant
  tags                 = var.tags

  auto_pause_delay_in_minutes = each.value.auto_pause_delay_in_minutes
  min_capacity                = each.value.min_capacity
}

resource "azurerm_management_lock" "this" {
  count = var.lock == null ? 0 : 1

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_mssql_server.this.id
  lock_level = var.lock.kind
  notes      = var.lock.notes

  # A lock taken before these exist would block creating them
  depends_on = [
    azurerm_mssql_database.this,
    azurerm_mssql_server_extended_auditing_policy.this,
    azurerm_monitor_diagnostic_setting.audit,
    azurerm_monitor_diagnostic_setting.database,
  ]
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                            = azurerm_mssql_server.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id               = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  role_definition_name             = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

# Server-level auditing to Log Analytics (opt-in). Azure Monitor reads audit events
# from the master database's diagnostic setting, which has to exist before
# auditing is pointed at it.
resource "azurerm_monitor_diagnostic_setting" "audit" {
  count = var.auditing_enabled ? 1 : 0

  name                       = var.diagnostic_settings.name
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.diagnostic_settings.log_analytics_workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
}

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  count = var.auditing_enabled ? 1 : 0

  server_id              = azurerm_mssql_server.this.id
  log_monitoring_enabled = true

  depends_on = [azurerm_monitor_diagnostic_setting.audit]
}

locals {
  # null means "module default"; an explicit empty list means "none"
  diag_log_categories    = try(var.diagnostic_settings.log_categories, null)
  diag_metric_categories = try(var.diagnostic_settings.metric_categories, null) == null ? ["Basic", "InstanceAndAppAdvanced", "WorkloadManagement"] : var.diagnostic_settings.metric_categories
}

# Database logs and metrics. Server auditing is covered above; these are the
# per-database categories (query statistics, errors, deadlocks, ...).
resource "azurerm_monitor_diagnostic_setting" "database" {
  for_each = var.diagnostic_settings == null ? {} : var.databases

  name                       = var.diagnostic_settings.name
  target_resource_id         = azurerm_mssql_database.this[each.key].id
  log_analytics_workspace_id = var.diagnostic_settings.log_analytics_workspace_id

  # Without an explicit list, allLogs covers every log category and any added
  # later
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
