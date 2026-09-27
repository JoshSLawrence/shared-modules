# Integration tests provision real Azure resources, so each run waits for a
# reviewer's approval. This is also what scopes the Azure credential: the
# federated credential trusts only jobs in this environment (see the
# azure_federated_credential_subject output), so a PR that edits the workflow
# to request an Azure token from some other job gets nothing, and one that
# uses this environment still needs approval first.
resource "github_repository_environment" "integration" {
  environment = "integration"
  repository  = github_repository.this.name

  reviewers {
    users = [data.github_user.owner.id]
  }

  # The reviewer is also the PR author on a single-maintainer repo, so self
  # review must be allowed. Admins go through the same approval as everyone.
  prevent_self_review = false
  can_admins_bypass   = false

  # No deployment_branch_policy: PR jobs run on refs/pull/<n>/merge, which a
  # "protected branches only" policy would reject. The approval above is the
  # gate, and PRs from forks never get an OIDC token anyway.
}

# The iac workflow (.github/workflows/iac.yaml) plans this root module in
# iac-plan and applies it in iac-apply. Each environment holds its own
# IAC_GITHUB_TOKEN secret (set by hand -- see README.md), and the Azure
# identity for the state trusts only these two environments (see the
# iac_federated_credential_subjects output).
#
# Planning is read-only and runs on every push to a PR, so it needs no
# approval -- which is why its GitHub token must only be able to read the
# repository settings.
resource "github_repository_environment" "iac_plan" {
  environment = "iac-plan"
  repository  = github_repository.this.name

  # No deployment_branch_policy, for the same reason as integration above.
}

# Applying changes the live repository settings, so every apply waits for a
# reviewer to approve the plan posted on the PR. Its token has write access.
resource "github_repository_environment" "iac_apply" {
  environment = "iac-apply"
  repository  = github_repository.this.name

  reviewers {
    users = [data.github_user.owner.id]
  }

  # Same reasoning as integration above: single maintainer, and admins get
  # no shortcut past the approval.
  prevent_self_review = false
  can_admins_bypass   = false

  # No deployment_branch_policy, for the same reason as integration above.
  # The workflow only applies PR merge refs and main.
}
