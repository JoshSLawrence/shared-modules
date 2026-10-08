# Contributing

Thanks for contributing to this shared module repository. Please read this
before opening a PR — it covers the terminology, tooling, and expectations
specific to how modules here are developed and versioned.

## Terminology

If you're new to this repo, start with the **Terminology** section in the [README](./README.md). In short:

- **Root module** — the top-level config you actually run (`tofu plan` / `tofu apply`).
- **Child module** — a local module inside a root module's own `modules/` directory, used only by that root module.
- **Shared module** — a version-controlled, remotely-sourced module (like the ones in this repo) that gets pulled into a root or child module.

While working in this repo, treat the shared module you're editing as a root module for local development purposes: write/update its `examples/` directory as a root config, and run `tofu` commands directly against it to validate your changes. A shared module may itself contain child modules under its own `modules/` directory — those follow the same rules as child modules anywhere else (local-only, not independently versioned).

A shared module's child modules are private to it: never reach into another shared module's `modules/` directory to reuse a child module directly. If the same logic is needed by two or more shared modules, promote it to its own shared module instead (see step 4 below).

## OpenTofu, not Terraform

This repo targets [OpenTofu](https://opentofu.org) exclusively. Use the `tofu` CLI for all local development, testing, and examples.

- Do not add Terraform-specific workarounds or assume Terraform behavior.
- We provide **no guarantee of cross-compatibility with Terraform**. If a module happens to work under `terraform`, that's incidental, not a supported outcome. Do not write code or docs implying otherwise.
- Version constraints in `terraform.tf` should reference OpenTofu-compatible provider versions and, where relevant, an OpenTofu `required_version` constraint rather than a Terraform one.
- For code style (naming, formatting, file layout, comments, etc.), follow [HashiCorp's Terraform style guide](https://developer.hashicorp.com/terraform/language/style) — it's the closest authoritative style reference available, and OpenTofu's language is currently a close mirror of Terraform's. Mentally substitute `tofu` for `terraform` as you read it; it does not imply any guarantee of Terraform compatibility beyond shared style conventions.

### OpenTofu version floor

Shared modules support the oldest OpenTofu version we reasonably can, so
consumers aren't forced to upgrade to use them. That version — the
**floor** — is currently **1.9.0**:

- Each module's `mise.toml` pins `opentofu` to the floor, so CI proves the
  module really works on it, and its `terraform.tf` declares
  `required_version = ">= <floor>"`. The repo-root `mise.toml` pins the
  same version so local hooks match CI, and is the source of truth:
  `mise run new-module` passes it to the cookiecutter template as the
  default.
- 1.9 is the oldest release supporting what this repo relies on: provider
  mocking in `tofu test` (`mock_provider`, 1.8+) and validation conditions
  that reference other variables (1.9+).
- Don't bump a module's OpenTofu pin as routine maintenance. Raise the floor
  only when a module needs a newer language feature — and since that drops
  support for consumers on older versions, it's a **major** version bump
  for that module.
- Other tools (tflint, trivy, terraform-docs, ...) and providers should stay
  current. Providers already do: modules use `>=` constraints and commit no
  lock file, so CI always tests against the latest provider releases.
- The floor applies to shared modules only. Root modules in this repo (e.g.
  `iac/`) aren't consumed by anyone, so they can use a current OpenTofu.

## Tooling

Before you start, install the repo's standard tooling — see the **Repository Tooling** section in the [README](./README.md#repository-tooling) for details:

- **mise** — install it, then run `mise install` to pin the correct OpenTofu (and other tool) versions for this repo. Prefer `mise run <task>` over ad hoc shell commands for anything that already has a task defined in `mise-tasks/`; add a new task there if a common workflow is missing one.
- **pre-commit** — run `pre-commit install` once after cloning. Do not bypass hooks with `--no-verify`; fix what they flag instead.
- **cookiecutter** — scaffold new shared modules from the `shared-module` template rather than hand-rolling the directory structure (see below).

### Scaffolding a new module with cookiecutter

The module template isn't maintained here. It lives in
[JoshSLawrence/cookiecutter](https://github.com/JoshSLawrence/cookiecutter)
(`templates/shared-module`), which this repo includes as a git submodule at
`cookiecutter/`. Pinning the submodule means every contributor, and CI's
template check, scaffolds from the same template commit.

Run this from the root of your clone:

```bash
mise run new-module
```

It initializes the submodule if needed, then runs
`cookiecutter cookiecutter/templates/shared-module -o modules` with the
repo's OpenTofu floor as the default `opentofu_version`. Cookiecutter
prompts for the module name, description, and which providers the module
uses (azurerm, azapi, azuread, random), then creates
`modules/<module-slug>/` with the standard layout. Provider and tool
versions are hardcoded in the template. See its
[README](https://github.com/JoshSLawrence/cookiecutter/blob/main/templates/shared-module/README.md)
for every input.

To pick up template changes, bump the submodule in a PR. PR validation's
template check renders the new template and runs the module checks against
it. Dependabot also opens a weekly PR when the submodule is behind.

```bash
git submodule update --remote cookiecutter
git add cookiecutter
```

## Adding or Changing a Shared Module

1. For a new module, scaffold it with cookiecutter (see [Scaffolding a new module](#scaffolding-a-new-module-with-cookiecutter) above) rather than copying an existing module by hand, so it starts with the standard layout. For a change, work within the existing module's directory.
1. Document the module by editing its `.header.md` (and `.terraform-docs.yaml` config, if needed) and regenerating `README.md` with `terraform-docs` (run `mise exec -- terraform-docs .` from within the module, or let the repo's `terraform_docs` pre-commit hook do it) — don't hand-edit a generated `README.md` directly, since your changes will be overwritten.
1. Add or update an `examples/` directory with a minimal root configuration that exercises the module end-to-end. Call the module itself with `source = "../.."` and any other shared module by pinned release tag, and add a test that plans each example (e.g. `tests/03_examples.tftest.hcl`).
1. If the module needs internal abstractions, put them in a child module under that module's `modules/` directory — don't reuse another shared module's child module directly. If logic needs to be reused across shared modules, it should be promoted to its own shared module instead.
1. Put any supporting scripts (e.g. ones invoked via `local-exec`) in that module's `scripts/` directory rather than inlining them in `.tf` files.
1. To build on another shared module from this repo, call a released version of it — see [Calling another shared module](#calling-another-shared-module).
1. Run the repo's `pre-commit` hooks against the module and its examples before opening a PR (`pre-commit run -a`, or let them run on commit) — this covers `tofu fmt`/`tofu validate`, `tflint` (per the module's `.tflint.hcl`), `trivy` (per its `trivy.yaml`), and `terraform-docs`. See [Validating changes](./CLAUDE.md#validation) in CLAUDE.md for what to do if a hook fails.

### Calling another shared module

A shared module (or an example) can call another shared module from this
repo, e.g. `synapse-workspace` creates its default storage with
`storage-account`. Always pin the call to a released, module-scoped tag,
exactly as an outside consumer would:

```hcl
module "storage_account" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/v0.0.1"
}
```

Never use a relative path (`../storage-account`) or a child module of
another shared module. Pinning means a change to the called module can't
affect the caller until the caller deliberately bumps its `ref`, so each
module is validated and released on its own:

- The called module's version must be released before a PR can use it.
  Ship the dependency in its own PR first, wait for the release workflow
  to tag it, then open the PR that consumes it. Until the tag exists,
  `tofu init` (and so validation) fails for the consumer.
- Upgrading a dependency is a change to the caller: bump the `ref` and the
  caller's own `VERSION`, and note it in its `CHANGELOG.md`.

The one exception is an example calling *its own* module, which uses
`source = "../.."` so the example (and the test that plans it) exercises
the code in the PR rather than the last release.

## Versioning and Releases

- Shared modules are consumed by pinned `ref` (tag or commit), not by branch. Consumers rely on tags to control when they pick up changes.
- Since this repo is a monorepo of independently versioned modules, tags are **module-scoped**: `<module-name>/vX.Y.Z` (e.g. `azure-shared-services/v1.2.0`), not a bare `vX.Y.Z`. A bare tag doesn't identify which module it releases.
- Follow semantic versioning for module tags: breaking changes to inputs, outputs, or resource behavior are a major version bump.

### Releasing a Module

Each module has a `VERSION` file and a `CHANGELOG.md` at its root. To release a new version:

1. **Update `CHANGELOG.md`** — add an entry for the new version with a summary of changes (Added, Changed, Fixed, Removed, etc.). Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with a `## [vX.Y.Z] - YYYY-MM-DD` heading matching the new VERSION — the release workflow uses that section as the GitHub Release notes.
2. **Update the `VERSION` file** with the new version (e.g. `v1.2.0`).
3. **Merge the PR** to `main`.
4. **The release workflow** (`.github/workflows/release.yaml`) automatically detects the VERSION change, creates a git tag (`<module>/v1.2.0`), and publishes a matching GitHub Release using that version's `CHANGELOG.md` section as release notes.

The PR validation workflow checks that:

- Every module with `.tf` or `scripts/` changes (including child modules' `scripts/`) also bumped its `VERSION`
- The version format is valid (`vX.Y.Z`)
- The tag doesn't already exist
- The new version is greater than the one currently on `main`
- `CHANGELOG.md` has a non-empty `## [vX.Y.Z]` section for the new version

Example VERSION file:

```text
v1.0.0
```

> **Note:** Don't create tags or releases manually. Let the release workflow
> handle it to ensure consistency.

## Workflows

CI/CD runs on GitHub Actions. Workflow definitions live in
`.github/workflows/`, and the logic they run lives in shell scripts under
`.github/scripts/`:

- **`ci.yaml`** — runs on every push to `main` (i.e. after a merge) and
  is what the README's **CI** badge shows (filtered to `main` pushes), so
  the badge reflects only the health of `main`, never a pull request. It
  runs **Repo Checks** and a **Validate** leg for *every* module (not just
  changed ones: a merge can break a module it didn't touch) with fmt,
  validate, tflint, trivy, terraform-docs drift, and unit tests. It never
  runs integration tests, the VERSION checks, or PR comments, and has no
  cloud credentials. It's not required for merging; it exists to tell you
  if `main` went red.
- **`pr-validation.yaml`** — runs on every PR to `main`:
  - **Detect Changes** finds every module with *any* changed file under
    `modules/<name>/` (`.tf`, tests, examples, lint/scan config, docs, ...)
    and runs the VERSION checks above. Only changes that alter what
    consumers get — `.tf` files and `scripts/` (the module's own or a child
    module's) — require a `VERSION` bump; e.g. a tests-, examples-, or
    docs-only change is validated but doesn't force a new release.
  - **Repo Checks** always runs: `shellcheck`, `actionlint`, and
    `trailing-whitespace` over the whole repo (via the pre-commit hooks), plus
    rendering the cookiecutter template from the `cookiecutter/` submodule
    and running the module checks against the result, and running the same
    checks (plus its tests) on `iac/` — so changes to `.github/`,
    `mise-tasks/`, the `cookiecutter/` submodule pin, or `iac/` are
    validated too.
  - **Validate** runs once per changed module, in parallel, with fmt,
    validate, tflint, trivy, terraform-docs drift, and unit tests. It uses
    only the tool versions pinned in that module's own `mise.toml` (the
    repo-root one isn't inherited), and a check whose tool isn't pinned
    fails rather than being skipped.
  - **Integration** runs integration tests for each changed module that has
    them, once every Validate job has passed — see
    [Integration Tests](#integration-tests).
  - **Validation Result** rolls everything up into one stable check.
- **`release.yaml`** — runs on pushes to `main` that touch a
  `modules/*/VERSION` file. It checks *every* module's `VERSION` against
  the existing tags and, for any that's missing, creates the tag on the
  commit that last changed that `VERSION` file, plus a GitHub Release. That
  makes it safe to re-run, and you can trigger it manually (Actions →
  Release → Run workflow) to recover from a failed or skipped release.
- **`iac.yaml`** — runs on PRs that touch `iac/` (or the workflow and its
  scripts). **Plan** plans the PR merged into `main` and posts the plan as
  a PR comment; **Apply** applies exactly that plan once you approve the
  `iac-apply` environment, then updates the comment. Run it manually on
  `main` to re-apply `main`, e.g. to roll back. It's skipped until it's set
  up — see [Making a change](./iac/README.md#making-a-change) and
  [Enabling the iac workflow](./iac/README.md#enabling-the-iac-workflow).

When adding or changing a workflow:

1. **Keep the YAML thin.** Put logic in a script under `.github/scripts/`
   (sourcing `common.sh`) rather than in inline `run:` blocks, so it can be
   linted with `shellcheck` and run locally to debug — the scripts fall back
   to sensible defaults outside Actions (e.g. diffing against `origin/main`).
2. **Pin third-party actions to a full commit SHA** with the version in a
   trailing comment (`uses: owner/action@<sha> # vX.Y.Z`). Dependabot
   (`.github/dependabot.yml`) opens PRs to keep those pins current.
3. **Grant least-privilege `permissions:`** per workflow/job. CI is
   read-only throughout, and PR validation is read-only apart from
   `id-token: write` on the Integration job for Azure OIDC; the iac jobs
   add `id-token: write` (state access) and `pull-requests: write` (the
   plan comment); only the release job gets `contents: write`.
4. **New third-party actions must be allow-listed** in
   `iac/actions.tf` (and pinned to a SHA), or GitHub refuses to run them.
5. **Set `timeout-minutes` on every job** so a hung step doesn't burn the
   6-hour default.

### Repository Setup

The GitHub repository itself — settings, rulesets, environments, Actions
permissions, and variables — is managed as code by the root module in
[`iac/`](./iac/README.md). Change settings there in a PR, approve the
iac workflow's apply of the PR, and merge once it applied cleanly — roll
back by applying `main` and closing the PR (see
[Making a change](./iac/README.md#making-a-change)). Don't click settings in
the UI, or the next apply will revert them. It sets up, among other
things:

- **A `main` ruleset** requiring a pull request (squash merge only) and the
  **Validation Result** check — not the per-module `Validate (...)` /
  `Integration (...)` jobs, whose names depend on which modules changed
  and which are skipped when none did. It also requires branches to be
  **up to date** before merging: the VERSION checks only compare a PR
  against `main` as it was when they ran, so two PRs could otherwise both
  bump a module to the same new version, both pass, and both merge cleanly,
  leaving the second PR's changes unreleased. (If you ever switch to a merge
  queue instead, add a `merge_group` trigger to `pr-validation.yaml`.)
- **A release tag ruleset** making `<module>/v*` tags immutable (no moving
  or deleting them), with only repository admins able to bypass it.
  Creating tags isn't restricted, because the release workflow creates
  them with its `GITHUB_TOKEN`, and GitHub doesn't accept the built-in
  Actions app as a bypass actor on a personal repository. Locking down tag
  creation would mean having the release workflow authenticate as a
  dedicated GitHub App instead.
- **A read-only default `GITHUB_TOKEN`** (jobs request more explicitly),
  and only GitHub-owned plus explicitly allow-listed actions, all pinned to
  a full commit SHA. Adding a new third-party action therefore also needs
  an `iac/` change.
- **Approval before fork PR workflows run** for every external
  contributor, not just first-timers (GitHub's default, which can be gamed
  by landing a trivial change first).

These settings assume a single maintainer. Before giving anyone else write
access, work through
[Before adding a collaborator](./iac/README.md#before-adding-a-collaborator).

### Integration Tests

Unit tests (`tests/01_`–`89_`) run on every PR with no credentials. Integration
tests (`tests/90_`–`99_`) create real Azure resources, so PR validation only
runs them (in the separate **Integration** job, the only job that can
request an Azure token) when Azure OIDC is configured and every **Validate**
job has passed. If Azure OIDC isn't configured, they're skipped, and
**Validation Result** shows a warning. Each integration run also waits for
approval in the `integration` environment before it starts. To enable them:

1. Create an Entra ID app registration (or user-assigned managed identity)
   for CI and grant it only the roles the integration tests need, ideally
   scoped to a dedicated test subscription or resource group.
2. Add a federated credential to it: issuer
   `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`, and the subject printed by
   `tofu output azure_federated_credential_subject` in `iac/`. It has the
   form `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:integration`:
   GitHub's immutable subject format, which embeds IDs so the credential
   can't be reused by a future repository that takes the same name.
3. Set `azure_client_id`, `azure_tenant_id`, and `azure_subscription_id` in
   `iac/terraform.tfvars` (identifiers, not secrets) and apply `iac/`. That
   creates the `AZURE_*` repository variables the workflow checks for.

Because the credential trusts only the `integration` environment, and that
environment needs your approval, a PR can't get an Azure token without
review — even one that edits the workflow to request a token from another
job. PRs from forks never get an OIDC token, so they always run unit tests
only.

A new push never cancels an integration run that's already in progress —
the newer run waits for it — because cancelling mid-test would skip the
`tofu test` teardown and leave real resources behind. A run can still be
interrupted by a manual cancel or by the job's 90-minute timeout, so name
or tag test resources recognisably and periodically clean up anything left
over in the test subscription.

## Reviewing External Pull Requests

Contributors without write access open PRs from their own forks. They
can't merge, can't create tags, and their workflow runs get a read-only
token with no secrets and no Azure access. What they *can* do is change
what CI checks, so review accordingly:

- **Approve workflow runs only after reading the diff.** Every external PR
  waits for "Approve workflows to run". Look especially at `.github/`,
  `mise-tasks/`, `iac/`, and module `tests/` before clicking it.
- **A green check proves little if the PR touches CI.** A PR runs its own
  copy of the workflows and scripts, so changes under `.github/` or
  `mise-tasks/` can make **Validation Result** pass regardless of the code.
  For such PRs, your review is the check.
- **Integration tests don't run for forks** (no OIDC token), so
  **Validation Result** shows a warning instead. To run them, push the
  reviewed branch into this repo yourself (e.g.
  `gh pr checkout <n> && git push origin HEAD:refs/heads/pr-<n>`) and open a
  PR from it; its integration run then waits for your approval in the
  `integration` environment.
- **Never apply `iac/` from a contributor's branch.** The iac workflow
  doesn't run for forks; push a reviewed copy to a branch in this repo and
  open a PR from it (see
  [Making a change](./iac/README.md#making-a-change)).
- **Check VERSION/CHANGELOG** as for any module change: the release is cut
  from what you merge.

## Pull Requests

- The [PR template](./.github/pull_request_template.md) is auto-populated when you create a PR — complete its checklist covering VERSION, CHANGELOG, examples, and validation.
- Keep PRs scoped to a single module where possible.
- Describe what changed and, if applicable, whether it's a breaking change requiring a major version bump.
- Ensure the relevant `pre-commit` hooks pass, and that examples plan cleanly with `tofu`, before requesting review. Never suppress a `tflint`/`trivy` finding to force a hook to pass — see [Validating changes](./CLAUDE.md#validation) in CLAUDE.md.
