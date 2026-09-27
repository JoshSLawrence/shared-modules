#!/usr/bin/env bash
#
# Checks that modules with consumer-affecting changes also have VERSION file
# changes. Used by the PR validation workflow.
#
# Consumer-affecting changes are:
#   - any .tf file in the module
#   - anything in the module's scripts/ directory, or a child module's
#     scripts/ directory -- these ship with the module and (e.g. via
#     local-exec) change its behavior just like .tf changes do
#
# Deliberately computes its own list rather than reusing the output of
# detect-changed-modules.sh: detection triggers validation on *any* module
# change, but tests-, examples-, or docs-only changes don't alter what
# consumers get, so they validate without forcing a new release.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_diff_base
BASE="$(diff_base)"

log_info "Checking for .tf / scripts/ changes without VERSION bump..."

# Find modules with consumer-affecting changes. Every pathspec uses :(glob) so
# "*" can't cross directories -- otherwise e.g. modules/foo/examples/bar/main.tf
# or modules/foo/examples/bar/scripts/ would match and example-only changes
# would force a release.
MODULES_REQUIRING_BUMP=$(git diff --name-only "$BASE"...HEAD -- \
  ':(glob)modules/*/*.tf' \
  ':(glob)modules/*/modules/**/*.tf' \
  ':(glob)modules/*/scripts/**' \
  ':(glob)modules/*/modules/**/scripts/**' \
  | cut -d'/' -f2 | sort -u)

# Find modules with changed VERSION files
MODULES_WITH_VERSION_CHANGES=$(git diff --name-only "$BASE"...HEAD -- 'modules/*/VERSION' | cut -d'/' -f2 | sort -u)

if [ -z "$MODULES_REQUIRING_BUMP" ]; then
  log_info "No .tf or scripts/ files changed in any module"
  exit 0
fi

log_info "Modules with .tf / scripts/ changes: $MODULES_REQUIRING_BUMP"
log_info "Modules with VERSION changes: $MODULES_WITH_VERSION_CHANGES"

ERRORS=0

for module in $MODULES_REQUIRING_BUMP; do
  # Skip if module directory doesn't exist (e.g., deleted module)
  if [ ! -d "modules/$module" ]; then
    log_info "Skipping deleted module: $module"
    continue
  fi

  # Check if VERSION was also updated. Whole-line match (-x), not -w: -w
  # treats "-" as a word boundary, so "foo" would match a bumped "foo-bar".
  if ! echo "$MODULES_WITH_VERSION_CHANGES" | grep -qxF "$module"; then
    log_error "Module '$module' has .tf or scripts/ changes but its VERSION file was not updated. Bump modules/$module/VERSION and add a matching CHANGELOG.md entry."
    ERRORS=$((ERRORS + 1))
  else
    log_info "✓ $module: .tf / scripts/ changes with VERSION bump"
  fi
done

if [ $ERRORS -gt 0 ]; then
  log_error "$ERRORS module(s) missing VERSION bump"
  exit 1
fi

log_info "All modified modules have VERSION bumps"
