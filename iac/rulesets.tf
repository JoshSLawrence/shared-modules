locals {
  # App ID of the built-in GitHub Actions app: required status checks must
  # come from a workflow, not from anyone who can post a commit status.
  github_actions_app_id = 15368

  # Built-in repository role IDs used by ruleset bypass actors
  repository_role_admin = 5
}

# Everything reaches main through a pull request that passes PR validation.
# No bypass actors: to push directly (e.g. to recover from a broken main),
# temporarily set ruleset_enforcement = "disabled" and apply, which leaves an
# audit trail in this repo's history.
resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true

    pull_request {
      # Zero approvals: this is a single-maintainer repo, and GitHub never
      # lets an author approve their own PR. Raise this once there are other
      # maintainers.
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    required_status_checks {
      # Require PR branches to be up to date with main, so the VERSION checks
      # never pass against a stale main (two PRs bumping a module to the same
      # version would otherwise both pass and both merge).
      strict_required_status_checks_policy = true

      required_check {
        context        = "Validation Result"
        integration_id = local.github_actions_app_id
      }
    }
  }
}

# Release tags (<module>/vX.Y.Z) are immutable once created: consumers pin to
# them, so moving or deleting one silently changes or breaks their builds.
#
# Tag *creation* isn't restricted: the release workflow creates tags with the
# workflow's GITHUB_TOKEN, and GitHub doesn't allow the built-in Actions app as
# a bypass actor on a user-owned repository. Restricting creation would need a
# dedicated GitHub App for the release workflow to authenticate as.
#
# Admins can bypass, so a broken release can still be deleted as described in
# the PR template's rollback plan.
resource "github_repository_ruleset" "release_tags" {
  name        = "release-tags"
  repository  = github_repository.this.name
  target      = "tag"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = ["refs/tags/*/v*"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = local.repository_role_admin
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    update           = true
    deletion         = true
    non_fast_forward = true
  }
}
