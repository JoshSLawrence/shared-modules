mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_resource "azurerm_synapse_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Synapse/workspaces/synw-test"
      identity = {
        principal_id = "00000000-0000-0000-0000-000000000005"
        tenant_id    = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stsynwtest"
      primary_dfs_endpoint = "https://stsynwtest.dfs.core.windows.net/"
    }
  }
}

mock_provider "random" {}

variables {
  name                = "synw-test"
  resource_group_name = "rg-test"
  location            = "eastus"
  storage_account = {
    name = "stsynwtest"
  }
}

run "defaults_are_private_with_new_storage" {
  command = plan

  assert {
    condition     = azurerm_synapse_workspace.this.public_network_access_enabled == false
    error_message = "Public network access should be disabled by default."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.managed_virtual_network_enabled == true && azurerm_synapse_workspace.this.data_exfiltration_protection_enabled == false
    error_message = "The managed virtual network should be on, and exfiltration protection off, by default."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.azuread_authentication_only == true && azurerm_synapse_workspace.this.sql_administrator_login == "sqladminuser"
    error_message = "Only Entra ID auth should be allowed by default, with the default SQL login still set."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.identity[0].type == "SystemAssigned"
    error_message = "The workspace should have a system-assigned identity."
  }

  assert {
    condition     = output.data_lake_filesystem_id == "https://stsynwtest.dfs.core.windows.net/synapse"
    error_message = "The workspace should use the synapse file system of the storage account it creates, got ${output.data_lake_filesystem_id}."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.storage_data_lake_gen2_filesystem_id == "https://stsynwtest.dfs.core.windows.net/synapse"
    error_message = "The workspace's default storage should be the created file system."
  }

  assert {
    condition     = output.storage_account_name == "stsynwtest" && output.storage_account_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stsynwtest"
    error_message = "Storage outputs should describe the created account."
  }

  assert {
    condition     = azurerm_role_assignment.storage_blob_data_contributor[0].role_definition_name == "Storage Blob Data Contributor" && azurerm_role_assignment.storage_blob_data_contributor[0].principal_id == "00000000-0000-0000-0000-000000000005"
    error_message = "The workspace identity should get Storage Blob Data Contributor on its default storage."
  }

  assert {
    condition     = azurerm_role_assignment.storage_blob_data_contributor[0].scope == output.storage_account_id
    error_message = "The storage role assignment should be scoped to the default storage account."
  }

  assert {
    condition = (
      length(azurerm_synapse_firewall_rule.allow_all) == 0 && length(random_password.sql_administrator) == 1 &&
      length(azurerm_private_endpoint.this) == 0 && length(azurerm_synapse_managed_private_endpoint.this) == 0 &&
      length(azurerm_synapse_managed_private_endpoint.storage) == 0 && length(azurerm_synapse_spark_pool.this) == 0 &&
      length(azurerm_key_vault_secret.sql_administrator_password) == 0 && length(azurerm_synapse_workspace_aad_admin.this) == 0 &&
      length(azurerm_management_lock.this) == 0 && length(azurerm_monitor_diagnostic_setting.this) == 0 &&
      length(azurerm_role_assignment.this) == 0 && length(azurerm_synapse_role_assignment.this) == 0
    )
    error_message = "No optional resources should be created by default."
  }

  assert {
    condition     = length(azurerm_synapse_workspace.this.github_repo) == 0
    error_message = "Git integration should be off by default."
  }
}

run "custom_filesystem_name" {
  command = plan

  variables {
    storage_account = {
      name            = "stsynwtest"
      filesystem_name = "workspace"
    }
  }

  assert {
    condition     = output.data_lake_filesystem_id == "https://stsynwtest.dfs.core.windows.net/workspace"
    error_message = "filesystem_name should name the workspace's file system."
  }
}

