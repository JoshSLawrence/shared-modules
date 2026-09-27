#!/usr/bin/env bash

#MISE description="Run OpenTofu tests for a module"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
  echo "Usage: mise run test <module-name>"
  echo ""
  echo "Available modules with tests:"
  for dir in modules/*/tests; do
    if [[ -d "$dir" ]]; then
      module_name=$(basename "$(dirname "$dir")")
      echo "  - $module_name"
    fi
  done
  exit 1
fi

"$SCRIPT_DIR/_tofu-test.sh" --module "$1"
