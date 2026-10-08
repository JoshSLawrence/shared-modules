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
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001/databases/db-mock"    }
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

run "defaults_are_private_and_entra_only" {
  command = plan

  assert {
    condition     = azurerm_mssql_server.this.public_network_access_enabled == false && azurerm_mssql_server.this.minimum_tls_version == "1.2" && azurerm_mssql_server.this.outbound_network_restriction_enabled == false
    error_message = "The server should be private, require TLS 1.2 and not restrict outbound by default."
  }

  assert {
    condition     = azurerm_mssql_server.this.version == "12.0"
    error_message = "The server should use version 12.0."
  }

  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].tenant_id == "00000000-0000-0000-0000-000000000001"
    error_message = "entra_admin.tenant_id should default to the current client's tenant."
  }

  assert {
    condition     = length(azurerm_mssql_database.this) == 0 && length(azurerm_private_endpoint.this) == 0 && length(azurerm_management_lock.this) == 0 && length(azurerm_role_assignment.this) == 0
    error_message = "No optional resources should be created by default."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.audit) == 0 && length(azurerm_mssql_server_extended_auditing_policy.this) == 0 && length(azurerm_monitor_diagnostic_setting.database) == 0
    error_message = "No auditing or diagnostics should be created by default."
  }
}

run "entra_only_is_always_set" {
  command = plan

  variables {
    public_network_access_enabled        = true
    outbound_network_restriction_enabled = true
    entra_admin = {
      login     = "sg-sql-admins"
      object_id = "00000000-0000-0000-0000-000000000010"
      tenant_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].azuread_authentication_only == true
    error_message = "Entra ID authentication only should always be on."
  }

  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].login_username == "sg-sql-admins" && azurerm_mssql_server.this.azuread_administrator[0].object_id == "00000000-0000-0000-0000-000000000010" && azurerm_mssql_server.this.azuread_administrator[0].tenant_id == "11111111-1111-1111-1111-111111111111"
    error_message = "The Entra administrator and an explicit tenant_id should be passed through."
  }

  assert {
    condition     = azurerm_mssql_server.this.public_network_access_enabled == true && azurerm_mssql_server.this.outbound_network_restriction_enabled == true
    error_message = "Public access and outbound restriction should follow their variables."
  }
}

run "serverless_database" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name                    = "GP_S_Gen5_2"
        auto_pause_delay_in_minutes = 60
        min_capacity                = 0.5
      }
    }
  }

  assert {
    condition     = azurerm_mssql_database.this["app"].sku_name == "GP_S_Gen5_2" && azurerm_mssql_database.this["app"].auto_pause_delay_in_minutes == 60 && azurerm_mssql_database.this["app"].min_capacity == 0.5
    error_message = "A serverless database should get its auto-pause delay and minimum capacity."
  }
}

run "serverless_never_pause" {
  command = plan

  variables {
    databases = {
      app = {
        sku_name                    = "GP_S_Gen5_2"
        auto_pause_delay_in_minutes = -1
      }
    }
  }

  assert {
    condition     = azurerm_mssql_database.this["app"].auto_pause_delay_in_minutes == -1
    error_message = "An auto-pause delay of -1 (never pause) should be accepted and passed through."
  }
}

run "databases_default_name_from_key" {
  command = plan

  variables {
    databases = {
      app = {}
      custom = {
        name                 = "sales"
        sku_name             = "GP_S_Gen5_2"
        max_size_gb          = 32
        storage_account_type = "Local"
        collation            = "Latin1_General_100_CI_AS_SC_UTF8"
        zone_redundant       = true
      }
    }
  }

  assert {
    condition     = azurerm_mssql_database.this["app"].name == "app" && azurerm_mssql_database.this["app"].sku_name == "S0"
    error_message = "A database should default its name to the key, with SKU S0."
  }

  assert {
    condition     = azurerm_mssql_database.this["app"].storage_account_type == "Geo" && azurerm_mssql_database.this["app"].collation == "SQL_Latin1_General_CP1_CI_AS" && azurerm_mssql_database.this["app"].zone_redundant == false
    error_message = "Database defaults for backup storage, collation and zone redundancy are wrong."
  }

  assert {
    condition     = azurerm_mssql_database.this["custom"].name == "sales" && azurerm_mssql_database.this["custom"].sku_name == "GP_S_Gen5_2" && azurerm_mssql_database.this["custom"].max_size_gb == 32 && azurerm_mssql_database.this["custom"].storage_account_type == "Local" && azurerm_mssql_database.this["custom"].collation == "Latin1_General_100_CI_AS_SC_UTF8" && azurerm_mssql_database.this["custom"].zone_redundant == true
    error_message = "Explicit database settings should be honored."
  }

  assert {
    condition     = azurerm_mssql_database.this["app"].server_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001"
    error_message = "Databases should be created on the server."
  }
}

