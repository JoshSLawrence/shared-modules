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
}

variables {
  name                = "kv-test-001"
  resource_group_name = "rg-test"
  location            = "eastus"
}

run "name_too_long" {
  command = plan

  variables {
    name = "kv-this-name-is-far-too-long"
  }

  expect_failures = [var.name]
}

run "name_with_consecutive_hyphens" {
  command = plan

  variables {
    name = "kv--test"
  }

  expect_failures = [var.name]
}

run "name_starting_with_digit" {
  command = plan

  variables {
    name = "1kv-test"
  }

  expect_failures = [var.name]
}

run "tenant_id_must_be_guid" {
  command = plan

  variables {
    tenant_id = "not-a-guid"
  }

  expect_failures = [var.tenant_id]
}

run "sku_name_is_validated" {
  command = plan

  variables {
    sku_name = "basic"
  }

  expect_failures = [var.sku_name]
}

run "soft_delete_retention_below_minimum" {
  command = plan

  variables {
    soft_delete_retention_days = 6
  }

  expect_failures = [var.soft_delete_retention_days]
}

run "soft_delete_retention_above_maximum" {
  command = plan

  variables {
    soft_delete_retention_days = 91
  }

  expect_failures = [var.soft_delete_retention_days]
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
      vault = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0.300"
      }
    }
  }

  expect_failures = [var.private_endpoints]
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

run "dns_zone_ids_rejected_when_dns_is_policy_managed" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      vault = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
      }
    }
  }

  expect_failures = [var.private_endpoints]
}

