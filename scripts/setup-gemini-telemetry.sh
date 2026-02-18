#!/bin/bash
# setup-gemini-telemetry.sh
# Enables OpenTelemetry local file logging for Gemini CLI
# so that ai-impact-dashboard.py can read token usage data.
#
# Safe to run multiple times (idempotent).

set -e

GEMINI_DIR="$HOME/.gemini"
SETTINGS_FILE="$GEMINI_DIR/settings.json"
TELEMETRY_LOG="$GEMINI_DIR/telemetry.log"

echo "Setting up Gemini CLI telemetry logging..."

# Create .gemini directory if needed
mkdir -p "$GEMINI_DIR"

# If settings.json doesn't exist, create it with telemetry config
if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "telemetry": {
    "enabled": true,
    "exporters": {
      "file": {
        "enabled": true,
        "path": "~/.gemini/telemetry.log"
      }
    }
  }
}
EOF
    echo "Created $SETTINGS_FILE with telemetry config."
else
    # Check if telemetry config already exists
    if python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
tel = data.get('telemetry', {})
exporters = tel.get('exporters', {})
file_exp = exporters.get('file', {})
if file_exp.get('enabled') and file_exp.get('path'):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "Telemetry already configured in $SETTINGS_FILE. No changes needed."
    else
        # Add telemetry config to existing settings
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
data.setdefault('telemetry', {})
data['telemetry']['enabled'] = True
data['telemetry'].setdefault('exporters', {})
data['telemetry']['exporters']['file'] = {
    'enabled': True,
    'path': '~/.gemini/telemetry.log'
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
print('Updated $SETTINGS_FILE with telemetry config.')
"
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
