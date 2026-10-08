mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
      primary_dfs_endpoint = "https://sttest001.dfs.core.windows.net/"
    }
  }

  # Containers created with storage_account_id get Resource Manager IDs,
  # which role assignments need as their scope
  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001/blobServices/default/containers/mock"
    }
  }
}

variables {
  name                = "sttest001"
  resource_group_name = "rg-test"
  location            = "eastus"
}

run "defaults_are_private_and_entra_only" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.public_network_access == "Disabled"
    error_message = "Public network access should be disabled by default."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false && azurerm_storage_account.this.default_to_oauth_authentication == true
    error_message = "Shared Key auth should be disabled, and Entra ID the default, by default."
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2" && azurerm_storage_account.this.https_traffic_only_enabled == true && azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "TLS 1.2, HTTPS only and no public blob access should always be enforced."
  }

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled == true && azurerm_storage_account.this.cross_tenant_replication_enabled == false
    error_message = "Infrastructure encryption should be on, and cross-tenant replication off, by default."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny" && azurerm_storage_account.this.network_rules[0].bypass == toset(["AzureServices"])
    error_message = "The firewall should deny by default and let trusted Azure services bypass it."
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == false && azurerm_storage_account.this.account_replication_type == "RAGRS" && azurerm_storage_account.this.access_tier == "Hot"
    error_message = "Unexpected account defaults (HNS off, RAGRS, Hot)."
  }

  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].delete_retention_policy) == 1 && azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Blob soft delete should default to 7 days."
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 0 && length(azurerm_private_endpoint.this) == 0 && length(azurerm_management_lock.this) == 0 && length(azurerm_monitor_diagnostic_setting.account) == 0 && length(azurerm_monitor_diagnostic_setting.blob) == 0 && length(azurerm_role_assignment.this) == 0
    error_message = "No optional resources should be created by default."
  }
}

run "public_access_is_open_to_all_networks" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access == "Enabled"
    error_message = "Public network access should be enabled when requested."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Allow"
    error_message = "Public accounts should accept traffic from every network."
  }
}

run "data_lake_containers" {
  command = plan

  variables {
    is_hns_enabled = true
    containers = {
      bronze = {}
      raw = {
        name     = "raw-landing"
        metadata = { owner = "data-eng" }
      }
    }
  }

  assert {
    condition     = azurerm_storage_container.this["bronze"].name == "bronze" && azurerm_storage_container.this["raw"].name == "raw-landing"
    error_message = "Container names should default to their key, and honor an explicit name."
  }

  assert {
    condition     = alltrue([for c in azurerm_storage_container.this : c.container_access_type == "private"])
    error_message = "Containers should always be private."
  }

  assert {
    condition     = output.containers["bronze"].data_lake_filesystem_id == "https://sttest001.dfs.core.windows.net/bronze"
    error_message = "data_lake_filesystem_id should be the dfs endpoint plus the container name, got ${output.containers["bronze"].data_lake_filesystem_id}."
  }
}

run "blob_containers_have_no_filesystem_id" {
  command = plan

  variables {
    containers = {
      data = {}
    }
  }

  assert {
    condition     = output.containers["data"].data_lake_filesystem_id == null
    error_message = "Containers on a non-HNS account shouldn't expose a Data Lake file system ID."
  }
}

run "soft_delete_and_versioning_can_be_disabled" {
  command = plan

  variables {
    blob_properties = {
      versioning_enabled              = false
      delete_retention_days           = 0
      container_delete_retention_days = 0
    }
  }

  assert {
    condition     = length(azurerm_storage_account.this.blob_properties[0].delete_retention_policy) == 0 && length(azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy) == 0
    error_message = "Zero retention days should disable blob and container soft delete."
  }
}

run "premium_accounts_have_no_access_tier" {
  command = plan

  variables {
    account_kind             = "BlockBlobStorage"
    account_tier             = "Premium"
    account_replication_type = "ZRS"
  }

  assert {
    condition     = azurerm_storage_account.this.account_tier == "Premium"
    error_message = "account_tier should be passed through."
  }
}

