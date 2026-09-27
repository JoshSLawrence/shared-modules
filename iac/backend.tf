# State lives in Azure Storage and is accessed with your Entra ID login
# (az login) rather than storage account keys. These are resource names and
# IDs, not secrets.
terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    subscription_id      = "232d899f-6a30-492c-8956-d03aaa050656"
    resource_group_name  = "rg-github"
    storage_account_name = "stdeveus2kz81ks"
    container_name       = "tfstate"
    key                  = "repos.shared-modules.tfstate"
  }
}