run "existing_storage" {
  command = plan

  variables {
    storage_account = null
    existing_storage = {
      data_lake_filesystem_id = "https://stexisting.dfs.core.windows.net/synapse"
      storage_account_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
    }
    storage_managed_private_endpoints = ["dfs", "blob"]
  }

  assert {
    condition     = azurerm_synapse_workspace.this.storage_data_lake_gen2_filesystem_id == "https://stexisting.dfs.core.windows.net/synapse"
    error_message = "The workspace should use the existing file system."
  }

  assert {
    condition     = output.storage_account_name == null && output.storage_private_endpoints == {}
    error_message = "No storage account should be created for existing storage."
  }

  assert {
    condition     = azurerm_role_assignment.storage_blob_data_contributor[0].scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
    error_message = "The storage role assignment should be scoped to the existing account."
  }

  assert {
    condition     = azurerm_synapse_managed_private_endpoint.storage["dfs"].name == "stexisting-dfs" && azurerm_synapse_managed_private_endpoint.storage["blob"].subresource_name == "blob"
    error_message = "Storage managed private endpoints should target the default storage account's sub-resources."
  }

  assert {
    condition     = azurerm_synapse_managed_private_endpoint.storage["dfs"].target_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
    error_message = "Storage managed private endpoints should target the existing account."
  }
}

run "existing_storage_without_role_assignment" {
  command = plan

  variables {
    storage_account = null
    existing_storage = {
      data_lake_filesystem_id      = "https://stexisting.dfs.core.windows.net/synapse"
      storage_account_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
      assign_blob_data_contributor = false
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.storage_blob_data_contributor) == 0
    error_message = "assign_blob_data_contributor = false should skip the storage role assignment."
  }
}

run "public_access_is_open_to_all_networks" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_synapse_workspace.this.public_network_access_enabled == true
    error_message = "Public network access should be enabled when requested."
  }

  assert {
    condition     = azurerm_synapse_firewall_rule.allow_all[0].name == "AllowAll" && azurerm_synapse_firewall_rule.allow_all[0].start_ip_address == "0.0.0.0" && azurerm_synapse_firewall_rule.allow_all[0].end_ip_address == "255.255.255.255"
    error_message = "A public workspace should get an AllowAll rule spanning every IPv4 address."
  }

  assert {
    condition     = local.storage_public_network_access_enabled == true
    error_message = "Storage the module creates should follow a public workspace."
  }
}

run "private_workspace_gets_private_storage" {
  command = plan

  assert {
    condition     = local.storage_public_network_access_enabled == false
    error_message = "Storage the module creates should follow a private workspace."
  }
}

run "storage_public_access_can_be_overridden" {
  command = plan

  variables {
    public_network_access_enabled = true
    storage_account = {
      name                          = "stsynwtest"
      public_network_access_enabled = false
    }
  }

  assert {
    condition     = local.storage_public_network_access_enabled == false
    error_message = "An explicit storage_account.public_network_access_enabled should win over the workspace's setting."
  }
}

run "private_endpoints_per_subresource" {
  command = plan

  variables {
    private_endpoints = {
      Dev = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dev.azuresynapse.net"]
        private_ip_address   = "10.0.0.6"
      }
      SqlOnDemand = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["Dev"].name == "pep-synw-test-dev" && azurerm_private_endpoint.this["SqlOnDemand"].custom_network_interface_name == "nic-pep-synw-test-sqlondemand"
    error_message = "Private endpoint and NIC names should follow the pep-/nic-pep- convention with a lowercased sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this["Dev"].ip_configuration[0].member_name == "Dev" && azurerm_private_endpoint.this["Dev"].private_service_connection[0].subresource_names == tolist(["Dev"])
    error_message = "Each endpoint should target its key's sub-resource and member."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["SqlOnDemand"].ip_configuration) == 0 && length(azurerm_private_endpoint.this["SqlOnDemand"].private_dns_zone_group) == 0
    error_message = "Without a static IP or DNS zones, no ip_configuration or DNS zone group should be set."
  }
}

run "storage_private_endpoints_pass_through" {
  command = plan

  variables {
    storage_account = {
      name = "stsynwtest"
      private_endpoints = {
        dfs = {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        }
      }
    }
  }

  assert {
    condition     = toset(keys(output.storage_private_endpoints)) == toset(["dfs"])
    error_message = "Storage private endpoints should be passed to the storage-account module."
  }
}

