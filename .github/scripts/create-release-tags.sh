#!/usr/bin/env bash
#
# Reconciles module-scoped git tags (<module>/vX.Y.Z) and matching GitHub
# Releases against the VERSION files on main. Used by the release workflow.
#
# Every module's current VERSION is checked, not just the ones this push
# changed: GitHub keeps at most one pending run per concurrency group and
# cancels older pending runs, so a diff-based approach would permanently miss
# a release whose run was cancelled. A missing tag is created on the
# first-parent commit that last changed that VERSION file (the squash or
# merge commit on main), so it points at exactly what was merged.
#
# Environment variables:
#   GH_TOKEN - token with contents:write, used by `gh release create`
#              (required; the workflow passes its GITHUB_TOKEN)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_env GH_TOKEN "This script must run inside the release workflow, which passes its GITHUB_TOKEN as GH_TOKEN."
require_tool gh "GitHub CLI (gh)"

# Tags are pushed through the credentials actions/checkout persisted for the
# workflow's GITHUB_TOKEN. Tags pushed with that token deliberately don't
# trigger other workflows, so there's no risk of a release loop.
log_info "Configuring git identity..."
git config user.name "github-actions[bot]"
git config user.email "41898237+github-actions[bot]@users.noreply.github.com"

shopt -s nullglob
VERSION_FILES=(modules/*/VERSION)
shopt -u nullglob

if [ ${#VERSION_FILES[@]} -eq 0 ]; then
  log_info "No modules/*/VERSION files found, nothing to release"
  exit 0
fi

log_info "Reconciling tags and releases for ${#VERSION_FILES[@]} module(s)..."

# Create the GitHub Release for a tag unless one already exists, so re-running
# the workflow after a partial failure fills in anything that's missing.
ensure_release() {
  local module="$1"
  local version="$2"
  local tag="$3"

  if gh release view "$tag" >/dev/null 2>&1; then
    log_info "GitHub Release '$tag' already exists, skipping"
    return 0
  fi

  local notes
  notes="$(changelog_section "$module" "$version")"
  if [ -z "$(echo "$notes" | tr -d '[:space:]')" ]; then
    log_warn "No '## [${version}]' section found in modules/${module}/CHANGELOG.md, using generic release notes"
    notes="See [CHANGELOG.md](https://github.com/${GITHUB_REPOSITORY:-}/blob/${tag}/modules/${module}/CHANGELOG.md)."
  fi

  local usage
  usage=$(cat <<EOF

## Usage

\`\`\`hcl
module "${module//-/_}" {
  source = "git::https://github.com/${GITHUB_REPOSITORY:-<owner>/<repo>}.git//modules/${module}?ref=${tag}"
}
\`\`\`
EOF
)

  # --latest=false: this repo releases many independent modules, so GitHub's
  # single repo-wide "Latest" badge would just point at whichever module
  # happened to release last.
  log_info "Creating GitHub Release: $tag"
  set +e
  gh release create "$tag" \
    --verify-tag \
    --latest=false \
    --title "${module} ${version}" \
    --notes "${notes}"$'\n'"${usage}"
  local release_exit=$?
  set -e

  if [ $release_exit -ne 0 ]; then
    log_error "Failed to create GitHub Release '$tag' (exit $release_exit). The tag exists; re-run the workflow to retry the release."
    return 1
  fi

  log_success "Created GitHub Release: $tag"
}

TAGS_CREATED=0
ERRORS=0

for file in "${VERSION_FILES[@]}"; do
  MODULE=$(module_from_path "$file")
  VERSION=$(read_module_version "$MODULE")

  if ! is_valid_version "$VERSION"; then
    log_error "Invalid version format in $file: '$VERSION' (expected vX.Y.Z). Fix it in a PR; PR validation should have caught this."
    ERRORS=$((ERRORS + 1))
    continue
  fi

  TAG="${MODULE}/${VERSION}"

  if tag_exists "$TAG"; then
    log_debug "$MODULE: tag '$TAG' already exists"
  else
    TARGET=$(git log -1 --first-parent --format=%H -- "$file")
    log_info "$MODULE: creating tag '$TAG' on ${TARGET}"
    set +e
    git tag -a "$TAG" -m "Release $MODULE $VERSION" "$TARGET"
    tag_exit=$?
    set -e

    if [ $tag_exit -ne 0 ]; then
      log_error "Failed to create tag '$TAG' (exit $tag_exit)"
      ERRORS=$((ERRORS + 1))
      continue
    fi

    log_info "Pushing tag: $TAG"
    set +e
    git push origin "refs/tags/$TAG" 2>&1
    push_exit=$?
    set -e

    if [ $push_exit -ne 0 ]; then
      log_error "Failed to push tag '$TAG' (exit $push_exit). Check that the workflow has 'contents: write' and that no tag ruleset blocks github-actions from creating tags."
      ERRORS=$((ERRORS + 1))
      continue
    fi

    log_success "Created tag: $TAG"
    TAGS_CREATED=$((TAGS_CREATED + 1))
  fi

  if ! ensure_release "$MODULE" "$VERSION" "$TAG"; then
    ERRORS=$((ERRORS + 1))
  fi
done

log_info "Summary: $TAGS_CREATED tag(s) created, $ERRORS error(s)"

if [ $ERRORS -gt 0 ]; then
  log_error "Completed with $ERRORS error(s)"
  exit 1
fi

log_info "All module tags and releases are up to date"
