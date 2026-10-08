# Plans each example end to end against mocked providers, so the examples
# can't drift from the module's interface unnoticed.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  mock_resource "azurerm_mssql_server" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001"
    }
  }

  mock_resource "azurerm_mssql_database" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001/databases/db-mock"
    }
  }

  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
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
    entra_admin_login           = "sg-sql-admins"
    entra_admin_object_id       = "00000000-0000-0000-0000-000000000010"
  }

  assert {
    condition     = module.sql_server.private_endpoints["sqlServer"] != null
    error_message = "The example should create the sqlServer private endpoint."
  }
}