run "managed_network_and_exfiltration_protection" {
  command = plan

  variables {
    data_exfiltration_protection_enabled = true
    linking_allowed_for_aad_tenant_ids   = ["00000000-0000-0000-0000-000000000001"]
    managed_private_endpoints = {
      sql-server = {
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Sql/servers/sql-test"
        subresource_name   = "sqlServer"
      }
    }
  }

  assert {
    condition     = azurerm_synapse_workspace.this.data_exfiltration_protection_enabled == true && azurerm_synapse_workspace.this.linking_allowed_for_aad_tenant_ids == tolist(["00000000-0000-0000-0000-000000000001"])
    error_message = "Exfiltration protection and allowed tenants should be passed through."
  }

  assert {
    condition     = azurerm_synapse_managed_private_endpoint.this["sql-server"].name == "sql-server" && azurerm_synapse_managed_private_endpoint.this["sql-server"].subresource_name == "sqlServer"
    error_message = "Managed private endpoints should be named after their key."
  }
}

run "supplied_sql_administrator_password" {
  command = plan

  variables {
    sql_administrator_password = "Supplied-Passw0rd!"
    sql_administrator_password_secret = {
      key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }

  assert {
    condition     = length(random_password.sql_administrator) == 0
    error_message = "No password should be generated when one is supplied."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.sql_administrator_login_password == "Supplied-Passw0rd!" && output.sql_administrator_password == "Supplied-Passw0rd!"
    error_message = "The supplied password should be used and output."
  }

  assert {
    condition     = azurerm_key_vault_secret.sql_administrator_password[0].value == "Supplied-Passw0rd!"
    error_message = "The supplied password should be stored in Key Vault."
  }
}

run "sql_administrator_secret_and_entra_admin" {
  command = plan

  variables {
    azuread_authentication_only = false
    sql_administrator_login     = "synapseadmin"
    sql_administrator_password_secret = {
      key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    }
    entra_admin = {
      login     = "sql-admins"
      object_id = "00000000-0000-0000-0000-000000000006"
    }
  }

  assert {
    condition     = azurerm_synapse_workspace.this.azuread_authentication_only == false && azurerm_synapse_workspace.this.sql_administrator_login == "synapseadmin"
    error_message = "SQL auth settings should be passed through."
  }

  assert {
    condition     = azurerm_key_vault_secret.sql_administrator_password[0].name == "synw-test-sql-admin-password" && azurerm_key_vault_secret.sql_administrator_password[0].content_type == "password"
    error_message = "The password secret should get a default name and the password content type."
  }

  assert {
    condition     = azurerm_synapse_workspace_aad_admin.this[0].tenant_id == "00000000-0000-0000-0000-000000000001" && azurerm_synapse_workspace_aad_admin.this[0].login == "sql-admins"
    error_message = "The Entra admin should default to the current tenant."
  }
}

run "spark_pools" {
  command = plan

  variables {
    spark_pools = {
      synspauto = {}
      fixed = {
        name                        = "synspfixed"
        node_size                   = "Large"
        node_count                  = 5
        auto_pause_delay_in_minutes = 0
      }
    }
  }

  assert {
    condition     = azurerm_synapse_spark_pool.this["synspauto"].name == "synspauto" && azurerm_synapse_spark_pool.this["synspauto"].auto_scale[0].min_node_count == 3 && azurerm_synapse_spark_pool.this["synspauto"].auto_scale[0].max_node_count == 10
    error_message = "Pools should auto-scale between 3 and 10 nodes by default."
  }

  assert {
    condition     = azurerm_synapse_spark_pool.this["synspauto"].auto_pause[0].delay_in_minutes == 15 && azurerm_synapse_spark_pool.this["synspauto"].spark_version == "3.5"
    error_message = "Pools should pause after 15 idle minutes and use Spark 3.5 by default."
  }

  assert {
    condition     = azurerm_synapse_spark_pool.this["fixed"].name == "synspfixed" && azurerm_synapse_spark_pool.this["fixed"].node_count == 5 && length(azurerm_synapse_spark_pool.this["fixed"].auto_scale) == 0
    error_message = "node_count should set a fixed size instead of auto-scaling."
  }

  assert {
    condition     = length(azurerm_synapse_spark_pool.this["fixed"].auto_pause) == 0
    error_message = "auto_pause_delay_in_minutes = 0 should disable auto-pause."
  }
}

run "github_repo_and_user_assigned_identity" {
  command = plan

  variables {
    github_repo = {
      account_name    = "psu-oeo"
      repository_name = "datalake"
      branch_name     = "main"
      root_folder     = "/synapse"
    }
    identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"]
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].repository_name == "datalake" && azurerm_synapse_workspace.this.github_repo[0].root_folder == "/synapse"
    error_message = "github_repo should configure Git integration."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.identity[0].type == "SystemAssigned, UserAssigned"
    error_message = "identity_ids should add user-assigned identities alongside the system-assigned one."
  }
}