run "private_endpoints_per_subresource" {
  command = plan

  variables {
    private_endpoints = {
      blob = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
        private_ip_address   = "10.0.0.6"
      }
      dfs_secondary = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["blob"].name == "pep-sttest001-blob" && azurerm_private_endpoint.this["blob"].custom_network_interface_name == "nic-pep-sttest001-blob"
    error_message = "Private endpoint and NIC names should follow the pep-/nic-pep- CAF convention."
  }

  assert {
    condition     = azurerm_private_endpoint.this["dfs_secondary"].name == "pep-sttest001-dfs-secondary"
    error_message = "Underscores in the sub-resource should become hyphens in the endpoint name."
  }

  assert {
    condition     = azurerm_private_endpoint.this["blob"].ip_configuration[0].private_ip_address == "10.0.0.6" && azurerm_private_endpoint.this["blob"].ip_configuration[0].member_name == "blob"
    error_message = "A static IP should create an ip_configuration for the sub-resource's member."
  }

  assert {
    condition     = azurerm_private_endpoint.this["dfs_secondary"].private_service_connection[0].subresource_names == tolist(["dfs_secondary"]) && length(azurerm_private_endpoint.this["dfs_secondary"].ip_configuration) == 0
    error_message = "Each endpoint should target its key's sub-resource, with a dynamic IP unless one is given."
  }
}

run "private_endpoints_for_every_service" {
  command = plan

  variables {
    private_endpoints = {
      blob = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
      }
      dfs = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"]
      }
      file = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"]
      }
      queue = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"]
      }
      table = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"]
      }
      web = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.web.core.windows.net"]
      }
    }
  }

  assert {
    condition     = toset(keys(azurerm_private_endpoint.this)) == toset(["blob", "dfs", "file", "queue", "table", "web"])
    error_message = "Every storage service should be able to get a private endpoint."
  }

  assert {
    condition     = alltrue([for k, pe in azurerm_private_endpoint.this : pe.private_service_connection[0].subresource_names == tolist([k]) && pe.name == "pep-sttest001-${k}"])
    error_message = "Each endpoint should target its own service and be named after it."
  }
}

run "lock_diagnostics_and_role_assignments" {
  command = plan

  variables {
    lock = {
      kind = "CanNotDelete"
      name = "lock-custom"
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Storage Blob Data Reader"
        principal_id               = "00000000-0000-0000-0000-000000000003"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this[0].name == "lock-custom" && azurerm_management_lock.this[0].lock_level == "CanNotDelete"
    error_message = "The lock should honor the requested name and level."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.blob[0].target_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001/blobServices/default"
    error_message = "Blob diagnostics should target the blob service."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.account) == 1
    error_message = "Account-level metrics should be sent too."
  }

  assert {
    condition     = azurerm_role_assignment.this["reader"].role_definition_name == "Storage Blob Data Reader" && azurerm_role_assignment.this["reader"].principal_type == "Group"
    error_message = "Role assignments should be passed through."
  }
}

run "private_dns_records_output" {
  command = plan

  variables {
    private_endpoints = {
      blob = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
      }
      dfs = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"]
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.blob.core.windows.net"
        name                = "privatelink.blob.core.windows.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        record_sets = [{
          name         = "sttest001"
          fqdn         = "sttest001.privatelink.blob.core.windows.net"
          type         = "A"
          ip_addresses = ["10.0.0.6"]
          ttl          = 10
        }]
      }]
    }
  }

  assert {
    condition     = length(output.private_dns_records) == 2 && toset([for r in output.private_dns_records : r.subresource]) == toset(["blob", "dfs"])
    error_message = "private_dns_records should list one record per endpoint: ${jsonencode(output.private_dns_records)}"
  }

  assert {
    condition = alltrue([
      for r in output.private_dns_records :
      r.resource == "sttest001" && r.zone_name == "privatelink.blob.core.windows.net" && r.name == "sttest001" && r.type == "A" && r.ip_addresses == tolist(["10.0.0.6"])
    ])
    error_message = "Each record should carry its zone, host name, type and IP: ${jsonencode(output.private_dns_records)}"
  }
}

run "private_dns_records_empty_without_zones" {
  command = plan

  variables {
    private_endpoints = {
      blob = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      }
    }
  }

  assert {
    condition     = output.private_dns_records == []
    error_message = "Endpoints without DNS zones should produce no records."
  }
}

