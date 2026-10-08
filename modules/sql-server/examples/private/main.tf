# A private-only SQL server: no public endpoint, reachable through a private
# endpoint (with a static IP) in an existing subnet, registered in an existing
# privatelink.database.windows.net zone. Audit events and the database's logs
# and metrics go to an existing Log Analytics workspace.

data "azurerm_subnet" "this" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.network_resource_group_name
}

# SQL server names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-sql-example-${random_string.suffix.result}"
  location = var.location
}

module "sql_server" {
  source = "../.."

  name                = "sql-example-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  entra_admin = {
    login     = var.entra_admin_login
    object_id = var.entra_admin_object_id
  }

  databases = {
    app = {
      sku_name    = "S0"
      max_size_gb = 10
    }
  }

  private_endpoints = {
    sqlServer = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.sql.id]
      private_ip_address   = cidrhost(data.azurerm_subnet.this.address_prefixes[0], 5)
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  auditing_enabled = true

  lock = {
    kind = "CanNotDelete"
  }

  tags = {
    purpose = "sql-server module example"
  }
}
