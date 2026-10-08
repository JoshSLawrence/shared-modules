# Approved exceptions:
# - AZU-0057 only recognizes classic Storage Analytics logging via an inline
#   queue_properties.logging block, which azurerm 5.x no longer has. Logging
#   is provided by Azure Monitor diagnostic settings instead (see
#   var.diagnostic_settings), which supersede classic logging.
# - AZU-0060 wants customer-managed keys whenever an account has containers.
#   Data is encrypted at rest with Microsoft-managed keys (plus infrastructure
#   encryption by default); customer-managed keys aren't supported by this
#   module yet.
#trivy:ignore:AZU-0057
#trivy:ignore:AZU-0060
resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = var.account_tier == "Premium" ? null : var.access_tier
  is_hns_enabled           = var.is_hns_enabled
  tags                     = var.tags

  public_network_access = var.public_network_access_enabled ? "Enabled" : "Disabled"

  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  shared_access_key_enabled         = var.shared_access_key_enabled
  # Makes the portal (and other clients that honor it) use Entra ID instead
  # of account keys, even while Shared Key auth is still allowed.
  default_to_oauth_authentication = true

  # Two states only: private (endpoint disabled; the rules are moot) or
  # public to every network. Deny stays the default for the private case so
  # the account never falls back to open if the endpoint is re-enabled
  # outside OpenTofu.
  network_rules {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled  = var.blob_properties.versioning_enabled
    change_feed_enabled = var.blob_properties.change_feed_enabled

    dynamic "delete_retention_policy" {
      for_each = var.blob_properties.delete_retention_days > 0 ? [1] : []

      content {
        days = var.blob_properties.delete_retention_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.blob_properties.container_delete_retention_days > 0 ? [1] : []

      content {
        days = var.blob_properties.container_delete_retention_days
      }
    }
  }
}

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = coalesce(each.value.name, each.key)
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
  metadata              = each.value.metadata
}

resource "azurerm_management_lock" "this" {
  count = var.lock == null ? 0 : 1

  name       = coalesce(var.lock.name, "lock-${var.name}")
  scope      = azurerm_storage_account.this.id
  lock_level = var.lock.kind
  notes      = var.lock.notes

  # A lock taken before the containers exist would block creating them
  depends_on = [azurerm_storage_container.this]
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                            = azurerm_storage_account.this.id
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
  diag_log_categories    = try(var.diagnostic_settings.log_categories, null) == null ? ["StorageRead", "StorageWrite", "StorageDelete"] : var.diagnostic_settings.log_categories
  diag_metric_categories = try(var.diagnostic_settings.metric_categories, null) == null ? ["Transaction"] : var.diagnostic_settings.metric_categories
}

resource "azurerm_monitor_diagnostic_setting" "account" {
  # The account itself only emits metrics, so there's nothing to set up
  # without any
  count = var.diagnostic_settings != null && length(local.diag_metric_categories) > 0 ? 1 : 0

  name                       = var.diagnostic_settings.name
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = var.diagnostic_settings.log_analytics_workspace_id

  dynamic "enabled_metric" {
    for_each = toset(local.diag_metric_categories)

    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.diagnostic_settings != null && length(local.diag_log_categories) + length(local.diag_metric_categories) > 0 ? 1 : 0

  name                       = var.diagnostic_settings.name
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.diagnostic_settings.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(local.diag_log_categories)

    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(local.diag_metric_categories)

    content {
      category = enabled_metric.value
    }
  }
}
