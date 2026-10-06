# Plans each example end to end against mocked providers, so the examples
# can't drift from the module's interface unnoticed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test-001"
    }
  }
  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    }
  }

  mock_data "azurerm_subnet" {
    defaults = {
      id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      address_prefixes = ["10.0.0.0/27"]
    }
  }
}

mock_provider "random" {}

run "private_example_plans" {
  command = plan

  module {
    source = "./examples/private"
  }

  variables {
    subscription_id             = "00000000-0000-0000-0000-000000000000"
    network_resource_group_name = "rg-network"
    virtual_network_name        = "vnet-test"
    subnet_name                 = "snet-test"
    log_analytics_workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
  }

  assert {
    condition     = module.key_vault.private_endpoints["vault"] != null
    error_message = "The example should create the vault private endpoint."
  }
}
