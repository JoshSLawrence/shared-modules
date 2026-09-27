terraform {
  # This root module isn't bound by the shared-module OpenTofu floor -- it's
  # applied with the version pinned in iac/mise.toml. The constraint stays at
  # the floor only because the repo-wide pre-commit hooks validate iac/ with
  # the repo-root tools.
  required_version = ">= 1.9.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}
