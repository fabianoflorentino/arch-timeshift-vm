#!/usr/bin/env bash
#
# Syntax-check the restore playbook. Run via `make syntax`.
set -euo pipefail

cd "$(dirname "$0")/.."
exec ansible-playbook playbooks/restore.yml --syntax-check "$@"
