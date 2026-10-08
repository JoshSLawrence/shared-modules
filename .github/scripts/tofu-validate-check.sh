#!/usr/bin/env bash
#
# OpenTofu validate check for a module. Used by the PR validation and CI workflows.
#
# Environment variables:
#   WORKING_DIR  - module directory to check (required)
#   GITHUB_TOKEN - lets `tofu init` fetch GitHub-hosted module sources when the
#                  repo is private (optional; see configure_git_github_auth)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

cd_working_dir
ensure_mise
require_mise_tool opentofu
configure_git_github_auth

log_info "=== Running OpenTofu Validate ==="

# Initialize without a backend (still downloads modules/providers)
log_info "Initializing OpenTofu (without backend)..."

set +e
INIT_OUTPUT=$(mise exec -- tofu init -backend=false 2>&1)
INIT_EXIT_CODE=$?
set -e

if [ $INIT_EXIT_CODE -ne 0 ]; then
  log_warn "OpenTofu init failed (exit code: $INIT_EXIT_CODE)"
  echo "$INIT_OUTPUT"

  # Surface the common auth failure with a fix, rather than letting validate
  # fail later with a vaguer "module not installed" error.
  if echo "$INIT_OUTPUT" | grep -qiE "could not read (Username|Password)|permission denied|repository.*not found|authentication failed|401|403"; then
    log_error "tofu init failed with what looks like a Git authentication/permissions error. If a module source points at another private GitHub repo, the workflow's GITHUB_TOKEN can't read it -- grant access (e.g. a GitHub App or fine-grained token passed as GITHUB_TOKEN) or make the source repo readable."
    exit 1
  fi

  # Otherwise continue -- validate reports a clearer error about what's missing
fi

log_info "Running OpenTofu validate..."
if mise exec -- tofu validate; then
  log_info "OpenTofu validation passed"
else
  log_error "OpenTofu validation failed in ${WORKING_DIR}. Run 'tofu init -backend=false && tofu validate' there to reproduce."
  exit 1
fi
