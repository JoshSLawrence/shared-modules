# AGENTS.md

Instructions for agents working in this repository.

## What this repo is

A collection of version-controlled **shared modules** for OpenTofu (not
Terraform). Each directory under `modules/` is a shared module that can be
sourced independently via git reference with per-module semantic versioning.

See README.md for full terminology and architecture overview.

## Key concepts

- **Shared module**: A reusable OpenTofu module under `modules/<name>/` with
  its own VERSION file and git tag namespace (`<name>/vX.Y.Z`)
- **Root module**: Top-level module that configures providers and backend
  (e.g., `iac/`)
- **Child module**: Local-only module under a shared module's `modules/` dir

Shared modules never configure their own provider or backend. That belongs in
`examples/` or the caller's root module.

## Repository structure

```
shared-modules/
├── .github/                    # CI/CD workflows and scripts
├── cookiecutter/               # Submodule: JoshSLawrence/cookiecutter (module template)
├── iac/                        # Root module that manages this repo on GitHub
├── mise-tasks/                 # Repo task scripts (mise run <task>)
├── modules/                    # All shared modules live here
│   ├── <module-name>/
│   │   ├── examples/           # Working examples (configure provider/backend)
│   │   ├── modules/            # Child modules (local to this module)
│   │   ├── scripts/            # Scripts for local-exec provisioners
│   │   ├── tests/              # OpenTofu tests (*.tftest.hcl)
│   │   ├── .header.md          # Source for terraform-docs
│   │   ├── CHANGELOG.md
│   │   ├── README.md           # Generated - don't edit directly
│   │   ├── VERSION             # e.g., v0.0.1
│   │   ├── outputs.tf
│   │   ├── terraform.tf        # required_providers/version only
│   │   └── variables.tf
│   └── ...
```

## Essential conventions

- **OpenTofu, not Terraform.** Use `tofu` in commands/scripts/docs. Follow
  HashiCorp's Terraform style guide for code style (substitute `tofu` for
  `terraform`).
- **Scaffold new modules via `mise run new-module`** (uses cookiecutter).
  Never hand-copy. The template lives in the `cookiecutter/` submodule
  (JoshSLawrence/cookiecutter, `templates/shared-module`). Don't edit it in
  place here: change it upstream, then bump the submodule pin.
- **Generated files stay generated.** Module READMEs are built by
  terraform-docs from `.header.md` + `.tf` files. Edit the source, then
  regenerate.
- **Azure resource naming.** Use CAF abbreviations (e.g., `kv-` for Key Vault,
  `st` for Storage Account) in all examples and module-generated names.
  Reference: <https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations>
- **OpenTofu floor is 1.9.0.** Modules target the floor (pinned in
  `mise.toml`, `>= floor` in `terraform.tf`). Never use features newer than
  the floor or bump it without user approval (it's a breaking change).
- **Cross-variable validation is supported** (OpenTofu 1.9+). Use it for
  constraints like mutual exclusivity. Gotcha: validating two variables
  against each other causes a cycle; put the validation in only one.
- **Tool versions pinned in `mise.toml`** at repo root and per-module. In CI,
  modules see only their own `mise.toml` (`MISE_CEILING_PATHS`), so every
  required tool must be pinned there.
- **Every shared module must have a working example** under `examples/` that
  calls the module via HTTPS git reference (or `source = "../.."` for local
  dev).
- **Scripts over inline provisioners.** Prefer `scripts/<name>.sh` over
  inline `local-exec` command strings.
- **Tests live in `tests/`.** Use numeric prefixes: `01_`–`89_` for unit
  tests (mock providers, fast, run locally), `90_`–`99_` for integration
  tests (real infra, slow, CI only). Never run integration tests without
  explicit user permission.

## Validation

- Run `mise run hooks` (or `pre-commit run -a`) before finishing work.
- If tflint/trivy/shellcheck fail, surface the issue. Never auto-add
  suppressions; prefer fixing the root cause.
- If the user approves a suppression, add a comment explaining why.

## Security

- Never commit secrets (keys, passwords, connection strings). `*.tfvars` is
  gitignored; never force-add them. Exception: `iac/terraform.tfvars` (only
  non-secret IDs).
- Mark sensitive variables/outputs `sensitive = true`.
- Default to least privilege (IAM, network, permissions).

## Workflows

- PR validation runs checks + unit tests per changed module (matrix).
  Integration tests run separately after all checks pass (if Azure OIDC
  configured).
- Release workflow tags/releases modules when their VERSION file changes on
  `main`.
- Repo settings managed in `iac/` (rulesets, environments, etc.). Changes
  applied from PR branch before merge, rolled back by applying `main`. Never
  `tofu apply` in `iac/` without explicit user approval.
- The iac workflow (`iac.yaml`) plans `iac/` on PRs, comments the plan, and
  applies it after approval in the `iac-apply` environment. The plan
  job's GitHub token must stay read-only (no approval gate), its Azure
  identity is only for the state, and `iac/` state must never hold secrets
  (plan artifacts are public).

## Need more detail?

- CONTRIBUTING.md — how to add/change modules, tooling, versioning
- README.md — terminology, layout, design decisions
- `.github/scripts/common.sh` — logging/utility functions for scripts
