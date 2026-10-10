# Synapse records the collaboration branch's latest commit in
# github_repo.last_commit_id as people work in Synapse Studio, so the module
# ignores later changes to it. These runs apply once, then plan against that
# state.
#
# The plans skip refresh: on OpenTofu 1.9.0-1.9.2 (fixed in 1.9.3; 1.9 is the
# floor this module is tested on), a mock refresh drops the stored
# last_commit_id, which would hide what ignore_changes does.

mock_provider "azurerm" {
  # No identity defaults (unlike 01_): on OpenTofu 1.9.0-1.9.2 (fixed in
  # 1.9.3) a mock refresh rejects them, and this file's second apply and
  # destroy both refresh.
  mock_resource "azurerm_synapse_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Synapse/workspaces/synw-test"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stsynwtest"
      primary_dfs_endpoint = "https://stsynwtest.dfs.core.windows.net/"
    }
  }
}

mock_provider "random" {}

variables {
  name                = "synw-test"
  resource_group_name = "rg-test"
  location            = "eastus"
  storage_account = {
    name = "stsynwtest"
  }
  github_repo = {
    account_name    = "contoso"
    repository_name = "analytics"
    branch_name     = "main"
    root_folder     = "/synapse"
  }
}

# Stands in for a workspace whose Studio has recorded a commit
run "create_with_recorded_commit" {
  command = apply

  variables {
    github_repo = {
      account_name    = "contoso"
      repository_name = "analytics"
      branch_name     = "main"
      root_folder     = "/synapse"
      last_commit_id  = "0123456789abcdef0123456789abcdef01234567"
    }
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].last_commit_id == "0123456789abcdef0123456789abcdef01234567"
    error_message = "last_commit_id should seed the recorded commit when Git integration is first configured."
  }
}

run "recorded_commit_is_not_reset" {
  command = plan

  plan_options {
    refresh = false
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].last_commit_id == "0123456789abcdef0123456789abcdef01234567"
    error_message = "The module should keep the commit Synapse recorded, not plan last_commit_id back to null."
  }
}

run "other_git_settings_still_update" {
  command = plan

  plan_options {
    refresh = false
  }

  variables {
    github_repo = {
      account_name    = "contoso"
      repository_name = "analytics"
      branch_name     = "release"
      root_folder     = "/synapse"
    }
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].branch_name == "release" && azurerm_synapse_workspace.this.github_repo[0].last_commit_id == "0123456789abcdef0123456789abcdef01234567"
    error_message = "Only last_commit_id should be ignored: a branch change should still plan."
  }
}

run "git_integration_can_still_be_removed" {
  command = plan

  plan_options {
    refresh = false
  }

  variables {
    github_repo = null
  }

  assert {
    condition     = length(azurerm_synapse_workspace.this.github_repo) == 0
    error_message = "Removing github_repo should still plan Git integration off."
  }
}

# A workspace without Git integration has no github_repo block to ignore, so
# adding it later plans the whole block. This apply updates the workspace
# from the one above.
run "apply_without_git_integration" {
  command = apply

  variables {
    github_repo = null
  }

  assert {
    condition     = length(azurerm_synapse_workspace.this.github_repo) == 0
    error_message = "The workspace should have no Git integration before it is added."
  }
}

run "git_integration_added_with_seed" {
  command = plan

  plan_options {
    refresh = false
  }

  variables {
    github_repo = {
      account_name    = "contoso"
      repository_name = "analytics"
      branch_name     = "main"
      root_folder     = "/synapse"
      last_commit_id  = "0123456789abcdef0123456789abcdef01234567"
    }
  }

  assert {
    condition     = length(azurerm_synapse_workspace.this.github_repo) == 1
    error_message = "Adding Git integration after creation should plan the github_repo block."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].repository_name == "analytics" && azurerm_synapse_workspace.this.github_repo[0].last_commit_id == "0123456789abcdef0123456789abcdef01234567"
    error_message = "Adding Git integration after creation should plan the full block, including the seed."
  }
}

run "git_integration_added_without_seed" {
  command = plan

  plan_options {
    refresh = false
  }

  assert {
    condition     = length(azurerm_synapse_workspace.this.github_repo) == 1
    error_message = "Adding Git integration after creation should plan the github_repo block."
  }

  assert {
    condition     = azurerm_synapse_workspace.this.github_repo[0].repository_name == "analytics" && azurerm_synapse_workspace.this.github_repo[0].last_commit_id == null
    error_message = "Adding Git integration after creation without a seed should plan last_commit_id as null."
  }
}
