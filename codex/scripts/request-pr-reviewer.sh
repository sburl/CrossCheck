#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  exec "$SCRIPT_DIR/../../scripts/request-pr-reviewer.sh" "$@"
else
  source "$SCRIPT_DIR/../../scripts/request-pr-reviewer.sh" "$@"
fi
