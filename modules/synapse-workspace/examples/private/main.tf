# A fully private Synapse workspace with its own private ADLS Gen2 default
# storage: no public endpoints, reachable through private endpoints (with
# static IPs) in an existing subnet, registered in existing privatelink DNS
# zones.
#
# Everything here is managed through Azure Resource Manager, so it can be
# applied without network access to the workspace. Features that use the
# workspace's data plane need line of sight to the Dev private endpoint (or a
# public workspace, as in the existing-storage example),
# including storage_managed_private_endpoints = ["dfs"], which Spark and
# serverless SQL need to reach this private storage account.

data "azurerm_subnet" "this" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_private_dns_zone" "this" {
  for_each = {
    blob        = "privatelink.blob.core.windows.net"
    dfs         = "privatelink.dfs.core.windows.net"
    synapse_dev = "privatelink.dev.azuresynapse.net"
    synapse_sql = "privatelink.sql.azuresynapse.net"
  }

  name                = each.value
  resource_group_name = var.network_resource_group_name
}

# Workspace and storage account names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  subnet_prefix = data.azurerm_subnet.this.address_prefixes[0]
}

resource "azurerm_resource_group" "this" {
  name     = "rg-synw-example-${random_string.suffix.result}"
  location = var.location
}

module "synapse_workspace" {
  source = "../.."

  name                = "synw-example-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  storage_account = {
    name = "stsynwexample${random_string.suffix.result}"
    private_endpoints = {
      blob = {
        subnet_id            = data.azurerm_subnet.this.id
        private_dns_zone_ids = [data.azurerm_private_dns_zone.this["blob"].id]
        private_ip_address   = cidrhost(local.subnet_prefix, 4)
      }
      dfs = {
        subnet_id            = data.azurerm_subnet.this.id
        private_dns_zone_ids = [data.azurerm_private_dns_zone.this["dfs"].id]
        private_ip_address   = cidrhost(local.subnet_prefix, 5)
      }
    }
  }

  private_endpoints = {
    Dev = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["synapse_dev"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 6)
    }
    Sql = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["synapse_sql"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 7)
    }
    SqlOnDemand = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["synapse_sql"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 8)
    }
  }

  entra_admin = {
    login     = var.sql_admin_group.display_name
    object_id = var.sql_admin_group.object_id
  }

  spark_pools = {
    synspmedium = {
      node_size = "Medium"
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  tags = {
    purpose = "synapse-workspace module example"
  }
}
