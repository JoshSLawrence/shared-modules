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

run "name_too_short" {
  command = plan

  variables {
    name = "ad"
  }

  expect_failures = [var.name]
}

run "name_with_consecutive_hyphens" {
  command = plan

  variables {
    name = "adf--test"
  }

  expect_failures = [var.name]
}

run "name_ending_with_hyphen" {
  command = plan

  variables {
    name = "adf-test-"
  }

  expect_failures = [var.name]
}

run "integration_runtime_compute_type_is_validated" {
  command = plan

  variables {
    managed_integration_runtime = {
      compute_type = "ComputeOptimized"
    }
  }

  expect_failures = [var.managed_integration_runtime]
}

run "integration_runtime_core_count_is_validated" {
  command = plan

  variables {
    managed_integration_runtime = {
      core_count = 12
    }
  }

  expect_failures = [var.managed_integration_runtime]
}

run "managed_private_endpoint_name_is_validated" {
  command = plan

  variables {
    managed_private_endpoints = {
      "lake dfs" = {
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stlake"
        subresource_name   = "dfs"
      }
    }
  }

  expect_failures = [var.managed_private_endpoints]
}

run "private_endpoint_subresource_is_case_sensitive" {
  command = plan

  variables {
    private_endpoints = {
      datafactory = {
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
      portal = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "not-an-ip"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "lock_kind_is_validated" {
  command = plan

  variables {
    lock = {
      kind = "Locked"
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
        principal_id               = "00000000-0000-0000-0000-000000000007"
        principal_type             = "Application"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "dns_zone_ids_rejected_when_dns_is_policy_managed" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      dataFactory = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.datafactory.azure.net"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}


run "diagnostics_with_nothing_enabled" {
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
