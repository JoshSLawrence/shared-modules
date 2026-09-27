#!/usr/bin/env bash
#
# Refuses to apply an iac/ plan that no longer describes what would merge.
# Runs in the iac workflow's apply job, after the approval and before
# anything is applied. An approval can come hours or days after the plan,
# and OpenTofu only rejects a saved plan when the *state* changed since --
# not when the code did. So check that:
#
#   - the PR is still open and has no newer commits (a newer push has its
#     own plan, which is the one to review and approve), and
#   - iac/ hasn't changed on the target branch since the plan (applying
#     would undo whatever merged there, until that's applied again).
#
# Environment variables:
#   GH_TOKEN          - token for the GitHub API (the workflow's GITHUB_TOKEN)
#   GITHUB_REPOSITORY - owner/name
#   TARGET_BRANCH     - branch the change lands on (e.g. main)
#   TARGET_SHA        - commit of TARGET_BRANCH the plan was made against
#   PR_NUMBER, HEAD_SHA - the PR and the head commit that was planned (PR
#                       runs only; unset for runs on main)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

require_tool gh "GitHub CLI (gh)"
require_tool jq
require_env GH_TOKEN
require_env GITHUB_REPOSITORY
require_env TARGET_BRANCH
require_env TARGET_SHA

log_config GITHUB_REPOSITORY PR_NUMBER HEAD_SHA TARGET_BRANCH TARGET_SHA

if [ -n "${PR_NUMBER:-}" ]; then
  RERUN_HINT="Update the branch with ${TARGET_BRANCH} (or push a commit) to plan again, then approve that run instead."
else
  RERUN_HINT="Run the iac workflow on ${TARGET_BRANCH} again to plan its current state."
fi

if [ -n "${PR_NUMBER:-}" ]; then
  require_env HEAD_SHA
  log_info "Checking PR #${PR_NUMBER} is open and still at ${HEAD_SHA:0:7}..."
  pr="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")"
  state="$(jq -r .state <<< "$pr")"
  current_head="$(jq -r .head.sha <<< "$pr")"

  if [ "$state" != "open" ]; then
    log_error "PR #${PR_NUMBER} is ${state}; plans are only applied from open PRs. To apply what's on ${TARGET_BRANCH}, run the iac workflow on ${TARGET_BRANCH} (Actions -> iac -> Run workflow)."
    exit 1
  fi
  if [ "$current_head" != "$HEAD_SHA" ]; then
    log_error "PR #${PR_NUMBER} has moved on to ${current_head:0:7} since this plan (${HEAD_SHA:0:7}). Approve the newer run's apply instead -- its plan includes the new commits."
    exit 1
  fi
  log_success "PR #${PR_NUMBER} is open and unchanged"
fi

log_info "Checking iac/ hasn't changed on ${TARGET_BRANCH} since ${TARGET_SHA:0:7}..."
comparison="$(gh api "repos/${GITHUB_REPOSITORY}/compare/${TARGET_SHA}...${TARGET_BRANCH}")"
ahead_by="$(jq -r .ahead_by <<< "$comparison")"
file_count="$(jq -r '.files | length' <<< "$comparison")"
iac_files="$(jq -r '[.files[]? | select(.filename | startswith("iac/")) | .filename] | join(", ")' <<< "$comparison")"

# The compare API lists at most 300 files, so with more than that an iac/
# change could be missing from the list. Too much has changed to be sure the
# plan is current either way.
if [ "$file_count" -ge 300 ]; then
  log_error "${TARGET_BRANCH} has changed too much since this plan (${ahead_by} commits, ${file_count}+ files) to check iac/ is unaffected. ${RERUN_HINT}"
  exit 1
fi
if [ -n "$iac_files" ]; then
  log_error "iac/ changed on ${TARGET_BRANCH} since this plan (${iac_files}). Applying it would revert those changes. ${RERUN_HINT}"
  exit 1
fi

log_success "Plan is still current (${TARGET_BRANCH} is ${ahead_by} commit(s) ahead, none touching iac/)"