run "private_endpoint_with_static_ip_and_dns" {
  command = plan

  variables {
    private_endpoints = {
      sqlServer = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"]
        private_ip_address   = "10.0.0.5"
      }
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this["sqlServer"].name == "pep-sql-test-001-sqlserver" && azurerm_private_endpoint.this["sqlServer"].custom_network_interface_name == "nic-pep-sql-test-001-sqlserver"
    error_message = "Private endpoint and NIC names should follow the pep-/nic-pep- CAF convention."
  }

  assert {
    condition     = azurerm_private_endpoint.this["sqlServer"].private_service_connection[0].subresource_names == tolist(["sqlServer"])
    error_message = "The private endpoint should target the sqlServer sub-resource."
  }

  assert {
    condition     = azurerm_private_endpoint.this["sqlServer"].ip_configuration[0].name == "ipconfig" && azurerm_private_endpoint.this["sqlServer"].ip_configuration[0].private_ip_address == "10.0.0.5" && azurerm_private_endpoint.this["sqlServer"].ip_configuration[0].subresource_name == "sqlServer" && azurerm_private_endpoint.this["sqlServer"].ip_configuration[0].member_name == "sqlServer"
    error_message = "A static IP should create an ip_configuration for the sqlServer member."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["sqlServer"].private_dns_zone_group) == 1
    error_message = "DNS zone IDs should create a private DNS zone group."
  }

  assert {
    condition     = azurerm_private_endpoint.this["sqlServer"].resource_group_name == "rg-test" && azurerm_private_endpoint.this["sqlServer"].location == "eastus"
    error_message = "The private endpoint should default to the server's resource group and location."
  }
}

run "private_endpoint_dynamic_ip_without_dns" {
  command = plan

  variables {
    private_endpoints = {
      sqlServer = {
        subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        name                   = "pep-custom"
        network_interface_name = "nic-custom"
        resource_group_name    = "rg-network"
      }
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.this["sqlServer"].ip_configuration) == 0 && length(azurerm_private_endpoint.this["sqlServer"].private_dns_zone_group) == 0
    error_message = "Without a static IP or DNS zones, no ip_configuration or DNS zone group should be set."
  }

  assert {
    condition     = azurerm_private_endpoint.this["sqlServer"].name == "pep-custom" && azurerm_private_endpoint.this["sqlServer"].custom_network_interface_name == "nic-custom" && azurerm_private_endpoint.this["sqlServer"].resource_group_name == "rg-network"
    error_message = "Name, NIC name and resource group overrides should be honored."
  }
}

