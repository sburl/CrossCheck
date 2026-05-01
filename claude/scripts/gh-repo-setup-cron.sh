#!/usr/bin/env bash
# Cron job: ensure sburl repos are protected and optionally invite bot.
#
# Install as a daily cron job:
#   0 8 * * * /path/to/gh-repo-setup-cron.sh >> ~/.local/bin/gh-repo-setup.log 2>&1
#
# Requires: gh (authenticated), jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../scripts/gh-repo-setup-cron.sh"
