#!/usr/bin/env bash
#
# Plans iac/ to a saved plan file for the iac workflow's apply job, and
# renders the plan summary the workflow posts on the PR. Never changes
# anything, so it's safe to run locally (with `az login` and `gh auth login`
# as described in iac/README.md).
#
# Environment variables:
#   WORKING_DIR  - root module to plan (default: iac)
#   PLAN_DIR     - where to write tfplan and summary.md (default:
#                  $RUNNER_TEMP/iac-plan). The workflow uploads this
#                  directory as the plan artifact, so nothing else goes in it.
#   GITHUB_TOKEN - credential for the GitHub provider. Required in CI; locally
#                  the provider falls back to `gh auth token`.
#   ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID - state backend auth in CI
#
# Outputs:
#   has-changes - true if the plan changes anything (needs an apply)
#   plan-sha256 - digest of tfplan, checked by iac-apply.sh before applying
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ensure_mise
require_tool jq

export WORKING_DIR="${WORKING_DIR:-iac}"
PLAN_DIR="${PLAN_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/iac-plan}"
# Only iac/mise.toml counts, not the repo-root one (see iac-check.sh)
export MISE_CEILING_PATHS
MISE_CEILING_PATHS="$(pwd -P)"

if is_github_actions; then
  require_env GITHUB_TOKEN "Set the IAC_GITHUB_TOKEN secret in the iac-plan environment -- see 'Enabling the iac workflow' in iac/README.md."
fi

log_config WORKING_DIR PLAN_DIR HEAD_SHA TARGET_BRANCH TARGET_SHA PR_NUMBER

rm -rf "$PLAN_DIR"
mkdir -p "$PLAN_DIR"
PLAN_FILE="$PLAN_DIR/tfplan"
SUMMARY_FILE="$PLAN_DIR/summary.md"

# plan.json holds sensitive values unmasked, so it stays out of PLAN_DIR
# (which is uploaded) and is deleted on exit.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
PLAN_LOG="$WORK_DIR/plan.log"

cd_working_dir
require_mise_tool opentofu

# Render the summary, publish it to the job summary, and set the outputs.
# Runs for failures too, so the PR comment says the plan failed instead of
# silently showing the previous push's plan.
finish() {
  local exit_code="$1"
  PLAN_EXIT_CODE="$exit_code" PLAN_LOG="$PLAN_LOG" \
    PLAN_JSON="$WORK_DIR/plan.json" PLAN_TEXT="$WORK_DIR/plan.txt" \
    bash "$SCRIPT_DIR/iac-plan-summary.sh" > "$SUMMARY_FILE"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "$SUMMARY_FILE" >> "$GITHUB_STEP_SUMMARY"
  fi
  log_info "Plan summary written to $SUMMARY_FILE"
}

# -lockfile=readonly: plan (and later apply) with exactly the provider
# versions and checksums committed in .terraform.lock.hcl.
log_step "tofu init"
log_cmd tofu init -input=false -lockfile=readonly
set +e
mise exec -- tofu init -input=false -lockfile=readonly 2>&1 | tee "$PLAN_LOG"
init_exit=${PIPESTATUS[0]}
set -e
if [ "$init_exit" -ne 0 ]; then
  finish "$init_exit"
  set_output has-changes false
  log_error "tofu init failed (exit $init_exit). If it can't reach the state, check the iac workflow's Azure identity (IAC_AZURE_CLIENT_ID) has a federated credential for the iac-plan environment and Storage Blob Data Contributor on the state container (see iac/README.md). If .terraform.lock.hcl is out of date, run 'tofu init -upgrade' in iac/ and commit the lock file."
  exit "$init_exit"
fi

# -lock=false: planning never writes state, and a saved plan is safe without
# the lock -- apply takes the lock and refuses the plan if the state changed
# since. Not locking means a cancelled plan (superseded by a newer push)
# can't leave a stale lease on the state blob.
log_step "tofu plan"
log_cmd tofu plan -input=false -lock=false -detailed-exitcode -out="$PLAN_FILE"
set +e
mise exec -- tofu plan -input=false -lock=false -detailed-exitcode -out="$PLAN_FILE" 2>&1 | tee -a "$PLAN_LOG"
plan_exit=${PIPESTATUS[0]}
set -e

case "$plan_exit" in
  0 | 2) ;;
  *)
    finish "$plan_exit"
    set_output has-changes false
    log_error "tofu plan failed (exit $plan_exit). See the errors above; reproduce with 'tofu plan' in iac/ (see iac/README.md for credentials)."
    exit "$plan_exit"
    ;;
esac

mise exec -- tofu show -json "$PLAN_FILE" > "$WORK_DIR/plan.json"
mise exec -- tofu show -no-color "$PLAN_FILE" > "$WORK_DIR/plan.txt"
finish "$plan_exit"

if [ "$plan_exit" -eq 2 ]; then
  plan_sha256="$(file_sha256 "$PLAN_FILE")"
  set_output has-changes true
  set_output plan-sha256 "$plan_sha256"
  log_summary "Plan has changes (tfplan sha256 $plan_sha256) -- the apply job will wait for approval"
else
  # Nothing to apply: don't leave a plan file around to be uploaded
  rm -f "$PLAN_FILE"
  set_output has-changes false
  log_summary "No changes -- nothing to apply"
fi
