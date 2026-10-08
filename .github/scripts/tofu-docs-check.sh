#!/usr/bin/env bash
#
# Checks that a module's terraform-docs generated README.md is up to date.
# Used by the PR validation and CI workflows. Regenerates using the module's own
# .terraform-docs.yaml (same as the pre-commit hook and post-gen template
# hook) and fails if that changes anything.
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

log_info "=== Running Terraform Docs Check ==="
require_mise_tool terraform-docs

log_info "Regenerating README.md..."
if ! mise exec -- terraform-docs .; then
  log_error "terraform-docs generation failed in ${WORKING_DIR}. Check .terraform-docs.yaml and .header.md."
  exit 1
fi

# README.md may be brand new (untracked) in a PR adding a module, so add it
# with --intent-to-add; otherwise git diff wouldn't report it at all.
git add --intent-to-add README.md
if git diff --exit-code -- README.md; then
  log_info "Documentation is up to date"
else
  log_error "README.md is out of date in ${WORKING_DIR}. Run 'mise exec -- terraform-docs .' there (or 'mise run hooks') and commit the result."
  exit 1
fi
