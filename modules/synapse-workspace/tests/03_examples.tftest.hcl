# Plans each example end to end against mocked providers, so the examples
# can't drift from the module's interface unnoticed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
    }
  }

  mock_data "azurerm_subnet" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      address_prefixes = ["10.0.0.0/27"]
    }
  }

  mock_resource "azurerm_synapse_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Synapse/workspaces/synw-test"
      connectivity_endpoints = {
        dev         = "https://synw-test.dev.azuresynapse.net"
        sql         = "synw-test.sql.azuresynapse.net"
        sqlOnDemand = "synw-test-ondemand.sql.azuresynapse.net"
        web         = "https://web.azuresynapse.net?workspace=synw-test"
      }
      identity = {
        principal_id = "00000000-0000-0000-0000-000000000005"
        tenant_id    = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
      primary_dfs_endpoint = "https://sttest001.dfs.core.windows.net/"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    }
  }
}

mock_provider "random" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "private_example_plans" {
  command = plan

  module {
    source = "./examples/private"
  }

  variables {
    network_resource_group_name = "rg-network"
    virtual_network_name        = "vnet-test"
    subnet_name                 = "snet-test"
    log_analytics_workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    sql_admin_group = {
      display_name = "sql-admins"
      object_id    = "00000000-0000-0000-0000-000000000006"
    }
  }

  assert {
    condition     = toset(keys(output.private_endpoint_ips)) == toset(["Dev", "Sql", "SqlOnDemand"])
    error_message = "The example should create all three workspace private endpoints."
  }
}

run "existing_storage_example_plans" {
  command = plan

  module {
    source = "./examples/existing-storage"
  }

  variables {
    synapse_admin_group_object_id = "00000000-0000-0000-0000-000000000008"
  }

  assert {
    condition     = module.synapse_workspace.data_lake_filesystem_id == "https://sttest001.dfs.core.windows.net/synapse"
    error_message = "The workspace should use the data lake's synapse file system."
  }
}
