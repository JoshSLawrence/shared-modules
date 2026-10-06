# The workspace's default storage: created with the storage-account module, or
# an existing file system passed in by the caller. The module is pinned to a
# release like any other dependency; upgrading it is a change (and a version
# bump) to this module.
module "storage_account" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/v0.0.1"
  count  = var.storage_account == null ? 0 : 1

  name                                    = var.storage_account.name
  resource_group_name                     = var.resource_group_name
  location                                = var.location
  tags                                    = var.tags
  is_hns_enabled                          = true
  account_replication_type                = var.storage_account.account_replication_type
  infrastructure_encryption_enabled       = var.storage_account.infrastructure_encryption_enabled
  public_network_access_enabled           = local.storage_public_network_access_enabled
  private_endpoints_manage_dns_zone_group = local.storage_private_endpoints_manage_dns_zone_group
  private_endpoints                       = var.storage_account.private_endpoints
  diagnostic_settings                     = var.diagnostic_settings
  lock                                    = var.lock

  # Synapse doesn't support blob versioning or soft delete on its default
  # storage
  blob_properties = {
    versioning_enabled              = false
    change_feed_enabled             = false
    delete_retention_days           = 0
    container_delete_retention_days = 0
  }

  containers = {
    synapse = {
      name = var.storage_account.filesystem_name
    }
  }
}

locals {
  storage_public_network_access_enabled = try(coalesce(var.storage_account.public_network_access_enabled, var.public_network_access_enabled), null)

  storage_private_endpoints_manage_dns_zone_group = try(coalesce(var.storage_account.private_endpoints_manage_dns_zone_group, var.private_endpoints_manage_dns_zone_group), null)

  storage_account_id = var.storage_account == null ? var.existing_storage.storage_account_id : module.storage_account[0].id

  data_lake_filesystem_id = (
    var.storage_account == null
    ? var.existing_storage.data_lake_filesystem_id
    : module.storage_account[0].containers["synapse"].data_lake_filesystem_id
  )

  assign_storage_role = var.storage_account != null || try(var.existing_storage.assign_blob_data_contributor, false)
}

# Synapse (Spark, serverless SQL, pipelines) reads and writes its default
# storage as the workspace's managed identity
resource "azurerm_role_assignment" "storage_blob_data_contributor" {
  count = local.assign_storage_role ? 1 : 0

  scope                = local.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