run "policy_managed_dns" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
    private_endpoints = {
      sqlServer = {
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_ip_address = "10.0.0.9"
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this_unmanaged_dns_zone_group
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-policy"
        name                = "privatelink.database.windows.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
        record_sets = [{
          name         = "sql-test-001"
          fqdn         = "sql-test-001.privatelink.database.windows.net"
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
    condition     = azurerm_private_endpoint.this_unmanaged_dns_zone_group["sqlServer"].name == "pep-sql-test-001-sqlserver" && length(azurerm_private_endpoint.this_unmanaged_dns_zone_group["sqlServer"].private_dns_zone_group) == 0 && azurerm_private_endpoint.this_unmanaged_dns_zone_group["sqlServer"].ip_configuration[0].member_name == "sqlServer"
    error_message = "The endpoint should keep its name and static IP and get no zone group from this module."
  }

  assert {
    condition     = output.private_endpoints["sqlServer"] != null && length(output.private_dns_records) == 1 && output.private_dns_records[0].zone_name == "privatelink.database.windows.net"
    error_message = "Outputs should include policy-managed endpoints and the records the policy registered: ${jsonencode(output.private_dns_records)}"
  }
}

run "private_dns_records_output" {
  command = plan

  variables {
    private_endpoints = {
      sqlServer = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"]
      }
    }
  }

  override_resource {
    target = azurerm_private_endpoint.this
    values = {
      private_dns_zone_configs = [{
        id                  = "zonecfg-privatelink.database.windows.net"
        name                = "privatelink.database.windows.net"
        private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
        record_sets = [{
          name         = "sql-test-001"
          fqdn         = "sql-test-001.privatelink.database.windows.net"
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
      output.private_dns_records[0].resource == "sql-test-001" &&
      output.private_dns_records[0].subresource == "sqlServer" &&
      output.private_dns_records[0].zone_name == "privatelink.database.windows.net" &&
      output.private_dns_records[0].name == "sql-test-001" &&
      output.private_dns_records[0].fqdn == "sql-test-001.privatelink.database.windows.net" &&
      output.private_dns_records[0].type == "A" &&
      output.private_dns_records[0].ip_addresses == tolist(["10.0.0.5"]) &&
      output.private_dns_records[0].ttl == 10
    )
    error_message = "private_dns_records should list the server's A record: ${jsonencode(output.private_dns_records)}"
  }
}

run "outputs_expose_database_ids" {
  command = plan

  variables {
    databases = {
      app = {}
    }
  }

  assert {
    condition     = output.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001" && output.database_ids["app"] == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001/databases/db-mock"
    error_message = "id and database_ids (keyed like databases) should be exposed."
  }
}

run "lock_and_role_assignments" {
  command = plan

  variables {
    lock = {
      kind = "CanNotDelete"
    }
    role_assignments = {
      by_name = {
        role_definition_id_or_name = "SQL Server Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000003"
      }
      by_id = {
        role_definition_id_or_name = "/providers/Microsoft.Authorization/roleDefinitions/6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437"
        principal_id               = "00000000-0000-0000-0000-000000000004"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = azurerm_management_lock.this[0].lock_level == "CanNotDelete" && azurerm_management_lock.this[0].name == "lock-sql-test-001" && azurerm_management_lock.this[0].scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001"
    error_message = "The lock should use the requested level, a default lock-<name> name and the server scope."
  }

  assert {
    condition     = azurerm_role_assignment.this["by_name"].role_definition_name == "SQL Server Contributor" && azurerm_role_assignment.this["by_name"].scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001"
    error_message = "A role name should be passed as role_definition_name at the server scope."
  }

  assert {
    condition     = azurerm_role_assignment.this["by_id"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437"
    error_message = "A role definition ID should be passed as role_definition_id."
  }
}

run "diagnostics_alone_do_not_enable_auditing" {
  command = plan

  variables {
    databases = {
      app = {}
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.audit) == 0 && length(azurerm_mssql_server_extended_auditing_policy.this) == 0 && length(azurerm_monitor_diagnostic_setting.database) == 1
    error_message = "Without auditing_enabled, only database diagnostics should be created."
  }
}

run "diagnostics_create_auditing_and_database_settings" {
  command = plan

  variables {
    auditing_enabled = true
    databases = {
      app   = {}
      sales = {}
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
    }
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.audit[0].name == "diag-log-analytics" && azurerm_monitor_diagnostic_setting.audit[0].target_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test-001/databases/master"
    error_message = "Server auditing should use a diagnostic setting on the master database."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.audit[0].enabled_log) == 1 && one(azurerm_monitor_diagnostic_setting.audit[0].enabled_log).category == "SQLSecurityAuditEvents"
    error_message = "The master database setting should send SQLSecurityAuditEvents."
  }

  assert {
    condition     = azurerm_mssql_server_extended_auditing_policy.this[0].log_monitoring_enabled == true
    error_message = "The extended auditing policy should send audit events to Azure Monitor."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.database) == 2 && azurerm_monitor_diagnostic_setting.database["app"].name == "diag-log-analytics"
    error_message = "Each database should get a diagnostic setting."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.database["app"].enabled_log) == 1 && one(azurerm_monitor_diagnostic_setting.database["app"].enabled_log).category_group == "allLogs"
    error_message = "Database logs should default to the allLogs category group."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.database["app"].enabled_metric : m.category]) == toset(["Basic", "InstanceAndAppAdvanced", "WorkloadManagement"])
    error_message = "Database metrics should default to Basic, InstanceAndAppAdvanced and WorkloadManagement."
  }
}

run "diagnostics_without_databases_still_audit" {
  command = plan

  variables {
    auditing_enabled = true
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      name                       = "diag-custom"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.audit) == 1 && azurerm_monitor_diagnostic_setting.audit[0].name == "diag-custom" && length(azurerm_mssql_server_extended_auditing_policy.this) == 1 && length(azurerm_monitor_diagnostic_setting.database) == 0
    error_message = "Server auditing should be created with a custom name even when there are no databases."
  }
}

run "custom_categories" {
  command = plan

  variables {
    auditing_enabled = true
    databases = {
      app = {}
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = ["Errors", "Deadlocks"]
      metric_categories          = ["Basic"]
    }
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.database["app"].enabled_log : l.category]) == toset(["Errors", "Deadlocks"]) && alltrue([for l in azurerm_monitor_diagnostic_setting.database["app"].enabled_log : l.category_group == null])
    error_message = "Custom log_categories should replace the allLogs category group."
  }

  assert {
    condition     = toset([for m in azurerm_monitor_diagnostic_setting.database["app"].enabled_metric : m.category]) == toset(["Basic"])
    error_message = "Custom metric_categories should replace the default metric categories."
  }

  assert {
    condition     = one(azurerm_monitor_diagnostic_setting.audit[0].enabled_log).category == "SQLSecurityAuditEvents"
    error_message = "Custom categories should not affect server auditing."
  }
}

run "metrics_off" {
  command = plan

  variables {
    databases = {
      app = {}
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      metric_categories          = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.database["app"].enabled_metric) == 0 && length(azurerm_monitor_diagnostic_setting.database["app"].enabled_log) == 1
    error_message = "An empty metric_categories should send no metrics but keep the logs."
  }
}

run "logs_off" {
  command = plan

  variables {
    databases = {
      app = {}
    }
    diagnostic_settings = {
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.OperationalInsights/workspaces/log-test"
      log_categories             = []
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.database["app"].enabled_log) == 0 && length(azurerm_monitor_diagnostic_setting.database["app"].enabled_metric) == 3
    error_message = "An empty log_categories should send no logs but keep the default metrics."
  }
}
