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
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }

  mock_data "azurerm_subnet" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      address_prefixes = ["10.0.0.0/27"]
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
      primary_dfs_endpoint = "https://sttest001.dfs.core.windows.net/"
    }
  }
}

mock_provider "random" {}

run "private_data_lake_example_plans" {
  command = plan

  module {
    source = "./examples/private-data-lake"
  }

  variables {
    subscription_id             = "00000000-0000-0000-0000-000000000000"
    network_resource_group_name = "rg-network"
    virtual_network_name        = "vnet-test"
    subnet_name                 = "snet-test"
    log_analytics_workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
  }

  assert {
    condition     = toset(keys(output.data_lake_filesystem_ids)) == toset(["bronze", "silver", "gold"])
    error_message = "The example should create the bronze, silver and gold file systems."
  }
}
