#!/usr/bin/env bash
#
# Sets which fork pull request authors need a maintainer's approval before
# GitHub Actions runs their workflows. The GitHub provider has no resource for
# this setting, so iac/actions.tf runs this script from a terraform_data
# resource whenever the policy changes. Safe to run by hand.
#
# Environment variables:
#   REPOSITORY      - owner/name of the repository (required)
#   APPROVAL_POLICY - first_time_contributors_new_to_github,
#                     first_time_contributors, or all_external_contributors
#                     (required)
#
# Authenticates with the GitHub CLI: GITHUB_TOKEN/GH_TOKEN if set, otherwise
# your `gh auth login` session -- the same credential the provider uses.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/common.sh
source "$SCRIPT_DIR/../../.github/scripts/common.sh"

require_tool gh "GitHub CLI (gh)"
require_env REPOSITORY "Set it to owner/name, e.g. JoshSLawrence/shared-modules."
require_env APPROVAL_POLICY "Set it to all_external_contributors, first_time_contributors, or first_time_contributors_new_to_github."

case "$APPROVAL_POLICY" in
  first_time_contributors_new_to_github | first_time_contributors | all_external_contributors) ;;
  *)
    log_error "Invalid APPROVAL_POLICY '${APPROVAL_POLICY}'. Use all_external_contributors, first_time_contributors, or first_time_contributors_new_to_github."
    exit 1
    ;;
esac

ENDPOINT="repos/${REPOSITORY}/actions/permissions/fork-pr-contributor-approval"

log_info "Setting fork PR workflow approval policy for ${REPOSITORY} to '${APPROVAL_POLICY}'..."
set +e
gh api --method PUT "$ENDPOINT" -f approval_policy="$APPROVAL_POLICY" > /dev/null
exit_code=$?
set -e

if [ $exit_code -ne 0 ]; then
  log_error "Failed to set the fork PR approval policy (gh exit $exit_code). Check that your GitHub credential has admin rights on ${REPOSITORY} ('gh auth status')."
  exit $exit_code
fi

# Read it back: a PUT that GitHub accepted but silently ignored would
# otherwise leave the repo more permissive than iac/ claims.
actual="$(gh api "$ENDPOINT" --jq .approval_policy)"
if [ "$actual" != "$APPROVAL_POLICY" ]; then
  log_error "Fork PR approval policy is '${actual}' after setting '${APPROVAL_POLICY}'. Set it under Settings -> Actions -> General and re-run."
  exit 1
fi

log_success "Fork PR workflow approval policy is '${APPROVAL_POLICY}'"
