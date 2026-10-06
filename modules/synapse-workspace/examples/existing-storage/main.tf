# Composes released key-vault and storage-account modules with this one: a
# data lake account (bronze/silver/gold plus the workspace's file system)
# created separately and passed to the workspace as existing storage, with
# the SQL administrator password stored in Key Vault.
#
# The workspace and vault are public (open to every network, still behind
# Entra ID auth), so OpenTofu can reach their data planes from anywhere:
# Synapse RBAC, the managed private endpoint and the Key Vault secret all
# need that. The data lake stays private: Synapse reaches it through a
# managed private endpoint, once that endpoint is approved on the storage
# account (Networking > Private endpoint connections).

data "azurerm_client_config" "current" {}

# Names are globally unique
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-synw-existing-${random_string.suffix.result}"
  location = var.location
}

module "key_vault" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/key-vault?ref=key-vault/v0.0.1"

  name                          = "kv-synw-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  public_network_access_enabled = true

  role_assignments = {
    deployer_secrets_officer = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    # Lets Synapse linked services read secrets as the workspace identity
    synapse_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.synapse_workspace.identity_principal_id
      principal_type             = "ServicePrincipal"
    }
  }
}

module "data_lake" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/v0.0.1"

  name                = "stlake${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  is_hns_enabled      = true

  # Synapse doesn't support versioning or soft delete on its default storage
  blob_properties = {
    delete_retention_days           = 0
    container_delete_retention_days = 0
  }

  containers = {
    bronze  = {}
    silver  = {}
    gold    = {}
    synapse = {}
  }
}

module "synapse_workspace" {
  source = "../.."

  name                = "synw-existing-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  existing_storage = {
    data_lake_filesystem_id = module.data_lake.containers["synapse"].data_lake_filesystem_id
    storage_account_id      = module.data_lake.id
  }
  storage_managed_private_endpoints = ["dfs"]

  public_network_access_enabled = true

  sql_administrator_password_secret = {
    key_vault_id = module.key_vault.id
  }

  synapse_role_assignments = {
    admins = {
      role_name      = "Synapse Administrator"
      principal_id   = var.synapse_admin_group_object_id
      principal_type = "Group"
    }
  }

  tags = {
    purpose = "synapse-workspace module example"
  }
}
