#!/usr/bin/env bash
#
# Runs OpenTofu's native test framework (tofu test) for a module. Used by the
# PR validation and CI workflows.
#
# Environment variables:
#   WORKING_DIR       - module directory to check (required)
#   TOFU_TEST_SCOPE   - which test files to run, using the same split as the
#                       pre-commit hook (default: all):
#                         unit        - tests/[0-8]*.tftest.hcl (no credentials)
#                         integration - tests/9*.tftest.hcl (real infrastructure)
#                         all         - every test file
#   TOFU_TEST_VERBOSE - "true" to pass -verbose (default: false)
#   GITHUB_TOKEN      - lets tofu fetch GitHub-hosted module sources when the
#                       repo is private (optional)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

cd_working_dir
ensure_mise
require_mise_tool opentofu
configure_git_github_auth

TOFU_TEST_SCOPE="${TOFU_TEST_SCOPE:-all}"
log_info "=== Running OpenTofu Test (scope: ${TOFU_TEST_SCOPE}) ==="

case "$TOFU_TEST_SCOPE" in
  unit) PATTERN="tests/[0-8]*.tftest.hcl" ;;
  integration) PATTERN="tests/9*.tftest.hcl" ;;
  all) PATTERN="" ;;
  *)
    log_error "Invalid TOFU_TEST_SCOPE '${TOFU_TEST_SCOPE}'. Use unit, integration, or all."
    exit 1
    ;;
esac

if ! compgen -G "*.tftest.hcl" > /dev/null 2>&1 && \
   ! compgen -G "tests/*.tftest.hcl" > /dev/null 2>&1; then
  log_warn "No test files found in ${WORKING_DIR} (*.tftest.hcl or tests/*.tftest.hcl), skipping. Shared modules are expected to test their validation logic -- see CLAUDE.md."
  exit 0
fi

TEST_ARGS=()

if [ "${TOFU_TEST_VERBOSE:-false}" = "true" ]; then
  TEST_ARGS+=("-verbose")
fi

if [ -n "$PATTERN" ]; then
  mapfile -t TEST_FILES < <(compgen -G "$PATTERN" | sort || true)
  if [ ${#TEST_FILES[@]} -eq 0 ]; then
    log_warn "No ${TOFU_TEST_SCOPE} tests found (${PATTERN}), skipping"
    exit 0
  fi
  for test_file in "${TEST_FILES[@]}"; do
    TEST_ARGS+=("-filter=${test_file}")
  done
fi

# tofu test needs an initialized working directory. Don't rely on an earlier
# step having run init: the integration job runs this on a fresh checkout.
log_info "Initializing OpenTofu (without backend)..."
if ! mise exec -- tofu init -backend=false -input=false > /dev/null; then
  log_error "tofu init failed in ${WORKING_DIR}. Run 'tofu init -backend=false' there to see the full error."
  exit 1
fi

log_info "Running tofu test${TEST_ARGS[*]:+ ${TEST_ARGS[*]}}..."
if mise exec -- tofu test "${TEST_ARGS[@]+"${TEST_ARGS[@]}"}"; then
  log_info "OpenTofu tests passed"
else
  log_error "OpenTofu tests failed in ${WORKING_DIR}. Run 'mise run test <module-name>' to reproduce (integration tests need cloud credentials)."
  exit 1
fi
