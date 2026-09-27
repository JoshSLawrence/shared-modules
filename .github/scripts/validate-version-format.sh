#!/usr/bin/env bash
#
# Validates each VERSION file changed in a PR: vX.Y.Z format, tag doesn't
# already exist, version is greater than main's, and CHANGELOG.md has a
# non-empty section for it. Used by the PR validation workflow.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_diff_base
BASE="$(diff_base)"

log_info "Validating VERSION files..."

# Find VERSION files changed in this PR. --diff-filter=AM: a deleted module
# has no VERSION left to read, and nothing to release.
CHANGED_FILES=$(git diff --name-only --diff-filter=AM "$BASE"...HEAD -- 'modules/*/VERSION')

if [ -z "$CHANGED_FILES" ]; then
  log_info "No VERSION files changed in this PR"
  exit 0
fi

log_info "Found changed VERSION files:"
echo "$CHANGED_FILES"

# Tags are already local: the workflow checks out with fetch-depth: 0, which
# fetches every tag.
ERRORS=0

for file in $CHANGED_FILES; do
  MODULE=$(module_from_path "$file")
  VERSION=$(read_module_version "$MODULE")

  log_info "Checking $MODULE: $VERSION"

  if ! is_valid_version "$VERSION"; then
    log_error "Invalid version format in $file: '$VERSION' (expected vX.Y.Z)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  TAG="${MODULE}/${VERSION}"

  if tag_exists "$TAG"; then
    log_error "Tag '$TAG' already exists. Bump the version in $file."
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Compare against main's current VERSION (not the merge base), so a PR
  # can't release a version lower than what main already has.
  PREVIOUS=$(git show "${BASE}:${file}" 2> /dev/null | tr -d '[:space:]' || true)
  if is_valid_version "$PREVIOUS" && ! version_gt "$VERSION" "$PREVIOUS"; then
    log_error "$MODULE: VERSION $VERSION is not greater than $PREVIOUS on $BASE. Set $file to a higher version."
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # The release workflow uses this section as the GitHub Release notes
  if [ -z "$(changelog_section "$MODULE" "$VERSION" | tr -d '[:space:]')" ]; then
    log_error "$MODULE: modules/$MODULE/CHANGELOG.md has no (or an empty) '## [$VERSION]' section. Add one describing this release."
    ERRORS=$((ERRORS + 1))
    continue
  fi

  log_info "  ✓ Valid: will create tag '$TAG' on merge"
done

if [ $ERRORS -gt 0 ]; then
  log_error "$ERRORS validation error(s) found"
  exit 1
fi

log_info "All VERSION files valid"
