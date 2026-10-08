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

run "defaults_are_private_and_protected" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "Public network access should be disabled by default."
  }

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "The vault should always use RBAC authorization."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true && azurerm_key_vault.this.soft_delete_retention_days == 90
    error_message = "Purge protection should be on, with 90 days of soft delete retention, by default."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny" && azurerm_key_vault.this.network_acls[0].bypass == "AzureServices"
    error_message = "The firewall should deny by default and let trusted Azure services bypass it."
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == "00000000-0000-0000-0000-000000000001"
    error_message = "tenant_id should default to the current client's tenant."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 0 && length(azurerm_management_lock.this) == 0 && length(azurerm_monitor_diagnostic_setting.this) == 0 && length(azurerm_role_assignment.this) == 0
    error_message = "No optional resources should be created by default."
  }
}

run "explicit_tenant_id_is_used" {
  command = plan

  variables {
    tenant_id = "11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == "11111111-1111-1111-1111-111111111111"
    error_message = "An explicit tenant_id should override the current tenant."
  }
}

run "public_access_is_open_to_all_networks" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == true
    error_message = "Public network access should be enabled when requested."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Allow"
    error_message = "A public vault should accept traffic from every network."
  }
}

run "private_endpoint_with_static_ip_and_dns" {
  command = plan

  variables {
    private_endpoints = {
      vault = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
        private_ip_address   = "10.0.0.5"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["vault"].name == "pep-kv-test-001" && azurerm_private_endpoint.this["vault"].custom_network_interface_name == "nic-pep-kv-test-001"
    error_message = "Private endpoint and NIC names should follow the pep-/nic-pep- CAF convention."
  }

  assert {
    condition     = azurerm_private_endpoint.this["vault"].private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "The private endpoint should target the vault sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this["vault"].ip_configuration[0].private_ip_address == "10.0.0.5" && azurerm_private_endpoint.this["vault"].ip_configuration[0].member_name == "default"
    error_message = "A static IP should create an ip_configuration for the vault's \"default\" member."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["vault"].private_dns_zone_group) == 1
    error_message = "DNS zone IDs should create a private DNS zone group."
  }

  assert {
    condition     = azurerm_private_endpoint.this["vault"].resource_group_name == "rg-test" && azurerm_private_endpoint.this["vault"].location == "eastus"
    error_message = "The private endpoint should default to the vault's resource group and location."
  }
}

run "private_endpoint_dynamic_ip_without_dns" {
  command = plan

  variables {
    private_endpoints = {
      vault = {
        subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        name                = "pep-custom"
        resource_group_name = "rg-network"
      }
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["vault"].ip_configuration) == 0 && length(azurerm_private_endpoint.this["vault"].private_dns_zone_group) == 0
    error_message = "Without a static IP or DNS zones, no ip_configuration or DNS zone group should be set."
  }

  assert {
    condition     = azurerm_private_endpoint.this["vault"].name == "pep-custom" && azurerm_private_endpoint.this["vault"].resource_group_name == "rg-network"
    error_message = "Name and resource group overrides should be honored."
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
      by_name = {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = "00000000-0000-0000-0000-000000000003"
      }
      by_id = {
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
        principal_id               = "00000000-0000-0000-0000-000000000004"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this[0].lock_level == "CanNotDelete" && azurerm_management_lock.this[0].name == "lock-kv-test-001"
    error_message = "The lock should use the requested level and a default lock-<name> name."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].name == "diag-log-analytics"
    error_message = "Diagnostics should be created with the default name."
  }

  assert {
    condition     = azurerm_role_assignment.this["by_name"].role_definition_name == "Key Vault Secrets User"
    error_message = "A role name should be passed as role_definition_name."
  }

  assert {
    condition     = azurerm_role_assignment.this["by_id"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
    error_message = "A role definition ID should be passed as role_definition_id."
  }
}

run "private_dns_records_output" {
  command = plan

  variables {
    private_endpoints = {
      vault = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.vaultcore.azure.net"
        name                = "privatelink.vaultcore.azure.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        record_sets = [{
          name         = "kv-test-001"
          fqdn         = "kv-test-001.privatelink.vaultcore.azure.net"
          type         = "A"
          ip_addresses = ["10.0.0.5"]
          ttl          = 10
        }]
      }]
    }
  }

  assert {
    condition = (
      length(output.private_dns_records) == 1 &&
      output.private_dns_records[0].resource == "kv-test-001" &&
      output.private_dns_records[0].subresource == "vault" &&
      output.private_dns_records[0].zone_name == "privatelink.vaultcore.azure.net" &&
      output.private_dns_records[0].name == "kv-test-001" &&
      output.private_dns_records[0].fqdn == "kv-test-001.privatelink.vaultcore.azure.net" &&
      output.private_dns_records[0].type == "A" &&
      output.private_dns_records[0].ip_addresses == tolist(["10.0.0.5"]) &&
      output.private_dns_records[0].ttl == 10
    )
    error_message = "private_dns_records should list the vault's A record: ${jsonencode(output.private_dns_records)}"
  }
}

run "policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      vault = {
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
        name                = "privatelink.vaultcore.azure.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        record_sets = [{
          name         = "kv-test-001"
          fqdn         = "kv-test-001.privatelink.vaultcore.azure.net"
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
    condition     = azurerm_private_endpoint.this_unmanaged_dns_zone_group["vault"].name == "pep-kv-test-001" && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group["vault"].private_dns_zone_group) == 0
    error_message = "The endpoint should keep its name and get no zone group from this module."
  }

  assert {
    condition     = output.private_endpoints["vault"] != null && length(output.private_dns_records) == 1 && output.private_dns_records[0].zone_name == "privatelink.vaultcore.azure.net"
    error_message = "Outputs should include policy-managed endpoints and the records the policy registered: ${jsonencode(output.private_dns_records)}"
  }
}

run "diagnostics_default_categories" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_log) == 1 && one(azurerm_monitor_diagnostic_setting.this[0].enabled_log).category_group == "allLogs"
    error_message = "Logs should default to the allLogs category group."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.this[0].enabled_metric : m.category]) == toset(["AllMetrics"])
    error_message = "Metrics should default to AllMetrics."
  }
}

run "diagnostics_custom_categories" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = ["AuditEvent", "AzurePolicyEvaluationDetails"]
      metric_categories          = ["AllMetrics"]
    }
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.this[0].enabled_log : l.category]) == toset(["AuditEvent", "AzurePolicyEvaluationDetails"]) && alltrue([for l in azurerm_monitor_diagnostic_setting.this[0].enabled_log : l.category_group == null])
    error_message = "Exactly the requested log categories should be enabled, with no category group."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.this[0].enabled_metric : m.category]) == toset(["AllMetrics"])
    error_message = "Exactly the requested metric categories should be enabled."
  }
}

run "diagnostics_metrics_off" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      metric_categories          = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_metric) == 0 && length(azurerm_monitor_diagnostic_setting.this[0].enabled_log) == 1
    error_message = "Logs should stay enabled while metrics are off."
  }
}

run "diagnostics_logs_off" {
  command = plan

  variables {
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this[0].enabled_log) == 0 && length(azurerm_monitor_diagnostic_setting.this[0].enabled_metric) == 1
    error_message = "Metrics should stay enabled while logs are off."
  }
}