run "lock_diagnostics_and_role_assignments" {
  command = plan

  variables {
    lock = {
      kind = "CanNotDelete"
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
    role_assignments = {
      readers = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000007"
      }
    }
    synapse_role_assignments = {
      admins = {
        role_name      = "Synapse Administrator"
        principal_id   = "00000000-0000-0000-0000-000000000008"
        principal_type = "Group"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this[0].name == "lock-synw-test" && azurerm_management_lock.this[0].lock_level == "CanNotDelete"
    error_message = "The workspace lock should use the requested level and a default name."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Diagnostics should be created."
  }

  assert {
    condition     = azurerm_role_assignment.this["readers"].role_definition_name == "Reader"
    error_message = "Azure RBAC role assignments should be passed through."
  }

  assert {
    condition     = azurerm_synapse_role_assignment.this["admins"].role_name == "Synapse Administrator" && azurerm_synapse_role_assignment.this["admins"].principal_type == "Group"
    error_message = "Synapse RBAC role assignments should be passed through."
  }
}

run "private_dns_records_include_storage" {
  command = plan

  variables {
    private_endpoints = {
      Dev = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dev.azuresynapse.net"]
      }
    }
    storage_account = {
      name = "stsynwtest"
      private_endpoints = {
        dfs = {
          subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
          private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"]
        }
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.dev.azuresynapse.net"
        name                = "privatelink.dev.azuresynapse.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dev.azuresynapse.net"
        record_sets = [{
          name         = "synw-test"
          fqdn         = "synw-test.privatelink.dev.azuresynapse.net"
          type         = "A"
          ip_addresses = ["10.0.0.6"]
          ttl          = 10
        }]
      }]
    }
  }

  override_resource {
    target = module.storage_account.azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.dfs.core.windows.net"
        name                = "privatelink.dfs.core.windows.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
        record_sets = [{
          name         = "stsynwtest"
          fqdn         = "stsynwtest.privatelink.dfs.core.windows.net"
          type         = "A"
          ip_addresses = ["10.0.0.5"]
          ttl          = 10
        }]
      }]
    }
  }

  assert {
    condition = toset([for r in output.private_dns_records : "${r.resource}/${r.subresource}/${r.zone_name}/${r.ip_addresses[0]}"]) == toset([
      "synw-test/Dev/privatelink.dev.azuresynapse.net/10.0.0.6",
      "stsynwtest/dfs/privatelink.dfs.core.windows.net/10.0.0.5",
    ])
    error_message = "private_dns_records should list the workspace's and its storage's records: ${jsonencode(output.private_dns_records)}"
  }
}

run "policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      Dev = {
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
        name                = "privatelink.dev.azuresynapse.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dev.azuresynapse.net"
        record_sets = [{
          name         = "synw-test"
          fqdn         = "synw-test.privatelink.dev.azuresynapse.net"
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
    condition     = azurerm_private_endpoint.this_unmanaged_dns_zone_group["Dev"].name == "pep-synw-test-dev" && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group["Dev"].private_dns_zone_group) == 0
    error_message = "The endpoint should keep its name and get no zone group from this module."
  }

  assert {
    condition     = output.private_endpoints["Dev"] != null && length(output.private_dns_records) == 1 && output.private_dns_records[0].zone_name == "privatelink.dev.azuresynapse.net"
    error_message = "Outputs should include policy-managed endpoints and the records the policy registered: ${jsonencode(output.private_dns_records)}"
  }
}

