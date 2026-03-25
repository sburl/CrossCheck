#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  exec "$SCRIPT_DIR/../../scripts/codex-commit-review.sh" "$@"
else
  source "$SCRIPT_DIR/../../scripts/codex-commit-review.sh" "$@"
fi
