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
}

variables {
  name                = "sql-test-001"
  resource_group_name = "rg-test"
  location            = "eastus"
  entra_admin = {
    login     = "sg-sql-admins"
    object_id = "00000000-0000-0000-0000-000000000010"
  }
}

run "name_too_long" {
  command = plan

  variables {
    name = "sql-this-name-is-far-too-long-for-an-azure-sql-server-so-it-fails"
  }

  expect_failures = [var.name]
}

run "name_with_uppercase" {
  command = plan

  variables {
    name = "SQL-Test"
  }

  expect_failures = [var.name]
}

run "name_starting_with_hyphen" {
  command = plan

  variables {
    name = "-sql-test"
  }

  expect_failures = [var.name]
}

run "name_ending_with_hyphen" {
  command = plan

  variables {
    name = "sql-test-"
  }

  expect_failures = [var.name]
}

run "entra_admin_object_id_must_be_guid" {
  command = plan

  variables {
    entra_admin = {
      login     = "sg-sql-admins"
      object_id = "not-a-guid"
    }
  }

  expect_failures = [var.entra_admin]
}

run "entra_admin_tenant_id_must_be_guid" {
  command = plan

  variables {
    entra_admin = {
      login     = "sg-sql-admins"
      object_id = "00000000-0000-0000-0000-000000000010"
      tenant_id = "not-a-guid"
    }
  }

  expect_failures = [var.entra_admin]
}

run "database_storage_account_type_is_validated" {
  command = plan

  variables {
    databases = {
      app = {
        storage_account_type = "Premium"
      }
    }
  }

  expect_failures = [var.databases]
}

run "private_endpoint_subresource_is_validated" {
  command = plan

  variables {
    private_endpoints = {
      blob = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "private_endpoint_ip_is_validated" {
  command = plan

  variables {
    private_endpoints = {
      sqlServer = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0.300"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "dns_zone_ids_rejected_when_dns_is_policy_managed" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      sqlServer = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "diagnostics_must_send_something" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
      metric_categories          = []
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "lock_kind_is_validated" {
  command = plan

  variables {
    lock = {
      kind = "DoNotDelete"
    }
  }

  expect_failures = [var.lock]
}

run "role_assignment_principal_type_is_validated" {
  command = plan

  variables {
    role_assignments = {
      bad = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000003"
        principal_type             = "Robot"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "auditing_requires_diagnostic_settings" {
  command = plan

  variables {
    auditing_enabled = true
  }

  expect_failures = [var.auditing_enabled]
}

run "auto_pause_requires_serverless_sku" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name                    = "S0"
        auto_pause_delay_in_minutes = 60
      }
    }
  }

  expect_failures = [var.databases]
}

run "auto_pause_not_on_hyperscale_serverless" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name                    = "HS_S_Gen5_2"
        auto_pause_delay_in_minutes = 60
      }
    }
  }

  expect_failures = [var.databases]
}

run "auto_pause_delay_range" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name                    = "GP_S_Gen5_2"
        auto_pause_delay_in_minutes = 5
      }
    }
  }

  expect_failures = [var.databases]
}

run "min_capacity_requires_serverless_sku" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name     = "GP_Gen5_2"
        min_capacity = 0.5
      }
    }
  }

  expect_failures = [var.databases]
}

run "min_capacity_must_be_positive" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name     = "GP_S_Gen5_2"
        min_capacity = 0
      }
    }
  }

  expect_failures = [var.databases]
}