run "storage_inherits_policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
  }

  assert {
    condition     = local.storage_private_endpoints_manage_dns_zone_group == false
    error_message = "Storage the module creates should follow the workspace's DNS management."
  }
}

run "storage_dns_management_can_be_overridden" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    storage_account = {
      name                                    = "stsynwtest"
      private_endpoints_manage_dns_zone_group = true
    }
  }

  assert {
    condition     = local.storage_private_endpoints_manage_dns_zone_group == true
    error_message = "An explicit storage_account setting should win over the workspace's."
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
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_log) == 1 && one(azurerm_monitor_diagnostic_setting.this[0].enabled_log).category_group == "allLogs"
    error_message = "Workspace logs should default to the allLogs category group."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_metric) == 0
    error_message = "The workspace should send no metrics by default."
  }

  assert {
    condition     = local.storage_diagnostic_settings.log_categories == null && local.storage_diagnostic_settings.metric_categories == null && local.storage_diagnostic_settings.name == "diag-log-analytics"
    error_message = "The storage account should get the storage-account module's default categories."
  }
}

run "diagnostics_custom_categories" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = ["SynapseRbacOperations", "IntegrationPipelineRuns"]
      metric_categories          = ["AllMetrics"]
      storage_log_categories     = ["StorageWrite"]
      storage_metric_categories  = []
    }
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.this[0].enabled_log : l.category]) == toset(["SynapseRbacOperations", "IntegrationPipelineRuns"]) && alltrue([for l in azurerm_monitor_diagnostic_setting.this[0].enabled_log : l.category_group == null])
    error_message = "Exactly the requested workspace log categories should be enabled."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.this[0].enabled_metric : m.category]) == toset(["AllMetrics"])
    error_message = "The requested workspace metric categories should be enabled."
  }

  assert {
    condition     = toset(local.storage_diagnostic_settings.log_categories) == toset(["StorageWrite"]) && length(local.storage_diagnostic_settings.metric_categories) == 0
    error_message = "The storage categories should be passed to the storage-account module."
  }
}

run "diagnostics_metrics_only" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
      metric_categories          = ["AllMetrics"]
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_log) == 0 && length(azurerm_monitor_diagnostic_setting.this[0].enabled_metric) == 1
    error_message = "Only metrics should be enabled when logs are turned off."
  }
}

run "azure_services_access_rule" {
  command = plan

  variables {
    public_network_access_enabled = true
    azure_services_access_enabled = true
  }

  assert {
    condition     = azurerm_synapse_firewall_rule.azure_services[0].name == "AllowAllWindowsAzureIps" && azurerm_synapse_firewall_rule.azure_services[0].start_ip_address == "0.0.0.0" && azurerm_synapse_firewall_rule.azure_services[0].end_ip_address == "0.0.0.0"
    error_message = "Azure services access should add the AllowAllWindowsAzureIps rule."
  }

  assert {
    condition     = length(azurerm_synapse_firewall_rule.allow_all) == 1
    error_message = "The AllowAll rule should still be created for a public workspace."
  }
}

run "azure_services_access_off_by_default" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = length(azurerm_synapse_firewall_rule.azure_services) == 0
    error_message = "The AllowAllWindowsAzureIps rule should be opt-in."
  }
}

run "storage_role_assignments_are_accepted" {
  command = plan

  variables {
    storage_account = {
      name = "stsynwtest"
      role_assignments = {
        readers = {
          role_definition_id_or_name = "Storage Blob Data Reader"
          principal_id               = "00000000-0000-0000-0000-000000000009"
          principal_type             = "Group"
        }
      }
    }
  }

  assert {
    condition     = var.storage_account.role_assignments["readers"].role_definition_id_or_name == "Storage Blob Data Reader"
    error_message = "Storage role assignments should be accepted and passed to the storage-account module."
  }
}
