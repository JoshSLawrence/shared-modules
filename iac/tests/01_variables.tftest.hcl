mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      id    = "1234567"
      login = "JoshSLawrence"
    }
  }

  mock_resource "github_repository" {
    defaults = {
      repo_id = 7654321
    }
  }
}

# iac/terraform.tfvars holds the live values and is loaded automatically by
# tofu test, so pin every variable here: tests must not depend on (or change
# with) the real configuration.
variables {
  github_owner          = "JoshSLawrence"
  repository_name       = "shared-modules"
  ruleset_enforcement   = "active"
  azure_client_id       = null
  azure_tenant_id       = null
  azure_subscription_id = null
  iac_azure_client_id   = null
  iac_azure_tenant_id   = null
}

run "no_client_id_disables_integration_variables" {
  command = plan

  assert {
    condition     = length(github_actions_variable.azure) == 0
    error_message = "No AZURE_* variables should be created while azure_client_id is null."
  }

  assert {
    condition     = github_repository_ruleset.main.enforcement == "active"
    error_message = "ruleset_enforcement should be passed through to the rulesets."
  }
}

run "azure_ids_create_all_variables" {
  command = plan

  variables {
    azure_client_id       = "00000000-0000-0000-0000-000000000001"
    azure_tenant_id       = "00000000-0000-0000-0000-000000000002"
    azure_subscription_id = "00000000-0000-0000-0000-000000000003"
  }

  assert {
    condition     = toset(keys(github_actions_variable.azure)) == toset(["AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID"])
    error_message = "Setting the Azure IDs should create all three AZURE_* variables."
  }
}

run "federated_subject_uses_immutable_format" {
  command = plan

  assert {
    condition     = output.azure_federated_credential_subject == "repo:JoshSLawrence@1234567/shared-modules@7654321:environment:integration"
    error_message = "Unexpected federated credential subject: ${output.azure_federated_credential_subject}"
  }
}

run "iac_ids_create_iac_variables_only" {
  command = plan

  variables {
    iac_azure_client_id = "00000000-0000-0000-0000-000000000004"
    iac_azure_tenant_id = "00000000-0000-0000-0000-000000000002"
  }

  assert {
    condition     = toset(keys(github_actions_variable.azure)) == toset(["IAC_AZURE_CLIENT_ID", "IAC_AZURE_TENANT_ID"])
    error_message = "Setting only the iac Azure IDs should create just the two IAC_* variables."
  }
}

run "iac_federated_subjects_use_immutable_format" {
  command = plan

  assert {
    condition = output.iac_federated_credential_subjects == {
      plan  = "repo:JoshSLawrence@1234567/shared-modules@7654321:environment:iac-plan"
      apply = "repo:JoshSLawrence@1234567/shared-modules@7654321:environment:iac-apply"
    }
    error_message = "Unexpected iac federated credential subjects: ${jsonencode(output.iac_federated_credential_subjects)}"
  }
}

run "iac_apply_requires_approval" {
  command = plan

  assert {
    condition     = length(github_repository_environment.iac_apply.reviewers) == 1 && !github_repository_environment.iac_apply.can_admins_bypass
    error_message = "iac-apply must require a reviewer's approval, with no admin bypass."
  }
}

run "iac_client_id_requires_tenant_id" {
  command = plan

  variables {
    iac_azure_client_id = "00000000-0000-0000-0000-000000000004"
    iac_azure_tenant_id = null
  }

  expect_failures = [var.iac_azure_tenant_id]
}

run "iac_client_id_must_be_guid" {
  command = plan

  variables {
    iac_azure_client_id = "not-a-guid"
  }

  expect_failures = [var.iac_azure_client_id]
}

run "client_id_requires_tenant_id" {
  command = plan

  variables {
    azure_client_id       = "00000000-0000-0000-0000-000000000001"
    azure_tenant_id       = null
    azure_subscription_id = "00000000-0000-0000-0000-000000000003"
  }

  expect_failures = [var.azure_tenant_id]
}

run "client_id_requires_subscription_id" {
  command = plan

  variables {
    azure_client_id       = "00000000-0000-0000-0000-000000000001"
    azure_tenant_id       = "00000000-0000-0000-0000-000000000002"
    azure_subscription_id = null
  }

  expect_failures = [var.azure_subscription_id]
}

run "client_id_must_be_guid" {
  command = plan

  variables {
    azure_client_id = "not-a-guid"
  }

  expect_failures = [var.azure_client_id]
}

run "enforcement_must_be_active_or_disabled" {
  command = plan

  variables {
    ruleset_enforcement = "evaluate"
  }

  expect_failures = [var.ruleset_enforcement]
}

run "repository_name_is_validated" {
  command = plan

  variables {
    repository_name = "has spaces"
  }

  expect_failures = [var.repository_name]
}

run "fork_pr_approval_defaults_to_all_external_contributors" {
  command = plan

  assert {
    condition     = var.fork_pr_approval_policy == "all_external_contributors"
    error_message = "Fork PR workflows should need approval for every external contributor by default."
  }
}

run "fork_pr_approval_policy_is_validated" {
  command = plan

  variables {
    fork_pr_approval_policy = "nobody"
  }

  expect_failures = [var.fork_pr_approval_policy]
}
