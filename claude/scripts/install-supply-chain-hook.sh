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

SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if stat -c '%a' "$SETTINGS_TARGET" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_TARGET")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_TARGET")"
fi

HOOK_RUNNER='hook=$1; if [[ ! -x "$hook" ]]; then printf "Claude supply-chain gate unavailable or non-executable: %s\\n" "$hook" >&2; exit 2; fi; if bash "$hook"; then status=0; else status=$?; fi; if [[ "$status" -ne 0 && "$status" -ne 2 ]]; then printf "Claude supply-chain gate failed (%d): %s\\n" "$status" "$hook" >&2; exit 2; fi; exit "$status"'
printf -v HOOK_COMMAND 'bash -c %q -- %q' "$HOOK_RUNNER" "$HOOK_FILE"
TEMP_FILE="${SETTINGS_TARGET}.tmp.$$"
trap 'rm -f "$TEMP_FILE"' EXIT

if ! jq --arg hook "$HOOK_COMMAND" '
  def is_supply_chain_hook:
    .type == "command" and (
      ((.command // "") | startswith("for c in ") and contains("preuse-supply-chain-gate.sh") and contains("CrossCheck supply-chain hook not found")) or
      ((.command // "") | startswith("hook=$1; if [[ ! -x \"$hook\" ]]; then") and contains("preuse-supply-chain-gate.sh") and contains("bash \"$hook\""))
    );
  def install_hook($command):
    if any(.[]?; .matcher == "Bash" and any(.hooks[]?; is_supply_chain_hook)) then
      map(
        if .matcher == "Bash" then
          .hooks |= map(if is_supply_chain_hook then .command = $command else . end)
        else . end
      )
    elif any(.[]?; .matcher == "Bash") then
      reduce .[] as $entry ([];
        if $entry.matcher == "Bash" and (any(.[]; .matcher == "Bash") | not) then
          . + [$entry + {"hooks": (($entry.hooks // []) + [{"type":"command","command":$command}])}]
        else . + [$entry] end
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
mv "$TEMP_FILE" "$SETTINGS_TARGET"
trap - EXIT
