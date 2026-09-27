#!/usr/bin/env bash
#
# Creates or updates the iac workflow's comment on a PR: the plan summary
# from iac-plan-summary.sh plus where the apply stands. There's one comment
# per PR, edited in place by every run, so the PR always shows the latest
# plan instead of a growing stack of stale ones (earlier versions stay in
# the comment's edit history, and every run's summary stays on its run page).
#
# Environment variables:
#   GH_TOKEN          - token for the GitHub API (the workflow's GITHUB_TOKEN,
#                       so the comment is authored by github-actions[bot])
#   GITHUB_REPOSITORY - owner/name
#   PR_NUMBER         - PR to comment on. Unset (runs on main): does nothing.
#   HEAD_SHA          - PR head commit this run planned
#   SUMMARY_FILE      - plan summary markdown. If missing (the run failed
#                       before planning), a pointer to the run log is posted.
#   APPLY_STATUS      - none, awaiting-approval, succeeded, or failed
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

if [ -z "${PR_NUMBER:-}" ]; then
  log_info "Not a pull request run -- nothing to comment on"
  exit 0
fi

require_tool gh "GitHub CLI (gh)"
require_tool jq
require_env GH_TOKEN
require_env GITHUB_REPOSITORY
require_env HEAD_SHA
require_env APPLY_STATUS

case "$APPLY_STATUS" in
  none | awaiting-approval | succeeded | failed) ;;
  *)
    log_error "Unknown APPLY_STATUS '${APPLY_STATUS}'. Use none, awaiting-approval, succeeded, or failed."
    exit 1
    ;;
esac

# Hidden marker identifying the comment to update. Only comments by
# github-actions[bot] count, so nobody can hijack the update by quoting it.
MARKER="<!-- iac-plan-apply -->"
BOT_LOGIN="github-actions[bot]"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
RUN_URL="${REPO_URL}/actions/runs/${GITHUB_RUN_ID:-}"
README_URL="${REPO_URL}/blob/main/iac/README.md"

# Runs for older pushes can finish after newer ones (an approval given late,
# a slow apply). Leave the comment to the newest push's run instead of
# overwriting its plan with an outdated one.
current_head="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq .head.sha)"
if [ "$current_head" != "$HEAD_SHA" ]; then
  log_warn "PR #${PR_NUMBER} is now at ${current_head:0:7}, newer than this run's ${HEAD_SHA:0:7} -- leaving the PR comment to the newer run. This run's result is in its job summary."
  exit 0
fi

# Who approved this run's deployment, for the record. Best effort: the
# comment is still worth posting if this lookup fails.
approvers() {
  gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-0}/approvals" \
    --jq '[.[] | select(.state == "approved") | "@" + .user.login] | unique | join(", ")' 2> /dev/null || true
}

apply_section() {
  case "$APPLY_STATUS" in
    none) ;;
    awaiting-approval)
      echo "### 🔒 Apply: awaiting approval"
      echo ""
      echo "Review the plan above, then approve the \`iac-apply\` deployment on the [workflow run](${RUN_URL}) to apply exactly this plan. It's refused if the PR gets new commits or \`iac/\` changes on \`main\` first -- that push plans again, and its run is the one to approve."
      ;;
    succeeded)
      local by
      by="$(approvers)"
      echo "### ✅ Applied"
      echo ""
      echo "This plan was applied by the [workflow run](${RUN_URL})${by:+, approved by ${by}}. Merge the PR to record it on \`main\`. To roll back, close the PR and run the iac workflow on \`main\` (see the [iac README](${README_URL}))."
      ;;
    failed)
      echo "### ❌ Apply failed"
      echo ""
      echo "See the [workflow run](${RUN_URL}) log. If \`tofu apply\` started, some changes may already be live: fix the problem and push to plan again, or roll back by running the iac workflow on \`main\`. If the plan was refused as out of date, nothing was applied."
      ;;
  esac
}

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
{
  echo "$MARKER"
  echo "## OpenTofu: \`iac/\`"
  echo ""
  if [ -n "${SUMMARY_FILE:-}" ] && [ -s "$SUMMARY_FILE" ]; then
    cat "$SUMMARY_FILE"
  else
    echo "### ❌ No plan"
    echo ""
    echo "The [workflow run](${RUN_URL}) failed before it produced a plan. See its log."
  fi
  section="$(apply_section)"
  if [ -n "$section" ]; then
    echo ""
    echo "$section"
  fi
} > "$BODY_FILE"

# Oldest match wins, should two runs ever have raced to create the comment.
# Not piped into `head`: that could kill gh mid-pagination and fail the step.
comment_ids="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
  --jq ".[] | select(.user.login == \"${BOT_LOGIN}\" and (.body | startswith(\"${MARKER}\"))) | .id")"
comment_id="${comment_ids%%$'\n'*}"

payload="$(jq -n --rawfile body "$BODY_FILE" '{body: $body}')"
if [ -n "$comment_id" ]; then
  log_info "Updating comment ${comment_id} on PR #${PR_NUMBER}..."
  gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${comment_id}" --input - <<< "$payload" > /dev/null
else
  log_info "Creating comment on PR #${PR_NUMBER}..."
  gh api --method POST "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --input - <<< "$payload" > /dev/null
fi

log_success "PR #${PR_NUMBER} comment is up to date (apply status: ${APPLY_STATUS})"
