#!/bin/bash
# setup-gemini-telemetry.sh
# Enables OpenTelemetry local file logging for Gemini CLI
# so that ai-impact-dashboard.py can read token usage data.
#
# Safe to run multiple times (idempotent).

set -euo pipefail

GEMINI_DIR="$HOME/.gemini"
SETTINGS_FILE="$GEMINI_DIR/settings.json"
TELEMETRY_LOG="$GEMINI_DIR/telemetry.log"

echo "Setting up Gemini CLI telemetry logging..."

# Create .gemini directory if needed
mkdir -p "$GEMINI_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to manage $SETTINGS_FILE"
  exit 1
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" << EOF
{
  "telemetry": {
    "enabled": true,
    "target": "local",
    "outfile": "$HOME/.gemini/telemetry.log"
  }
}
EOF
  echo "Created $SETTINGS_FILE with telemetry config."
else
  if SETTINGS_FILE="$SETTINGS_FILE" HOME_DIR="$HOME" python3 <<'PY'
import json
import os
import sys

settings_file = os.environ["SETTINGS_FILE"]
home_dir = os.environ["HOME_DIR"]
expected_outfile = os.path.join(home_dir, ".gemini", "telemetry.log")

try:
    with open(settings_file) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

if not isinstance(data, dict):
    sys.exit(1)

telemetry = data.get("telemetry", {})
if not isinstance(telemetry, dict):
    sys.exit(1)

if (
    telemetry.get("enabled") is True
    and telemetry.get("target") == "local"
    and telemetry.get("outfile") == expected_outfile
):
    sys.exit(0)
sys.exit(1)
PY
 then
  echo "Telemetry already configured with expected path in $SETTINGS_FILE. No changes needed."
else
  cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak.$(date +%s)"
  echo "Telemetry settings are invalid or stale in $SETTINGS_FILE. Backing up and rebuilding..."
  if SETTINGS_FILE="$SETTINGS_FILE" HOME_DIR="$HOME" python3 <<'PY'
import json
import os
import sys
import tempfile

settings_file = os.environ["SETTINGS_FILE"]
home_dir = os.environ["HOME_DIR"]

try:
    with open(settings_file) as f:
        data = json.load(f)
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

telemetry = data.get("telemetry", {})
if not isinstance(telemetry, dict):
    telemetry = {}

telemetry["enabled"] = True
telemetry["target"] = "local"
telemetry["outfile"] = os.path.join(home_dir, ".gemini", "telemetry.log")

legacy_exporters = telemetry.get("exporters")
if isinstance(legacy_exporters, dict):
    file_exporter = legacy_exporters.get("file", {})
    if isinstance(file_exporter, dict) and file_exporter.get("path"):
        telemetry.pop("exporters", None)

data["telemetry"] = telemetry

orig_mode = 0o600
if os.path.exists(settings_file):
    orig_mode = os.stat(settings_file).st_mode & 0o777

fd, tmp_path = tempfile.mkstemp(prefix=".gemini_settings.", dir=os.path.dirname(settings_file))
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(tmp_path, orig_mode)
os.replace(tmp_path, settings_file)
PY
 then
    echo "Updated $SETTINGS_FILE with telemetry config."
  else
    echo "ERROR: Failed to parse or write $SETTINGS_FILE" >&2
    exit 1
  fi
fi

fi

# Touch the telemetry log so it exists
touch "$TELEMETRY_LOG"

echo ""
echo "Gemini CLI telemetry setup complete."
echo "  Config: $SETTINGS_FILE"
echo "  Log:    $TELEMETRY_LOG"
echo ""
echo "Future Gemini CLI sessions will log token usage to the log file."
echo "Note: Historical data cannot be backfilled - only new sessions will be tracked."
