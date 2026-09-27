#!/usr/bin/env bash
#
# Applies the saved iac/ plan made by iac-plan.sh, for the iac workflow's
# apply job. It applies exactly that plan -- the one posted on the PR and
# approved -- never a fresh one: OpenTofu refuses it if the state changed
# since it was made, and iac-apply-preflight.sh has already checked the code
# didn't.
#
# Environment variables:
#   WORKING_DIR  - root module to apply (default: iac)
#   PLAN_DIR     - directory holding tfplan (default: $RUNNER_TEMP/iac-plan)
#   PLAN_SHA256  - expected digest of tfplan, from the plan job (required in
#                  CI)
#   GITHUB_TOKEN - credential for the GitHub provider and the scripts it runs.
#                  Required in CI; locally the provider falls back to
#                  `gh auth token`.
#   ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID - state backend auth in CI
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ensure_mise

export WORKING_DIR="${WORKING_DIR:-iac}"
PLAN_DIR="${PLAN_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/iac-plan}"
PLAN_FILE="$PLAN_DIR/tfplan"
# Only iac/mise.toml counts, not the repo-root one (see iac-check.sh)
export MISE_CEILING_PATHS
MISE_CEILING_PATHS="$(pwd -P)"

if is_github_actions; then
  require_env GITHUB_TOKEN "Set the IAC_GITHUB_TOKEN secret in the iac-apply environment -- see 'Enabling the iac workflow' in iac/README.md."
  require_env PLAN_SHA256 "It should come from the plan job's plan-sha256 output; check the workflow wiring."
fi

log_config WORKING_DIR PLAN_FILE PLAN_SHA256

if [ ! -f "$PLAN_FILE" ]; then
  log_error "No plan file at ${PLAN_FILE}. Plan artifacts expire after 7 days; re-run the whole workflow to plan again."
  exit 1
fi

if [ -n "${PLAN_SHA256:-}" ]; then
  actual_sha256="$(file_sha256 "$PLAN_FILE")"
  if [ "$actual_sha256" != "$PLAN_SHA256" ]; then
    log_error "tfplan's sha256 is ${actual_sha256}, but the plan job produced ${PLAN_SHA256}. Refusing to apply a plan that isn't the one that was reviewed; re-run the whole workflow."
    exit 1
  fi
  log_success "tfplan matches the reviewed plan (sha256 ${PLAN_SHA256})"
fi

cd_working_dir
require_mise_tool opentofu

log_step "tofu init"
log_cmd tofu init -input=false -lockfile=readonly
if ! mise exec -- tofu init -input=false -lockfile=readonly; then
  log_error "tofu init failed. If it can't reach the state, check the iac workflow's Azure identity (IAC_AZURE_CLIENT_ID) has a federated credential for the iac-apply environment and Storage Blob Data Contributor on the state container (see iac/README.md)."
  exit 1
fi

# A saved plan applies without prompting. The lock timeout rides out a
# concurrent local plan/apply briefly holding the state lock.
log_step "tofu apply"
APPLY_LOG="$(mktemp)"
trap 'rm -f "$APPLY_LOG"' EXIT
log_cmd tofu apply -input=false -lock-timeout=5m "$PLAN_FILE"
set +e
mise exec -- tofu apply -input=false -lock-timeout=5m "$PLAN_FILE" 2>&1 | tee "$APPLY_LOG"
apply_exit=${PIPESTATUS[0]}
set -e

if [ "$apply_exit" -ne 0 ]; then
  if grep -q "Saved plan is stale" "$APPLY_LOG"; then
    log_error "The state changed after this plan was made (another apply ran), so OpenTofu refused it. Nothing was applied. Re-run the whole workflow to plan against the current state."
  else
    log_error "tofu apply failed (exit $apply_exit); some changes may already be applied. Fix the error above and push to plan again, or roll back by running the iac workflow on main (see iac/README.md)."
  fi
  exit "$apply_exit"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "### ✅ Applied the reviewed plan (sha256 \`${PLAN_SHA256:-unknown}\`)" >> "$GITHUB_STEP_SUMMARY"
fi
log_summary "Applied iac/"
