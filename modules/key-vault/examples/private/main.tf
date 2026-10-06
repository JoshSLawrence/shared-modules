# A private-only Key Vault: no public endpoint, reachable through a private
# endpoint (with a static IP) in an existing subnet, registered in an existing
# privatelink.vaultcore.azure.net zone.

data "azurerm_client_config" "current" {}

data "azurerm_subnet" "this" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.network_resource_group_name
}

# Key Vault names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-kv-example-${random_string.suffix.result}"
  location = var.location
}

module "key_vault" {
  source = "../.."

  name                = "kv-example-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  private_endpoints = {
    vault = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.vault.id]
      private_ip_address   = cidrhost(data.azurerm_subnet.this.address_prefixes[0], 5)
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  role_assignments = {
    deployer_secrets_officer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  lock = {
    kind = "CanNotDelete"
  }

  tags = {
    purpose = "key-vault module example"
  }
}
