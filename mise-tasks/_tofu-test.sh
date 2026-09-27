#!/usr/bin/env bash
set -euo pipefail

#MISE hide=true
#
# Core implementation for running OpenTofu tests on modules.
# This is a hidden helper script used by both pre-commit and the `mise run test` task.
#
# Usage:
#   _tofu-test.sh [file1] [file2] ...   # pre-commit mode: dedupe files to modules
#   _tofu-test.sh --module <name>       # direct mode: test a specific module
#
# Test filtering:
#   Pre-commit mode only runs unit/validation tests (files prefixed 01-89) to
#   keep local feedback fast. Integration tests (prefixed 90-99) are skipped.
#   Use `mise run test <module>` or `tofu test` directly to run all tests.

# shellcheck source=.github/scripts/common.sh
source "$(dirname "$0")/../.github/scripts/common.sh"

# Run tests for a single module directory
# Args:
#   $1 - module directory path
#   $2 - "unit-only" to filter to unit tests (01-89), or empty for all tests
run_module_tests() {
  local module_dir="$1"
  local test_mode="${2:-}"

  if [[ ! -d "$module_dir/tests" ]]; then
    log_debug "No tests/ directory in $module_dir, skipping"
    return 0
  fi

  log_info "Testing: $module_dir"

  local filter_args=()
  if [[ "$test_mode" == "unit-only" ]]; then
    # Only run unit/validation tests (01-89), skip integration tests (90-99)
    # Build filter args for each matching test file (paths relative to module dir)
    while IFS= read -r -d '' test_file; do
      # Convert absolute path to relative path from module directory
      local relative_path="${test_file#"$module_dir"/}"
      filter_args+=(-filter="$relative_path")
    done < <(find "$module_dir/tests" -maxdepth 1 -name '[0-8]*.tftest.hcl' -print0 | sort -z)

    if [[ ${#filter_args[@]} -eq 0 ]]; then
      log_debug "No unit tests found (files matching [0-8]*.tftest.hcl), skipping"
      return 0
    fi
    log_debug "Filtering to ${#filter_args[@]} unit test file(s)"
  fi

  set +e
  output=$(cd "$module_dir" && tofu test "${filter_args[@]}" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  if [[ $exit_code -ne 0 ]]; then
    log_error "Tests failed in $module_dir"
    return 1
  else
    log_info "Tests passed in $module_dir"
    return 0
  fi
}

# Extract unique module directories from a list of changed files.
# Only considers paths under modules/<module-name>/, ignoring examples/.
get_changed_modules() {
  local modules=()
  local seen=()

  for file in "$@"; do
    # Match modules/<module-name>/...
    if [[ "$file" =~ ^modules/([^/]+)/ ]]; then
      # Capture immediately before any other regex test overwrites BASH_REMATCH
      local module_name="${BASH_REMATCH[1]}"
      local module_dir="modules/$module_name"

      # Skip examples/ subdirectory
      if [[ "$file" =~ ^modules/[^/]+/examples/ ]]; then
        continue
      fi

      # Check if we've already seen this module
      local already_seen=false
      for s in "${seen[@]+"${seen[@]}"}"; do
        if [[ "$s" == "$module_dir" ]]; then
          already_seen=true
          break
        fi
      done

      if [[ "$already_seen" == false ]]; then
        seen+=("$module_dir")
        # Only include if tests/ directory exists
        if [[ -d "$module_dir/tests" ]]; then
          modules+=("$module_dir")
        fi
      fi
    fi
  done

  printf '%s\n' "${modules[@]+"${modules[@]}"}"
}

main() {
  # Direct module mode: --module <name>
  if [[ "${1:-}" == "--module" ]]; then
    if [[ -z "${2:-}" ]]; then
      log_error "Usage: _tofu-test.sh --module <module-name>"
      exit 1
    fi

    local module_name="$2"
    local module_dir="modules/$module_name"

    if [[ ! -d "$module_dir" ]]; then
      log_error "Module not found: $module_dir"
      exit 1
    fi

    # --module mode runs all tests (including integration)
    run_module_tests "$module_dir" ""
    local result=$?

    if [[ $result -eq 0 ]]; then
      log_summary "Tests passed for $module_name"
    fi
    exit $result
  fi

  # Pre-commit mode: list of files
  if [[ $# -eq 0 ]]; then
    log_debug "No files provided, skipping tests"
    exit 0
  fi

  # Get unique module directories with tests
  mapfile -t modules < <(get_changed_modules "$@")

  if [[ ${#modules[@]} -eq 0 ]]; then
    log_debug "No modules with tests found in changed files"
    exit 0
  fi

  log_info "Running tofu test for ${#modules[@]} module(s) (unit tests only)"

  local failed=0
  for module_dir in "${modules[@]}"; do
    # Pre-commit mode only runs unit tests (skips integration)
    if ! run_module_tests "$module_dir" "unit-only"; then
      failed=1
    fi
  done

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi

  log_summary "All tests passed"

}

main "$@"
