#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${1:?usage: install-supply-chain-hook.sh SETTINGS_FILE HOOK_FILE}"
HOOK_FILE="${2:?usage: install-supply-chain-hook.sh SETTINGS_FILE HOOK_FILE}"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Claude settings file not found: $SETTINGS_FILE" >&2
  exit 1
fi
if [ ! -x "$HOOK_FILE" ]; then
  echo "Supply-chain hook is missing or non-executable: $HOOK_FILE" >&2
  exit 1
fi

if stat -c '%a' "$SETTINGS_FILE" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_FILE")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_FILE")"
fi
printf -v HOOK_COMMAND 'bash %q' "$HOOK_FILE"
TEMP_FILE="${SETTINGS_FILE}.tmp.$$"
trap 'rm -f "$TEMP_FILE"' EXIT

if ! jq --arg hook "$HOOK_COMMAND" '
  def is_supply_chain_hook:
    ((.command // "") | contains("preuse-supply-chain-gate.sh"));
  def install_hook($command):
    if any(.[]?; any(.hooks[]?; is_supply_chain_hook)) then
      map(
        if any(.hooks[]?; is_supply_chain_hook) then
          .hooks |= map(if is_supply_chain_hook then .command = $command else . end)
        else . end
      )
    else
      . + [{"matcher":"Bash","hooks":[{"type":"command","command":$command}]}]
    end;
  if (.hooks | type) == "object" then
    .hooks.PreToolUse = ((.hooks.PreToolUse // []) | install_hook($hook))
  elif (.PreToolUse | type) == "array" then
    .PreToolUse |= install_hook($hook)
  else
    .hooks = ((.hooks // {}) + {"PreToolUse": ([] | install_hook($hook))})
  end
' "$SETTINGS_FILE" > "$TEMP_FILE"; then
  echo "Could not add the Claude supply-chain hook to $SETTINGS_FILE" >&2
  exit 1
fi

chmod "$SETTINGS_MODE" "$TEMP_FILE"
mv "$TEMP_FILE" "$SETTINGS_FILE"
trap - EXIT
