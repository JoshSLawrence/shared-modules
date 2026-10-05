# A private Data Factory wired to a private data lake and Key Vault, the
# way the data platform root modules compose these modules:
#
# - The factory, data lake and vault have no public endpoints; private
#   endpoints (with static IPs) in an existing subnet serve ADF Studio,
#   the factory API, the data lake and the vault.
# - Pipelines run on an integration runtime in the factory's managed virtual
#   network and reach the data lake and vault through managed private
#   endpoints (approve them on each target's private endpoint connections).
# - The factory's managed identity gets data access through RBAC.
#
# Everything here is managed through Azure Resource Manager, so it can be
# applied without network access to the factory, lake or vault.

data "azurerm_subnet" "this" {
  name                 = var.subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.network_resource_group_name
}

data "azurerm_private_dns_zone" "this" {
  for_each = {
    adf_api    = "privatelink.datafactory.azure.net"
    adf_portal = "privatelink.adf.azure.com"
    dfs        = "privatelink.dfs.core.windows.net"
    vault      = "privatelink.vaultcore.azure.net"
  }

  name                = each.value
  resource_group_name = var.network_resource_group_name
}

# Names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  subnet_prefix = data.azurerm_subnet.this.address_prefixes[0]
}

resource "azurerm_resource_group" "this" {
  name     = "rg-adf-example-${random_string.suffix.result}"
  location = var.location
}

module "data_factory" {
  source = "../.."

  name                = "adf-example-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  managed_integration_runtime = {}

  managed_private_endpoints = {
    data-lake-dfs = {
      target_resource_id = module.data_lake.id
      subresource_name   = "dfs"
    }
    key-vault = {
      target_resource_id = module.key_vault.id
      subresource_name   = "vault"
    }
  }

  private_endpoints = {
    dataFactory = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["adf_api"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 4)
    }
    portal = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["adf_portal"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 5)
    }
  }

  diagnostic_settings = {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  tags = {
    purpose = "data-factory module example"
  }
}

module "data_lake" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/v0.0.1"

  name                = "stadfexample${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  is_hns_enabled      = true

  containers = {
    bronze = {}
    silver = {}
    gold   = {}
  }

  private_endpoints = {
    dfs = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["dfs"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 6)
    }
  }

  role_assignments = {
    adf_blob_contributor = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.data_factory.identity_principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}

module "key_vault" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/key-vault?ref=key-vault/v0.0.1"

  name                = "kv-adf-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  private_endpoints = {
    vault = {
      subnet_id            = data.azurerm_subnet.this.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.this["vault"].id]
      private_ip_address   = cidrhost(local.subnet_prefix, 7)
    }
  }

  role_assignments = {
    adf_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.data_factory.identity_principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}
