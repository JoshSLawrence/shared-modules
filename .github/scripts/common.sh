#!/usr/bin/env bash
# Common functions library for workflow and task scripts
# Source this file in other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # from .github/scripts/
#   source "$SCRIPT_DIR/common.sh"
#
#   source "$(dirname "$0")/../.github/scripts/common.sh"      # from mise-tasks/

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Track script start time for total duration
SCRIPT_START_TIME=${EPOCHSECONDS:-$(date +%s)}

# Detect if running in GitHub Actions (GITHUB_ACTIONS is set to "true")
is_github_actions() {
  [[ "${GITHUB_ACTIONS:-}" == "true" ]]
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

# Warnings/errors are also emitted as GitHub workflow commands so they show up
# as annotations on the run summary and PR, instead of just "Process completed
# with exit code 1". Workflow commands go to stdout, where the runner parses
# them.
log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
  if is_github_actions; then
    echo "::warning::$1"
  fi
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
  if is_github_actions; then
    echo "::error::$1"
  fi
}

log_debug() {
  echo -e "${BLUE}[DEBUG]${NC} $1" >&2
}

log_step() {
  echo ""
  echo -e "${CYAN}========================================${NC}"
  echo -e "${CYAN}== ${1}${NC}"
  echo -e "${CYAN}========================================${NC}"
}

# Log the command about to be run (dimmed so it doesn't dominate)
# Goes to stderr so it doesn't pollute captured output
log_cmd() {
  echo -e "${GRAY}> $*${NC}" >&2
}

