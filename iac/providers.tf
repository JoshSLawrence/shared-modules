# Authenticates with GITHUB_TOKEN if set, otherwise falls back to the GitHub
# CLI (`gh auth token`). The token needs admin rights on the repository --
# see README.md.
provider "github" {
  owner = var.github_owner
}