run "policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      dfs = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0.9"
      }
    }
  }

  # What Azure reports once the policy has attached its zone group
  override_resource {
    target = azurerm_private_endpoint.this_unmanaged_dns_zone_group
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-policy"
        name                = "privatelink.dfs.core.windows.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
        record_sets = [{
          name         = "sttest001"
          fqdn         = "sttest001.privatelink.dfs.core.windows.net"
          type         = "A"
          ip_addresses = ["10.0.0.9"]
          ttl          = 10
        }]
      }]
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 0 && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group) == 1
    error_message = "With policy-managed DNS, endpoints should come from the resource that ignores zone groups."
  }

  assert {
    condition     = azurerm_private_endpoint.this_unmanaged_dns_zone_group["dfs"].name == "pep-sttest001-dfs" && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group["dfs"].private_dns_zone_group) == 0
    error_message = "The endpoint should keep its name and get no zone group from this module."
  }

  assert {
    condition     = output.private_endpoints["dfs"] != null && length(output.private_dns_records) == 1 && output.private_dns_records[0].zone_name == "privatelink.dfs.core.windows.net"
    error_message = "Outputs should include policy-managed endpoints and the records the policy registered: ${jsonencode(output.private_dns_records)}"
  }
}

run "diagnostics_default_categories" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.blob[0].enabled_log : l.category]) == toset(["StorageRead", "StorageWrite", "StorageDelete"])
    error_message = "Blob diagnostics should default to read, write and delete logs."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.blob[0].enabled_metric : m.category]) == toset(["Transaction"]) && toset([for m in azurerm_monitor_diagnostic_setting.account[0].enabled_metric : m.category]) == toset(["Transaction"])
    error_message = "Account and blob diagnostics should default to Transaction metrics."
  }
}

run "diagnostics_custom_categories" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = ["StorageRead"]
      metric_categories          = ["Capacity", "Transaction"]
    }
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.blob[0].enabled_log : l.category]) == toset(["StorageRead"])
    error_message = "Only the requested log categories should be enabled."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.blob[0].enabled_metric : m.category]) == toset(["Capacity", "Transaction"]) && toset([for m in azurerm_monitor_diagnostic_setting.account[0].enabled_metric : m.category]) == toset(["Capacity", "Transaction"])
    error_message = "The requested metric categories should be enabled on both settings."
  }
}

run "diagnostics_metrics_off" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      metric_categories          = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.account) == 0
    error_message = "The account-level setting only emits metrics, so it should be omitted when metrics are off."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.blob) == 1 && length(azurerm_monitor_diagnostic_setting.blob[0].enabled_metric) == 0 && length(azurerm_monitor_diagnostic_setting.blob[0].enabled_log) == 3
    error_message = "The blob setting should keep its logs and have no metrics."
  }
}

run "diagnostics_metrics_only" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.account) == 1 && length(azurerm_monitor_diagnostic_setting.blob) == 1 && length(azurerm_monitor_diagnostic_setting.blob[0].enabled_log) == 0
    error_message = "Without logs, both settings should carry only metrics."
  }
}

run "container_role_assignments" {
  command = plan

  variables {
    is_hns_enabled = true
    containers = {
      reports = {
        role_assignments = {
          analysts = {
            role_definition_id_or_name = "Storage Blob Data Reader"
            principal_id               = "00000000-0000-0000-0000-0000000000aa"
            principal_type             = "Group"
          }
        }
      }
      raw = {}
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.containers) == 1 && azurerm_role_assignment.containers["reports/analysts"].role_definition_name == "Storage Blob Data Reader" && azurerm_role_assignment.containers["reports/analysts"].principal_type == "Group"
    error_message = "A container role assignment should be created per container grant, keyed \"<container>/<grant>\"."
  }

  assert {
    condition     = azurerm_role_assignment.containers["reports/analysts"].scope == azurerm_storage_container.this["reports"].id && endswith(azurerm_role_assignment.containers["reports/analysts"].scope, "/blobServices/default/containers/mock")
    error_message = "A container role assignment should be scoped to the container's ID, not the account's."
  }
}
