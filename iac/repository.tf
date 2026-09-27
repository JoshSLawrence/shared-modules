data "github_user" "owner" {
  username = var.github_owner
}

resource "github_repository" "this" {
  name        = var.repository_name
  description = "Version-controlled, independently released OpenTofu shared modules."
  topics      = ["opentofu", "iac", "modules", "azure"]

  # Public: consumers can pull modules without Git credentials. It's also what
  # makes environment required reviewers available on a personal account.
  # Trivy's GIT-0001 flags every public repository; being public is the point
  # of this one (accepted exception, approved by the repo owner).
  #trivy:ignore:GIT-0001
  visibility = "public"

  # The history is pushed from an existing clone -- see README.md.
  auto_init = false

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  # Squash only: one commit per PR on main, which is what the release
  # workflow tags (it tags the first-parent commit that changed a VERSION).
  allow_squash_merge          = true
  allow_merge_commit          = false
  allow_rebase_merge          = false
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"
  allow_auto_merge            = true
  allow_update_branch         = true
  delete_branch_on_merge      = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  # Destroying this root module (or losing its state and re-applying) must
  # never delete the repository, its history, or its release tags.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

# Dependabot *security* updates: PRs for known-vulnerable dependencies. Routine
# version updates are configured separately in .github/.
resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}
