#!/usr/bin/env bash
#
# TFLint check for a module. Used by the PR validation and CI workflows.
#
# Environment variables:
#   WORKING_DIR      - module directory to check (required)
#   TFLINT_RECURSIVE - lint child modules too (default: true)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

cd_working_dir
ensure_mise

log_info "=== Running TFLint ==="
require_mise_tool tflint

log_info "Initializing tflint plugins..."
mise exec -- tflint --init

TFLINT_ARGS=(--format compact)
if [ "${TFLINT_RECURSIVE:-true}" = "true" ]; then
  TFLINT_ARGS+=(--recursive)
fi

log_info "Running tflint ${TFLINT_ARGS[*]}..."
if mise exec -- tflint "${TFLINT_ARGS[@]}"; then
  log_info "TFLint passed"
else
  log_error "TFLint found issues in ${WORKING_DIR}. Fix the findings above; don't add a tflint-ignore without reviewer sign-off."
  exit 1
fi
