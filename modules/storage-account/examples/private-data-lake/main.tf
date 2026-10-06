# A private-only ADLS Gen2 account with bronze/silver/gold file systems: no
# public endpoint, reachable through blob and dfs private endpoints (with
# static IPs) in an existing subnet, registered in existing privatelink DNS
# zones.

data "azurerm_client_config" "current" {}

data "azurerm_subnet" "this" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_private_dns_zone" "this" {
  for_each = {
    blob = "privatelink.blob.core.windows.net"
    dfs  = "privatelink.dfs.core.windows.net"
  }

  name                = each.value
  resource_group_name = var.network_resource_group_name
}

# Storage account names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-st-example-${random_string.suffix.result}"
  location = var.location
}

module "storage_account" {
  source = "../.."

  name                = "stexample${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  is_hns_enabled      = true

  containers = {
    bronze = {}
    silver = {}
    gold   = {}
  }

  private_endpoints = {
    blob = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["blob"].id]
      private_ip_address   = cidrhost(data.azurerm_subnet.this.address_prefixes[0], 6)
    }
    dfs = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["dfs"].id]
      private_ip_address   = cidrhost(data.azurerm_subnet.this.address_prefixes[0], 7)
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  role_assignments = {
    deployer_blob_contributor = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  lock = {
    kind = "CanNotDelete"
  }

  tags = {
    purpose = "storage-account module example"
  }
}
