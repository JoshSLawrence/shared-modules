#!/usr/bin/env bash
#
# Renders the OpenTofu cookiecutter template (from the cookiecutter/
# submodule) into a throwaway module and runs the same checks PR validation
# runs on real modules, so a submodule bump can't scaffold modules that fail
# CI. Used by the PR validation workflow; safe to run locally.
#
# Every provider is enabled so each provider's generated config gets checked.
# The template hardcodes its tool versions; only opentofu_version is taken
# from the repo-root mise.toml (the OpenTofu floor), as `mise run new-module`
# does.
#
# Environment variables:
#   TEMPLATE_DIR - template to render (default: cookiecutter/templates/opentofu).
#                  Point it at a local clone to test template changes before
#                  bumping the submodule.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ensure_mise
require_mise_tool cookiecutter
require_mise_tool opentofu

TEMPLATE_DIR="${TEMPLATE_DIR:-cookiecutter/templates/opentofu}"
MODULE_NAME="CI Template Check"
MODULE_SLUG="ci-template-check"
OUT_DIR="modules/${MODULE_SLUG}"
OPENTOFU_VERSION="$(mise current opentofu)"

if [ ! -f "$TEMPLATE_DIR/cookiecutter.json" ]; then
  log_error "No cookiecutter template at $TEMPLATE_DIR. Run 'git submodule update --init cookiecutter' (in CI, check out with 'submodules: true'). If the submodule is already initialized, it's pinned to a commit without the template: bump it with 'git submodule update --remote cookiecutter'."
  exit 1
fi

if [ -e "$OUT_DIR" ]; then
  log_error "$OUT_DIR already exists. Remove it (it's left over from an earlier run, not a real module) and retry."
  exit 1
fi

# Stage the rendered files in a private copy of the index: the docs check
# diffs README.md against the index, and this keeps a local run from
# touching your real staging area.
TMP_INDEX="$(mktemp)"
cp "$(git rev-parse --git-path index)" "$TMP_INDEX"
export GIT_INDEX_FILE="$TMP_INDEX"

cleanup() {
  rm -rf "$OUT_DIR" "$TMP_INDEX"
}
trap cleanup EXIT

log_step "Rendering $TEMPLATE_DIR"
log_config TEMPLATE_DIR MODULE_NAME OUT_DIR OPENTOFU_VERSION

if ! mise exec -- cookiecutter --no-input "$TEMPLATE_DIR" -o modules \
  module_name="$MODULE_NAME" \
  opentofu_version="$OPENTOFU_VERSION" \
  use_azurerm=true \
  use_azapi=true \
  use_azuread=true \
  use_random=true; then
  log_error "cookiecutter failed to render $TEMPLATE_DIR. Run 'mise run new-module' locally to reproduce."
  exit 1
fi

# Configure git user for CI environments
if is_github_actions; then
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git config user.name "github-actions[bot]"
fi

git add -A "$OUT_DIR"

# Same isolation as the validate job: only the rendered module's mise.toml
# counts, so a pin missing from the template is caught here.
export WORKING_DIR="$OUT_DIR"
export MISE_CEILING_PATHS
MISE_CEILING_PATHS="$(pwd -P)/modules"
export TOFU_TEST_SCOPE=unit

CHECKS=(tofu-fmt-check tofu-validate-check tofu-lint-check tofu-security-check tofu-docs-check tofu-test-check)
FAILED=()

for check in "${CHECKS[@]}"; do
  log_step "$check"
  # Subshell: each check cd's into WORKING_DIR and may exit
  if (bash "$SCRIPT_DIR/${check}.sh"); then
    log_success "$check passed"
  else
    FAILED+=("$check")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  log_error "A module freshly rendered from $TEMPLATE_DIR fails: ${FAILED[*]}. Fix the template upstream in JoshSLawrence/cookiecutter so new modules pass CI out of the box, then bump the submodule."
  exit 1
fi

log_summary "Rendered template passes all module checks"
