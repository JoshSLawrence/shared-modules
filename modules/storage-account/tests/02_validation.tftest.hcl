mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
    }
  }
}

variables {
  name                = "sttest001"
  resource_group_name = "rg-test"
  location            = "eastus"
}

run "name_with_uppercase" {
  command = plan

  variables {
    name = "StTest001"
  }

  expect_failures = [var.name]
}

run "name_with_hyphen" {
  command = plan

  variables {
    name = "st-test-001"
  }

  expect_failures = [var.name]
}

run "account_kind_is_validated" {
  command = plan

  variables {
    account_kind = "Storage"
  }

  expect_failures = [var.account_kind]
}

run "account_tier_is_validated" {
  command = plan

  variables {
    account_tier = "Basic"
  }

  expect_failures = [var.account_tier]
}

run "replication_type_is_validated" {
  command = plan

  variables {
    account_replication_type = "GEO"
  }

  expect_failures = [var.account_replication_type]
}

run "access_tier_is_validated" {
  command = plan

  variables {
    access_tier = "Archive"
  }

  expect_failures = [var.access_tier]
}

run "retention_days_are_validated" {
  command = plan

  variables {
    blob_properties = {
      delete_retention_days = 366
    }
  }

  expect_failures = [var.blob_properties]
}

run "container_name_is_validated" {
  command = plan

  variables {
    containers = {
      Bronze = {}
    }
  }

  expect_failures = [var.containers]
}

run "container_name_rejects_consecutive_hyphens" {
  command = plan

  variables {
    containers = {
      raw = {
        name = "raw--landing"
      }
    }
  }

  expect_failures = [var.containers]
}

run "private_endpoint_subresource_is_validated" {
  command = plan

  variables {
    private_endpoints = {
      vault = {
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
      blob = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "lock_kind_is_validated" {
  command = plan

  variables {
    lock = {
      kind = "Delete"
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
        principal_type             = "Device"
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
      dfs = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"]
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

run "container_role_assignment_principal_type_is_validated" {
  command = plan

  variables {
    containers = {
      reports = {
        role_assignments = {
          bad = {
            role_definition_id_or_name = "Storage Blob Data Reader"
            principal_id               = "00000000-0000-0000-0000-0000000000aa"
            principal_type             = "Robot"
          }
        }
      }
    }
  }

  expect_failures = [var.containers]
}
