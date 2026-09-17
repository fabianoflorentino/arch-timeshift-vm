#!/usr/bin/env bash
#
# Source this file before running test tooling by hand:
#
#   source scripts/test-env.sh
#   molecule test -s default
#
# It makes the test tooling use the local Docker daemon (instead of the
# remote `homeserver` context) and a local Docker config that bypasses the
# broken "desktop" credential store in ~/.docker/config.json.
#
# Works when sourced from either bash or zsh.
if [ -n "${BASH_SOURCE:-}" ]; then
  _self="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _self="${(%):-%N}"
else
  _self="$0"
fi
project_dir="$(cd "$(dirname "$_self")/.." && pwd)"
unset _self

export DOCKER_CONFIG="${DOCKER_CONFIG:-$project_dir/.docker}"
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"
export PATH="$project_dir/.venv/bin:$PATH"
export ANSIBLE_PYTHON_INTERPRETER="${ANSIBLE_PYTHON_INTERPRETER:-$project_dir/.venv/bin/python}"

mkdir -p "$DOCKER_CONFIG"
if [ ! -f "$DOCKER_CONFIG/config.json" ]; then
  printf '{}' > "$DOCKER_CONFIG/config.json"
fi

echo "test-env: DOCKER_HOST=$DOCKER_HOST DOCKER_CONFIG=$DOCKER_CONFIG"
