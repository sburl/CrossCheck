#!/usr/bin/env bash
# setup-gemini-telemetry.sh
# Delegates to the shared CrossCheck script in root scripts/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../scripts/setup-gemini-telemetry.sh"
