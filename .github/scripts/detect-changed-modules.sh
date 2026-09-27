#!/usr/bin/env bash
#
# Detects modules with any changed file (under modules/<name>/) and exposes
# them as step outputs for the PR validation workflow, so every module a PR
# touches gets validated -- not just those with .tf changes. A tests-, lint
# config-, or docs-only change can break validation just as easily.
# Outputs:
#   - matrix: JSON array of module names for the validation job's matrix
#   - has-changes: true/false flag
#   - integration-matrix: JSON array of the changed modules that have
#     integration tests (tests/9*.tftest.hcl), for the integration job
#   - has-integration-tests: true/false flag
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_tool jq

require_diff_base
BASE="$(diff_base)"
log_info "Detecting changed modules (diffing against $BASE)..."

# Find modules with any changed file. NF >= 3 keeps only paths inside a
# module directory (modules/<name>/...), ignoring files sitting directly in
# modules/ (e.g. modules/.gitkeep), which aren't a module. No `|| true`: a
# failing git diff must fail the job, not read as "no changes".
MODULES=$(git diff --name-only "$BASE"...HEAD -- 'modules/' | awk -F/ 'NF >= 3 { print $2 }' | sort -u)

VALID_MODULES=()
INTEGRATION_MODULES=()
for module in $MODULES; do
  # Skip if module directory doesn't exist (deleted module)
  if [ ! -d "modules/$module" ]; then
    log_info "Skipping deleted module: $module"
    continue
  fi

  # Module names end up in job names and paths; reject anything unexpected
  if [[ ! "$module" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_warn "Skipping module with invalid characters: $module. Module directory names may only contain letters, digits, '-' and '_'."
    continue
  fi

  VALID_MODULES+=("$module")
  if compgen -G "modules/$module/tests/9*.tftest.hcl" > /dev/null; then
    INTEGRATION_MODULES+=("$module")
    log_info "  - $module (has integration tests)"
  else
    log_info "  - $module"
  fi
done

# Print a JSON array of the arguments ([] when there are none)
json_array() {
  if [ $# -eq 0 ]; then
    echo "[]"
  else
    printf '%s\n' "$@" | jq -Rnc '[inputs]'
  fi
}

MATRIX=$(json_array "${VALID_MODULES[@]+"${VALID_MODULES[@]}"}")
INTEGRATION_MATRIX=$(json_array "${INTEGRATION_MODULES[@]+"${INTEGRATION_MODULES[@]}"}")
log_info "Matrix JSON: $MATRIX"
log_info "Integration matrix JSON: $INTEGRATION_MATRIX"

# GitHub rejects a matrix built from an empty array, so the has-* flags let
# the workflow skip a job instead -- e.g. for PRs touching no module, or that
# only deleted modules.
set_output matrix "$MATRIX"
set_output has-changes "$([ ${#VALID_MODULES[@]} -gt 0 ] && echo true || echo false)"
set_output integration-matrix "$INTEGRATION_MATRIX"
set_output has-integration-tests "$([ ${#INTEGRATION_MODULES[@]} -gt 0 ] && echo true || echo false)"
