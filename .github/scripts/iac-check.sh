#!/usr/bin/env bash
#
# Runs the module checks (fmt, validate, tflint, trivy, terraform-docs, tofu
# test) against iac/, the root module that configures this repository on
# GitHub. Validation only -- it never applies anything (see iac/README.md
# for how changes are applied). Used by the PR validation and CI workflows; safe to
# run locally.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ensure_mise

export WORKING_DIR=iac
# Only iac/mise.toml counts, not the repo-root one: iac/ is applied with its
# own (newer) OpenTofu, and a tool missing from its pins should fail here.
export MISE_CEILING_PATHS
MISE_CEILING_PATHS="$(pwd -P)"
export TOFU_TEST_SCOPE=all

CHECKS=(tofu-fmt-check tofu-validate-check tofu-lint-check tofu-security-check tofu-docs-check tofu-test-check)
FAILED=()

for check in "${CHECKS[@]}"; do
  log_step "iac: $check"
  # Subshell: each check cd's into WORKING_DIR and may exit
  if (bash "$SCRIPT_DIR/${check}.sh"); then
    log_success "$check passed"
  else
    FAILED+=("$check")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  log_error "iac/ failed: ${FAILED[*]}. Reproduce with '.github/scripts/iac-check.sh' from the repo root."
  exit 1
fi

log_summary "iac/ passes all checks"
