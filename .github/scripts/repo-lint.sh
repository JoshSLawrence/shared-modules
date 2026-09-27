#!/usr/bin/env bash
#
# Repo-level lint for everything outside modules/ -- workflow and task
# scripts, workflow definitions -- which the per-module validation never
# looks at. Runs the relevant pre-commit hooks from .pre-commit-config.yaml
# against all files, so CI and local hooks share one definition. Used by the
# PR validation workflow; tools come from the repo-root mise.toml.
#
# check-added-large-files isn't run here: it only inspects files staged for
# commit, so it can only ever fire locally.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

ensure_mise
for tool in pre-commit shellcheck actionlint; do
  require_mise_tool "$tool"
done

HOOKS=(trailing-whitespace shellcheck actionlint-system)
FAILED=()

for hook in "${HOOKS[@]}"; do
  log_step "pre-commit hook: $hook"
  if mise exec -- pre-commit run --all-files --show-diff-on-failure "$hook"; then
    log_success "$hook passed"
  else
    log_error "pre-commit hook '$hook' failed. Run 'pre-commit run --all-files $hook' locally to reproduce, fix the findings, and commit."
    FAILED+=("$hook")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  log_error "${#FAILED[@]} repo lint check(s) failed: ${FAILED[*]}"
  exit 1
fi

log_summary "Repo lint passed"
