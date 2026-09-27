#!/usr/bin/env bash
#
# OpenTofu format check for a module. Used by the PR validation workflow.
#
# Environment variables:
#   WORKING_DIR - module directory to check (required)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

cd_working_dir
ensure_mise
require_mise_tool opentofu

log_info "=== Running Format Check ==="
if mise exec -- tofu fmt -check -recursive -diff; then
  log_info "Format check passed"
else
  log_error "Format check failed in ${WORKING_DIR}. Run 'tofu fmt -recursive' there (or 'mise run hooks') and commit the result."
  exit 1
fi
