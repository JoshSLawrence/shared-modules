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

run "name_with_uppercase" {
  command = plan

  variables {
    name = "Synw-Test"
  }

  expect_failures = [var.name]
}

run "name_with_ondemand" {
  command = plan

  variables {
    name = "synw-test-ondemand"
  }

  expect_failures = [var.name]
}

run "name_too_long" {
  command = plan

  variables {
    name = "synw-this-workspace-name-is-much-longer-than-fifty-chars"
  }

  expect_failures = [var.name]
}

run "storage_both_set" {
  command = plan

  variables {
    existing_storage = {
      data_lake_filesystem_id = "https://stexisting.dfs.core.windows.net/synapse"
      storage_account_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
    }
  }

  expect_failures = [var.existing_storage]
}

run "storage_neither_set" {
  command = plan

  variables {
    storage_account = null
  }

  expect_failures = [var.existing_storage]
}

run "existing_filesystem_id_format" {
  command = plan

  variables {
    storage_account = null
    existing_storage = {
      data_lake_filesystem_id = "https://stexisting.blob.core.windows.net/synapse"
      storage_account_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stexisting"
    }
  }

  expect_failures = [var.existing_storage]
}

run "storage_private_endpoint_subresource_is_validated" {
  command = plan

  variables {
    storage_account = {
      name = "stsynwtest"
      private_endpoints = {
        Dev = {
          subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        }
      }
    }
  }

  expect_failures = [var.storage_account]
}

run "storage_private_endpoint_ip_is_validated" {
  command = plan

  variables {
    storage_account = {
      name = "stsynwtest"
      private_endpoints = {
        dfs = {
          subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
          private_ip_address = "10.0.0.999"
        }
      }
    }
  }

  expect_failures = [var.storage_account]
}

run "private_endpoint_subresource_is_case_sensitive" {
  command = plan

  variables {
    private_endpoints = {
      dev = {
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
      Sql = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0.256"
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "linked_tenants_require_exfiltration_protection" {
  command = plan

  variables {
    linking_allowed_for_aad_tenant_ids = ["00000000-0000-0000-0000-000000000001"]
  }

  expect_failures = [var.linking_allowed_for_aad_tenant_ids]
}

run "managed_private_endpoint_name_is_validated" {
  command = plan

  variables {
    managed_private_endpoints = {
      "-bad" = {
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
        subresource_name   = "vault"
      }
    }
  }

  expect_failures = [var.managed_private_endpoints]
}

run "storage_managed_private_endpoint_subresource" {
  command = plan

  variables {
    storage_managed_private_endpoints = ["file"]
  }

  expect_failures = [var.storage_managed_private_endpoints]
}

run "sql_login_reserved_name" {
  command = plan

  variables {
    sql_administrator_login = "Admin"
  }

  expect_failures = [var.sql_administrator_login]
}

run "sql_login_format" {
  command = plan

  variables {
    sql_administrator_login = "sql-admin"
  }

  expect_failures = [var.sql_administrator_login]
}

run "supplied_password_too_short" {
  command = plan

  variables {
    sql_administrator_password = "Ab1!"
  }

  expect_failures = [var.sql_administrator_password]
}

run "supplied_password_too_simple" {
  command = plan

  variables {
    sql_administrator_password = "alllowercaseletters"
  }

  expect_failures = [var.sql_administrator_password]
}

run "password_secret_name_is_validated" {
  command = plan

  variables {
    sql_administrator_password_secret = {
      key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
      name         = "not_valid"
    }
  }

  expect_failures = [var.sql_administrator_password_secret]
}

run "password_secret_expiration_is_validated" {
  command = plan

  variables {
    sql_administrator_password_secret = {
      key_vault_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
      expiration_date = "2027-01-01"
    }
  }

  expect_failures = [var.sql_administrator_password_secret]
}

run "entra_admin_object_id_is_validated" {
  command = plan

  variables {
    entra_admin = {
      login     = "sql-admins"
      object_id = "not-a-guid"
    }
  }

  expect_failures = [var.entra_admin]
}

run "spark_pool_name_is_validated" {
  command = plan

  variables {
    spark_pools = {
      "spark-pool" = {}
    }
  }

  expect_failures = [var.spark_pools]
}

run "spark_pool_node_size_family_is_validated" {
  command = plan

  variables {
    spark_pools = {
      synsp = {
        node_size_family = "ComputeOptimized"
      }
    }
  }

  expect_failures = [var.spark_pools]
}

run "spark_pool_node_size_is_validated" {
  command = plan

  variables {
    spark_pools = {
      synsp = {
        node_size = "Tiny"
      }
    }
  }

  expect_failures = [var.spark_pools]
}

run "spark_pool_auto_scale_is_validated" {
  command = plan

  variables {
    spark_pools = {
      synsp = {
        auto_scale_min_node_count = 10
        auto_scale_max_node_count = 5
      }
    }
  }

  expect_failures = [var.spark_pools]
}

run "spark_pool_node_count_is_validated" {
  command = plan

  variables {
    spark_pools = {
      synsp = {
        node_count = 2
      }
    }
  }

  expect_failures = [var.spark_pools]
}

run "lock_kind_is_validated" {
  command = plan

  variables {
    lock = {
      kind = "NoDelete"
    }
  }

  expect_failures = [var.lock]
}

run "synapse_role_principal_type_is_validated" {
  command = plan

  variables {
    synapse_role_assignments = {
      bad = {
        role_name      = "Synapse Administrator"
        principal_id   = "00000000-0000-0000-0000-000000000008"
        principal_type = "Application"
      }
    }
  }

  expect_failures = [var.synapse_role_assignments]
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
      Dev = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dev.azuresynapse.net"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

run "storage_dns_zone_ids_rejected_when_dns_is_policy_managed" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    storage_account = {
      name = "stsynwtest"
      private_endpoints = {
        dfs = {
          subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
          private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"]
        }
      }
    }
  }

  expect_failures = [var.storage_account]
}

run "workspace_diagnostics_with_nothing_enabled" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "storage_diagnostics_with_nothing_enabled" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      storage_log_categories     = []
      storage_metric_categories  = []
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "azure_services_access_requires_public_access" {
  command = plan

  variables {
    azure_services_access_enabled = true
  }

  expect_failures = [var.azure_services_access_enabled]
}

run "storage_role_assignment_principal_type_is_validated" {
  command = plan

  variables {
    storage_account = {
      name = "stsynwtest"
      role_assignments = {
        bad = {
          role_definition_id_or_name = "Reader"
          principal_id               = "00000000-0000-0000-0000-000000000009"
          principal_type             = "Robot"
        }
      }
    }
  }

  expect_failures = [var.storage_account]
}