# Log configuration variables in a readable format
# Usage: log_config "VAR1" "VAR2" "VAR3"
log_config() {
  local max_len=0
  for var_name in "$@"; do
    (( ${#var_name} > max_len )) && max_len=${#var_name}
  done

  for var_name in "$@"; do
    local var_value="${!var_name:-<not set>}"
    printf "  ${BOLD}%-${max_len}s${NC} = %s\n" "$var_name" "$var_value"
  done
}

# Format seconds into human-readable duration
format_duration() {
  local seconds=$1
  if (( seconds < 60 )); then
    echo "${seconds}s"
  elif (( seconds < 3600 )); then
    echo "$((seconds / 60))m $((seconds % 60))s"
  else
    echo "$((seconds / 3600))h $((seconds % 3600 / 60))m $((seconds % 60))s"
  fi
}

# Log a final summary with total elapsed time
log_summary() {
  local message="${1:-Script completed}"
  local now=${EPOCHSECONDS:-$(date +%s)}
  local elapsed=$((now - SCRIPT_START_TIME))

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}== ${message}${NC}"
  echo -e "${GREEN}== Total time: $(format_duration $elapsed)${NC}"
  echo -e "${GREEN}========================================${NC}"
}

# Check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Require a tool to be installed, exit if not found
require_tool() {
  local cmd="$1"
  local name="${2:-$cmd}"
  if ! command_exists "$cmd"; then
    log_error "$name is not installed. Please install $name to proceed."
    exit 1
  fi
  log_debug "$name found: $(command -v "$cmd")"
}

# Require an environment variable to be set, exit if not
# Usage: require_env "VAR_NAME" ["hint on how to set it"]
require_env() {
  local name="$1"
  local hint="${2:-}"
  if [ -z "${!name:-}" ]; then
    log_error "$name is not set.${hint:+ $hint}"
    exit 1
  fi
}

# Set a step output for later steps/jobs. Outside GitHub Actions (e.g. when
# running a script locally to debug it) there's no GITHUB_OUTPUT file, so the
# value is just logged instead.
# Usage: set_output "name" "value"
set_output() {
  local name="$1"
  local value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  else
    log_debug "output: ${name}=${value}"
  fi
}

# Print a file's SHA-256 (sha256sum on Linux runners, shasum on macOS)
file_sha256() {
  if command_exists sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Base ref that PR changes are diffed against. On pull_request events the
# workflow passes origin/<base branch>; locally this defaults to origin/main.
diff_base() {
  echo "${BASE_REF:-origin/main}"
}

# Fail if the diff base doesn't resolve to a commit. Without this, a missing
# ref makes `git diff` error out, which would look like "no changes" if
# swallowed -- skipping validation and passing the PR. Call before diffing.
require_diff_base() {
  local base
  base="$(diff_base)"
  if ! git rev-parse -q --verify "${base}^{commit}" > /dev/null; then
    log_error "Diff base '${base}' not found. In CI, check actions/checkout uses fetch-depth: 0; locally, run 'git fetch origin' or set BASE_REF to an existing ref."
    exit 1
  fi
}

# Module VERSION files hold a single vX.Y.Z; tags are <module>/vX.Y.Z.
# Shared by PR validation and the release workflow so both agree on what a
# valid version and an existing tag are.
VERSION_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+$'

# Print the module name for a path under modules/ (modules/<name>/... -> <name>)
module_from_path() {
  echo "$1" | cut -d'/' -f2
}

# Print a module's VERSION with surrounding whitespace stripped
# Usage: read_module_version "<module>"
read_module_version() {
  tr -d '[:space:]' < "modules/$1/VERSION"
}

is_valid_version() {
  [[ "$1" =~ $VERSION_REGEX ]]
}

# True if version $1 is strictly greater than version $2 (both vX.Y.Z)
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# Print the body of a module's CHANGELOG.md section for a version: everything
# after the "## [vX.Y.Z]" heading up to the next "## " heading. Prints nothing
# if the file or section is missing.
# Usage: changelog_section "<module>" "<version>"
changelog_section() {
  local changelog="modules/$1/CHANGELOG.md"
  [ -f "$changelog" ] || return 0
  awk -v heading="## [$2]" '
    index($0, heading) == 1 { in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$changelog"
}

# True if the tag exists locally. Checks refs/tags/ explicitly -- a bare
# `git rev-parse <module>/vX.Y.Z` would also match a branch of that name.
tag_exists() {
  git rev-parse -q --verify "refs/tags/$1" > /dev/null
}

# cd into WORKING_DIR (required) for the module validation check scripts
cd_working_dir() {
  require_env "WORKING_DIR" "Set it to the module directory to check (e.g. modules/<module-name>)."
  log_info "Changing to working directory: ${WORKING_DIR}"
  if ! cd "${WORKING_DIR}"; then
    log_error "Could not cd into WORKING_DIR '${WORKING_DIR}' (from $PWD). Check the module directory exists."
    exit 1
  fi
}

# Ensure mise is available (the validation checks run every tool via mise so
# CI uses exactly the versions pinned in the module's mise.toml)
ensure_mise() {
  if ! command_exists mise; then
    log_error "mise is not installed or not in PATH. Install it from https://mise.jdx.dev and retry."
    exit 1
  fi
}

# Fail unless mise resolves a version for a tool in the current directory.
# A check whose tool isn't pinned must fail rather than skip: otherwise
# deleting e.g. trivy from a module's mise.toml would silently disable its
# security scan. In CI, MISE_CEILING_PATHS stops mise from inheriting the
# repo-root mise.toml, so this reflects the module's own pins.
# Usage: require_mise_tool "<mise tool name>"
require_mise_tool() {
  local tool="$1"
  if [ -z "$(mise current "$tool" 2> /dev/null)" ]; then
    log_error "$tool is not pinned in ${WORKING_DIR:-.}/mise.toml. Add it (the standard pins are in cookiecutter/templates/shared-module/cookiecutter.json) so this check runs with a known version."
    exit 1
  fi
}

# Let `tofu init` fetch module sources hosted on GitHub (e.g. one shared module
# consuming another via git::https://github.com/... or git@github.com:...) when
# the repo is private. Rewrites GitHub URLs to authenticate with GITHUB_TOKEN.
# It's a no-op when GITHUB_TOKEN isn't set (local dev uses your own git
# credentials). The config is written to a throwaway file via GIT_CONFIG_GLOBAL
# rather than ~/.gitconfig so the token never lands in a persistent config.
configure_git_github_auth() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_debug "GITHUB_TOKEN not set -- skipping Git auth setup for GitHub module sources"
    return 0
  fi

  log_info "Configuring Git credentials for GitHub module sources..."

  local git_config
  git_config="$(mktemp)"
  export GIT_CONFIG_GLOBAL="$git_config"

  local authed="https://x-access-token:${GITHUB_TOKEN}@github.com/"
  git config --global url."${authed}".insteadOf "https://github.com/"
  git config --global --add url."${authed}".insteadOf "ssh://git@github.com/"
  git config --global --add url."${authed}".insteadOf "git@github.com:"
}
