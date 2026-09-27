#!/usr/bin/env bash

#MISE description="Bootstrap a new shared module using cookiecutter"

set -euo pipefail

TEMPLATE="cookiecutter/templates/shared-module"

if [ ! -f "$TEMPLATE/cookiecutter.json" ]; then
  echo "[INFO] Initializing the cookiecutter submodule"
  git submodule update --init cookiecutter
fi

if [ ! -f "$TEMPLATE/cookiecutter.json" ]; then
  echo "[ERROR] $TEMPLATE not found in the cookiecutter submodule. Bump it to a commit that has the template: git submodule update --remote cookiecutter" >&2
  exit 1
fi

# The repo-root mise.toml pins the OpenTofu floor; offer it as the default so
# new modules target the floor instead of whatever the template defaults to.
cookiecutter "$TEMPLATE" -o modules opentofu_version="$(mise current opentofu)"
