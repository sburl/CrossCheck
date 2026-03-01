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
    "target": "local",
    "outfile": "~/.gemini/telemetry.log"
  }
}
EOF
    echo "Created $SETTINGS_FILE with telemetry config."
else
    # Check if telemetry config already exists and is correct
    if SETTINGS_FILE="$SETTINGS_FILE" python3 -c "
import json, sys, os
settings_file = os.environ['SETTINGS_FILE']
with open(settings_file) as f:
    data = json.load(f)
tel = data.get('telemetry', {})
if tel.get('enabled') and tel.get('target') == 'local' and tel.get('outfile'):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "Telemetry already configured in $SETTINGS_FILE. No changes needed."
    else
        # Add telemetry config to existing settings, removing old 'exporters' if present
        SETTINGS_FILE="$SETTINGS_FILE" python3 -c "
import json, os
settings_file = os.environ['SETTINGS_FILE']
with open(settings_file) as f:
    data = json.load(f)
data.setdefault('telemetry', {})
data['telemetry']['enabled'] = True
data['telemetry']['target'] = 'local'
data['telemetry']['outfile'] = '~/.gemini/telemetry.log'
# Remove old/invalid exporters key if it exists
if 'exporters' in data['telemetry']:
    del data['telemetry']['exporters']
with open(settings_file, 'w') as f:
    json.dump(data, f, indent=2)
print(f'Updated {settings_file} with telemetry config.')
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
