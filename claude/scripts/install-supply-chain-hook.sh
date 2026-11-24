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
if ! jq -s -e 'length == 1 and (.[0] | type == "object")' "$SETTINGS_FILE" >/dev/null; then
  echo "Claude settings file must contain exactly one JSON object: $SETTINGS_FILE" >&2
  exit 1
fi

SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if stat -c '%a' "$SETTINGS_TARGET" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_TARGET")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_TARGET")"
fi

HOOK_RUNNER='CROSSCHECK_SUPPLY_CHAIN_GATE_V1=1; hook=$1; if [[ ! -x "$hook" ]]; then printf "Claude supply-chain gate unavailable or non-executable: %s\\n" "$hook" >&2; exit 2; fi; if bash "$hook"; then status=0; else status=$?; fi; if [[ "$status" -ne 0 && "$status" -ne 2 ]]; then printf "Claude supply-chain gate failed (%d): %s\\n" "$status" "$hook" >&2; exit 2; fi; exit "$status"'
printf -v HOOK_COMMAND 'bash -c %q -- %q' "$HOOK_RUNNER" "$HOOK_FILE"
TEMP_FILE="${SETTINGS_TARGET}.tmp.$$"
trap 'rm -f "$TEMP_FILE"' EXIT

if ! jq --arg hook "$HOOK_COMMAND" '
  def is_supply_chain_hook:
    .type == "command" and ((.command // "") as $command |
      (($command | startswith("for c in ") and contains("preuse-supply-chain-gate.sh") and (contains("CrossCheck supply-chain hook not found") or contains("done; exit 0"))) or
       ($command | contains("preuse-supply-chain-gate.sh") and ((contains("CROSSCHECK_SUPPLY_CHAIN_GATE_V1=1")) or (contains("bash -c") and contains("unavailable") and contains("non-executable:")))))
    );
  def install_hook($command):
    (reduce .[] as $entry ({found:false, entries:[]};
      if $entry.matcher != "Bash" then
        .entries += [$entry]
      else
        ($entry.hooks // []) as $hooks |
        ($hooks | map(select(is_supply_chain_hook))) as $managed |
        ($hooks | map(select(is_supply_chain_hook | not))) as $other |
        if ($managed | length) > 0 then
          if .found then
            if ($other | length) > 0 then
              .entries += [($entry | .hooks = $other)]
            else . end
          else
            .found = true | .entries += [($entry | .hooks = ($other + [($managed[0] | .command = $command)]))]
          end
        elif .found then
          .entries += [$entry]
        else
          .found = true | .entries += [($entry | .hooks = ($hooks + [{"type":"command","command":$command}]))]
        end
      end
    )) as $result |
    if $result.found then
      $result.entries
    else
      $result.entries + [{"matcher":"Bash","hooks":[{"type":"command","command":$command}]}]
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

if ! jq -s -e --arg hook "$HOOK_COMMAND" '
  length == 1 and
  (.[0] |
    (if (.hooks | type) == "object" then (.hooks.PreToolUse // []) else (.PreToolUse // []) end) |
    any(.[]; .matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == $hook)))
' "$TEMP_FILE" >/dev/null; then
  echo "Claude supply-chain hook was not present in the generated settings: $SETTINGS_FILE" >&2
  exit 1
fi

chmod "$SETTINGS_MODE" "$TEMP_FILE"
mv "$TEMP_FILE" "$SETTINGS_TARGET"
trap - EXIT
