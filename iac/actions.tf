# Least privilege by default: workflows get a read-only GITHUB_TOKEN unless a
# job asks for more (the release job asks for contents: write), and can never
# approve pull requests.
resource "github_workflow_repository_permissions" "this" {
  repository                       = github_repository.this.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Only GitHub-owned actions and an explicit allow-list may run, and every
# action must be pinned to a full commit SHA. Adding a new third-party action
# to a workflow therefore also needs a change here -- deliberately, so it gets
# reviewed.
resource "github_actions_repository_permissions" "this" {
  repository           = github_repository.this.name
  enabled              = true
  allowed_actions      = "selected"
  sha_pinning_required = true

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed = [
      "jdx/mise-action@*",
    ]
  }
}

# Read by the workflows, which skip the jobs that need Azure until these are
# set: pr-validation.yaml's integration job needs AZURE_CLIENT_ID, and
# iac.yaml needs IAC_AZURE_CLIENT_ID. Repository-level (not
# environment-level) because a job's `if:` is evaluated before its
# environment's variables are loaded.
locals {
  azure_variables = merge(
    var.azure_client_id == null ? {} : {
      AZURE_CLIENT_ID       = var.azure_client_id
      AZURE_TENANT_ID       = var.azure_tenant_id
      AZURE_SUBSCRIPTION_ID = var.azure_subscription_id
    },
    var.iac_azure_client_id == null ? {} : {
      IAC_AZURE_CLIENT_ID = var.iac_azure_client_id
      IAC_AZURE_TENANT_ID = var.iac_azure_tenant_id
    },
  )
}

resource "github_actions_variable" "azure" {
  for_each = local.azure_variables

  repository    = github_repository.this.name
  variable_name = each.key
  value         = each.value
}

# Workflows on pull requests from forks wait for a maintainer's approval
# before they run. GitHub's default only asks for first-time contributors,
# which anyone can get past by landing a trivial change first, so require it
# for every external contributor.
#
# The GitHub provider has no resource for this setting, so a script applies
# it whenever the policy changes. OpenTofu can't read the setting back:
# changing it in the UI isn't detected as drift. To re-assert it, run
# `tofu apply -replace=terraform_data.fork_pr_approval`.
resource "terraform_data" "fork_pr_approval" {
  triggers_replace = [github_repository.this.full_name, var.fork_pr_approval_policy]

  provisioner "local-exec" {
    command = "${path.module}/scripts/set-fork-pr-approval.sh"
    environment = {
      REPOSITORY      = github_repository.this.full_name
      APPROVAL_POLICY = var.fork_pr_approval_policy
    }
  }
}
