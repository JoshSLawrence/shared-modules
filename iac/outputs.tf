output "repository_url" {
  description = "URL of the repository."
  value       = github_repository.this.html_url
}

output "repository_ssh_clone_url" {
  description = "SSH clone URL, for `git remote add origin` when bootstrapping."
  value       = github_repository.this.ssh_clone_url
}

# Repositories created after 2026-07-15 use GitHub's immutable OIDC subject
# format, which embeds the owner and repository IDs so the subject can't be
# reused if the name is ever recycled.
output "azure_federated_credential_subject" {
  description = "Subject to set on the Azure federated credential for integration tests (issuer https://token.actions.githubusercontent.com, audience api://AzureADTokenExchange)."
  value = format(
    "repo:%s@%s/%s@%s:environment:%s",
    data.github_user.owner.login,
    data.github_user.owner.id,
    github_repository.this.name,
    github_repository.this.repo_id,
    github_repository_environment.integration.environment,
  )
}

output "iac_federated_credential_subjects" {
  description = "Subjects of the two federated credentials to add to the iac workflow's Azure identity, one per job's environment (same issuer and audience as azure_federated_credential_subject)."
  value = {
    for job, environment in {
      plan  = github_repository_environment.iac_plan.environment
      apply = github_repository_environment.iac_apply.environment
    } :
    job => format(
      "repo:%s@%s/%s@%s:environment:%s",
      data.github_user.owner.login,
      data.github_user.owner.id,
      github_repository.this.name,
      github_repository.this.repo_id,
      environment,
    )
  }
}
