#!/usr/bin/env bash
#
# Trivy misconfiguration scan for a module. Used by the PR validation workflow.
#
# Trivy picks up the module's own trivy.yaml from WORKING_DIR, which sets the
# severity threshold and exit code -- the same file the pre-commit hook
# reads, so local and CI results match.
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

log_info "=== Running Trivy Security Scan ==="
require_mise_tool trivy

if [ ! -f trivy.yaml ]; then
  log_error "No trivy.yaml in ${WORKING_DIR}. Copy it from cookiecutter/templates/opentofu/ so the scan uses the repo's standard severity threshold."
  exit 1
fi

log_info "Trivy version: $(mise exec -- trivy --version | head -1)"

if mise exec -- trivy config --skip-version-check --format table .; then
  log_info "Trivy security scan passed"
else
  log_error "Trivy found issues in ${WORKING_DIR}. Fix the findings above; don't add a trivy:ignore without reviewer sign-off."
  exit 1
fi
