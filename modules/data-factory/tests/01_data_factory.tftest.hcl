mock_provider "azurerm" {
  mock_resource "azurerm_data_factory" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DataFactory/factories/adf-test"
      identity = {
        principal_id = "00000000-0000-0000-0000-000000000005"
        tenant_id    = "00000000-0000-0000-0000-000000000001"
      }
    }
  }
}

variables {
  name                = "adf-test"
  resource_group_name = "rg-test"
  location            = "eastus"
}

run "defaults_are_private_with_managed_network" {
  command = plan

  assert {
    condition     = azurerm_data_factory.this.public_network_enabled == false && azurerm_data_factory.this.managed_virtual_network_enabled == true
    error_message = "Public network access should be off, and the managed virtual network on, by default."
  }

  assert {
    condition     = azurerm_data_factory.this.identity[0].type == "SystemAssigned"
    error_message = "The factory should have a system-assigned identity."
  }

  assert {
    condition     = output.identity_principal_id == "00000000-0000-0000-0000-000000000005"
    error_message = "identity_principal_id should expose the factory's managed identity."
  }

  assert {
    condition = (
      length(azurerm_data_factory_integration_runtime_azure.managed) == 0 && length(azurerm_data_factory_managed_private_endpoint.this) == 0 &&
      length(azurerm_private_endpoint.this) == 0 && length(azurerm_management_lock.this) == 0 &&
      length(azurerm_monitor_diagnostic_setting.this) == 0 && length(azurerm_role_assignment.this) == 0 &&
      length(azurerm_data_factory.this.github_configuration) == 0
    )
    error_message = "No optional resources should be created by default."
  }
}

run "public_access_can_be_enabled" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_data_factory.this.public_network_enabled == true
    error_message = "Public network access should be enabled when requested."
  }
}

run "managed_integration_runtime_defaults" {
  command = plan

  variables {
    managed_integration_runtime = {}
  }

  assert {
    condition     = azurerm_data_factory_integration_runtime_azure.managed[0].virtual_network_enabled == true && azurerm_data_factory_integration_runtime_azure.managed[0].name == "ir-managed-vnet"
    error_message = "The managed integration runtime should run in the managed virtual network."
  }

  assert {
    condition     = azurerm_data_factory_integration_runtime_azure.managed[0].location == "AutoResolve" && azurerm_data_factory_integration_runtime_azure.managed[0].compute_type == "General" && azurerm_data_factory_integration_runtime_azure.managed[0].core_count == 8
    error_message = "Unexpected managed integration runtime defaults."
  }

  assert {
    condition     = output.managed_integration_runtime_name == "ir-managed-vnet"
    error_message = "managed_integration_runtime_name should expose the runtime's name."
  }
}

run "managed_private_endpoints" {
  command = plan

  variables {
    managed_private_endpoints = {
      data-lake-dfs = {
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stlake"
        subresource_name   = "dfs"
      }
      sql = {
        name               = "mpe-sql"
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Sql/servers/sql-test"
        subresource_name   = "sqlServer"
      }
    }
  }

  assert {
    condition     = azurerm_data_factory_managed_private_endpoint.this["data-lake-dfs"].name == "data-lake-dfs" && azurerm_data_factory_managed_private_endpoint.this["data-lake-dfs"].subresource_name == "dfs"
    error_message = "Managed private endpoints should be named after their key."
  }

  assert {
    condition     = azurerm_data_factory_managed_private_endpoint.this["sql"].name == "mpe-sql"
    error_message = "An explicit managed private endpoint name should be honored."
  }
}

run "private_endpoints_per_subresource" {
  command = plan

  variables {
    private_endpoints = {
      dataFactory = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.datafactory.azure.net"]
        private_ip_address   = "10.0.0.4"
      }
      portal = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["dataFactory"].name == "pep-adf-test-datafactory" && azurerm_private_endpoint.this["portal"].custom_network_interface_name == "nic-pep-adf-test-portal"
    error_message = "Private endpoint and NIC names should follow the pep-/nic-pep- convention with a lowercased sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this["dataFactory"].ip_configuration[0].private_ip_address == "10.0.0.4" && azurerm_private_endpoint.this["dataFactory"].ip_configuration[0].member_name == "dataFactory"
    error_message = "A static IP should create an ip_configuration for the sub-resource's member."
  }

  assert {
    condition     = azurerm_private_endpoint.this["portal"].private_service_connection[0].subresource_names == tolist(["portal"]) && length(azurerm_private_endpoint.this["portal"].ip_configuration) == 0
    error_message = "Each endpoint should target its key's sub-resource, with a dynamic IP unless one is given."
  }
}

run "github_configuration_and_user_assigned_identity" {
  command = plan

  variables {
    github_configuration = {
      account_name    = "psu-oeo"
      repository_name = "crmdataexport"
      branch_name     = "main"
      root_folder     = "/datafactory"
    }
    identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"]
  }

  assert {
    condition     = azurerm_data_factory.this.github_configuration[0].root_folder == "/datafactory" && azurerm_data_factory.this.github_configuration[0].publishing_enabled == true
    error_message = "github_configuration should configure Git integration, with publishing enabled by default."
  }

  assert {
    condition     = azurerm_data_factory.this.identity[0].type == "SystemAssigned, UserAssigned"
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
      developers = {
        role_definition_id_or_name = "Data Factory Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000007"
        principal_type             = "Group"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this[0].name == "lock-adf-test" && azurerm_management_lock.this[0].lock_level == "CanNotDelete"
    error_message = "The lock should use the requested level and a default name."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Diagnostics should be created."
  }

  assert {
    condition     = azurerm_role_assignment.this["developers"].role_definition_name == "Data Factory Contributor"
    error_message = "Role assignments should be passed through."
  }
}

run "private_dns_records_output" {
  command = plan

  variables {
    private_endpoints = {
      dataFactory = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.datafactory.azure.net"]
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.datafactory.azure.net"
        name                = "privatelink.datafactory.azure.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.datafactory.azure.net"
        record_sets = [{
          name         = "adf-test.eastus"
          fqdn         = "adf-test.eastus.privatelink.datafactory.azure.net"
          type         = "A"
          ip_addresses = ["10.0.0.4"]
          ttl          = 10
        }]
      }]
    }
  }

  assert {
    condition     = length(output.private_dns_records) == 1 && output.private_dns_records[0].subresource == "dataFactory" && output.private_dns_records[0].zone_name == "privatelink.datafactory.azure.net" && output.private_dns_records[0].fqdn == "adf-test.eastus.privatelink.datafactory.azure.net"
    error_message = "private_dns_records should list the factory's A record: ${jsonencode(output.private_dns_records)}"
  }
}

run "policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      dataFactory = {
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
        name                = "privatelink.datafactory.azure.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.datafactory.azure.net"
        record_sets = [{
          name         = "adf-test"
          fqdn         = "adf-test.privatelink.datafactory.azure.net"
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
    condition     = azurerm_private_endpoint.this_unmanaged_dns_zone_group["dataFactory"].name == "pep-adf-test-datafactory" && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group["dataFactory"].private_dns_zone_group) == 0
    error_message = "The endpoint should keep its name and get no zone group from this module."
  }

  assert {
    condition     = output.private_endpoints["dataFactory"] != null && length(output.private_dns_records) == 1 && output.private_dns_records[0].zone_name == "privatelink.datafactory.azure.net"
    error_message = "Outputs should include policy-managed endpoints and the records the policy registered: ${jsonencode(output.private_dns_records)}"
  }
}

