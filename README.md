# Shared Modules

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-%3E%3D1.9.0-844fba?logo=opentofu)](https://opentofu.org)
[![PR Validation](https://github.com/JoshSLawrence/shared-modules/actions/workflows/pr-validation.yaml/badge.svg)](https://github.com/JoshSLawrence/shared-modules/actions/workflows/pr-validation.yaml)
[![IaC](https://github.com/JoshSLawrence/shared-modules/actions/workflows/iac.yaml/badge.svg)](https://github.com/JoshSLawrence/shared-modules/actions/workflows/iac.yaml)

This repository is a collection of version-controlled **shared modules** for
[OpenTofu](https://opentofu.org). It exists so that common infrastructure
patterns can be written once, reviewed once, and reused across many
OpenTofu configurations instead of being copy-pasted between repos.

> **OpenTofu, not Terraform.** Modules in this repo are written for and
> tested against OpenTofu. While OpenTofu is a fork of Terraform and much of
> its syntax overlaps, we make **no guarantee of cross-compatibility** with
> HashiCorp Terraform. Provider behavior, state handling, and CLI features
> can diverge between the two projects over time. Do not assume a module
> here will work unmodified under `terraform`.

## Terminology

These terms are used throughout this repo and its documentation. They
describe a module's *role in a given context*, not a fixed property of the
module itself — the same module can be a shared module in one context and a
root module in another (see the note below).

- **Root module** — the top-level OpenTofu configuration that you actually run (`tofu plan` / `tofu apply`), i.e. the directory containing your root `.tf` files, backend config, and providers. A root module houses the configuration for a specific piece of infrastructure and typically composes one or more child and/or shared modules together.

- **Child module** — a module that lives inside a root module, usually under that root module's own `modules/` directory. Child modules are local, not independently version-controlled, and exist to provide minor abstractions or reduce duplication within a single root module. They are not intended to be reused outside of the root module they belong to.

- **Shared module** — a module that lives in a separate, version-controlled repository (like this one) and is pulled into a root or child module by source reference (e.g. a Git URL with a `ref`/tag). Shared modules are the unit of reuse across repos and teams, and changes to them are versioned so consumers can upgrade deliberately.

Note: when you are developing a shared module in this repo, treat that module as a root module for the purposes of local development and testing (write examples, run `tofu plan`, etc., directly against it). A shared module can also have its own child modules under its own `modules/` directory.

A shared module's child modules are private to it: never reach into another shared module's `modules/` directory to reuse a child module directly. If the same logic is needed by two or more shared modules, promote it to its own shared module instead, and call a released version of it (see [Calling another shared module](./CONTRIBUTING.md#calling-another-shared-module)).

## Repository Layout

Every shared module lives in its own directory under `modules/`, alongside the tooling that supports developing and maintaining every module in this repo (sorted lexically — dotfiles first, then everything else alphabetically):

```text
shared-modules/
├── .github/                 # GitHub repo config
│   ├── CODEOWNERS           # requests the maintainer's review on every PR
│   ├── dependabot.yml       # keeps the SHA-pinned workflow actions and the cookiecutter submodule up to date
│   ├── pull_request_template.md
│   ├── scripts/             # shell scripts called by workflows (common.sh, etc.)
│   └── workflows/           # CI/CD workflows (PR validation, release, iac)
├── .gitignore
├── .gitmodules
├── .pre-commit-config.yaml
├── AGENTS.md                # symlink to CLAUDE.md
├── CLAUDE.md                # rules for agents (and humans) working in this repo
├── CONTRIBUTING.md
├── cookiecutter/            # git submodule: JoshSLawrence/cookiecutter, home of the shared-module template
├── iac/                     # root module that configures this repo on GitHub (rulesets, environments, ...)
├── mise-tasks/              # mise task scripts (our make/Makefile replacement)
├── mise.toml
├── modules/                 # every shared module lives here — see the layout below
│   ├── <module1>/
│   └── <module2>/
└── README.md
```

Everything a consumer might pull as a module lives under `modules/` — nothing
else at the repo root (`cookiecutter/`, `mise-tasks/`, etc.) is ever a valid
module source, by construction rather than by convention. `iac/` is a root
module, but it's never consumed or released: it's what configures this
repository itself on GitHub (see [iac/README.md](./iac/README.md)).

A typical module directory (`modules/<module-name>/`) looks like (sorted lexically — dotfiles first, then everything else alphabetically):

```text
<module-name>/
├── .header.md              # markdown injected at the top of the terraform-docs-generated README
├── .terraform-docs.yaml    # terraform-docs config
├── .tflint.hcl             # tflint config
├── CHANGELOG.md            # version history and upgrade notes (linked from README)
├── examples/               # usage examples for callers
├── mise.toml               # mise version constraints for this module
├── modules/                # this module's own child modules (not to be confused with the repo-root modules/ folder)
├── outputs.tf              # all outputs from the module
├── README.md               # generated by terraform-docs from .header.md + the .tf files — don't hand-edit
├── scripts/                # scripts supporting this module (e.g. invoked via local-exec)
├── terraform.tf            # providers and OpenTofu version constraints
├── tests/                  # OpenTofu test files (*.tftest.hcl) for validation logic
├── trivy.yaml              # trivy config
├── variables.tf            # all required inputs
├── VERSION                 # current module version (e.g. v0.0.1) — updated in PRs, triggers the release workflow
└── *.tf                    # additional module logic, split across as many files as needed
```

## Repository Tooling

This repo standardizes on a few tools so that every shared module is developed and validated the same way:

- **[mise](https://mise.jdx.dev)** — manages tool versions (OpenTofu, etc.) and runs repo tasks. Task scripts live in `mise-tasks/`; run `mise tasks` to list them and `mise run <task>` to execute one. Think of it as our Makefile replacement. Each module also has its own `mise.toml` pinning the tool versions it needs.
- **[pre-commit](https://pre-commit.com)** — runs formatting/linting/validation hooks (see `.pre-commit-config.yaml`) before a commit is allowed. Run `pre-commit install` once after cloning so the hooks run automatically. To run hooks manually against all files: `pre-commit run -a` (or `mise run hooks`).
- **[cookiecutter](https://cookiecutter.readthedocs.io)** — scaffolds new shared modules so every one starts with the same layout and boilerplate described above. The template lives in [JoshSLawrence/cookiecutter](https://github.com/JoshSLawrence/cookiecutter), included here as the `cookiecutter/` git submodule. To create a new module: `mise run new-module` (see [Scaffolding a new module](./CONTRIBUTING.md#scaffolding-a-new-module-with-cookiecutter)).
- **[tflint](https://github.com/terraform-linters/tflint)** — lints each module against its own `.tflint.hcl` config.
- **[trivy](https://trivy.dev)** — scans each module for misconfigurations/vulnerabilities using its own `trivy.yaml` config.
- **[terraform-docs](https://terraform-docs.io)** — generates each module's `README.md` from its `.tf` files, using `.terraform-docs.yaml` for config and `.header.md` as the injected preamble. Don't hand-edit a module's generated `README.md`; edit `.header.md` and the `.tf` files instead, then regenerate.
- **[shellcheck](https://www.shellcheck.net) / [actionlint](https://github.com/rhysd/actionlint)** — lint the repo's shell scripts and GitHub Actions workflows. Both run as pre-commit hooks and in PR validation's **Repo Checks** job.

## Using a Shared Module

Reference a module from this repo by Git source, pointing at the module's
subdirectory under `modules/` with `//` and pinning `ref` to a module-scoped
release tag (see
[Versioning and Releases](./CONTRIBUTING.md#versioning-and-releases)) rather
than a branch:

Over HTTPS (preferred):

```hcl
module "example" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/<module-name>?ref=<module-name>/vX.Y.Z"

  # module inputs...
}
```

Over SSH:

```hcl
module "example" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/<module-name>?ref=<module-name>/vX.Y.Z"

  # module inputs...
}
```

If the repository is private, your machine (or pipeline) must already be
authenticated to GitHub — an SSH key for the SSH form, or a credential
helper/token for the HTTPS form (e.g. `gh auth setup-git`). In GitHub
Actions, the default `GITHUB_TOKEN` can only read the repo the workflow runs
in, so a consuming repo needs a token or GitHub App with read access to this
one.

Every release also gets a [GitHub
Release](https://github.com/JoshSLawrence/shared-modules/releases) named
after its tag (`<module-name>/vX.Y.Z`), with that version's `CHANGELOG.md`
entry as release notes — a quick way to browse what's available.

Always pin `ref` to a released tag rather than a branch. Floating on a
branch means your root module's behavior can change without you touching
anything, and it makes drift very hard to reason about.

## Resource Naming

We recommend following the [Azure Cloud Adoption Framework resource abbreviations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) when naming Azure resources. This provides a consistent, recognizable naming pattern across your infrastructure.

Common abbreviations used in these modules:

| Resource | Abbreviation | Example |
|----------|--------------|---------|
| Key Vault | `kv` | `kv-myapp-prod` |
| App Configuration | `appcs` | `appcs-myapp-prod` |
| App Service Plan | `asp` | `asp-myapp-prod` |
| Storage Account | `st` | `stmyappprod` |
| Log Analytics Workspace | `log` | `log-myapp-prod` |
| Resource Group | `rg` | `rg-myapp-prod` |
| Virtual Network | `vnet` | `vnet-hub-prod` |
| Subnet | `snet` | `snet-private-endpoints` |
| Private Endpoint | `pep` | `pep-kv-myapp-prod` |

Modules accept resource names as input variables, so you're free to use your own naming convention. However, module examples and any names generated internally by a module follow the CAF abbreviations.

## Getting Started

1. Install [OpenTofu](https://opentofu.org/docs/intro/install/).
1. Browse the module you need and read its own `README.md` for required inputs, outputs, and provider requirements.
1. Reference it from your root module as shown above, pinning a version.
1. Run `tofu init`, `tofu plan`, and `tofu apply` from your root module.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to add or change a shared
module, our versioning/tagging expectations, and testing guidelines.
