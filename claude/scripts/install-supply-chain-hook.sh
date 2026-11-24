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
SETTINGS_ROOT="$(dirname "$SETTINGS_TARGET")"
SETTINGS_RELATIVE="$(basename "$SETTINGS_TARGET")"
if stat -c '%a' "$SETTINGS_TARGET" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_TARGET")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_TARGET")"
fi

HOOK_RUNNER='CROSSCHECK_SUPPLY_CHAIN_GATE_V1=1; hook=$1; if [[ ! -x "$hook" ]]; then printf "Claude supply-chain gate unavailable or non-executable: %s\\n" "$hook" >&2; exit 2; fi; if bash "$hook"; then status=0; else status=$?; fi; if [[ "$status" -ne 0 && "$status" -ne 2 ]]; then printf "Claude supply-chain gate failed (%d): %s\\n" "$status" "$hook" >&2; exit 2; fi; exit "$status"'
printf -v HOOK_COMMAND 'bash -c %q -- %q' "$HOOK_RUNNER" "$HOOK_FILE"
PUBLISH_HELPER="$(cd "$(dirname "$0")/../.." && pwd)/scripts/atomic-publish-file.py"
SETTINGS_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-snapshot.XXXXXX")"
TEMP_FILE=""
PUBLISH_STARTED=0
cleanup_hook_stages() {
  local exit_status=$?
  trap - EXIT
  if [ "$PUBLISH_STARTED" -eq 0 ]; then
    python3 "$PUBLISH_HELPER" snapshot-cleanup "$SETTINGS_SNAPSHOT" || true
  fi
  rm -f "$TEMP_FILE" "$SETTINGS_SNAPSHOT" "$SETTINGS_SNAPSHOT.crosscheck-identity"
  exit "$exit_status"
}
trap cleanup_hook_stages EXIT
if ! python3 "$PUBLISH_HELPER" snapshot "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SETTINGS_SNAPSHOT" --private; then
  echo "Claude settings changed or became unsafe while it was being read: $SETTINGS_FILE" >&2
  exit 1
fi

# Work from one private snapshot and refuse to publish if another process
# changes the live settings while validation is running.
if ! jq -s -e '
  length == 1 and
  (.[0] | type == "object" and
    ((has("permissions") | not) or (.permissions | type == "object")) and
    ((.permissions | has("deny") | not) or (.permissions.deny | type == "array")) and
    ((has("hooks") | not) or (.hooks | type == "object")) and
    ((.hooks | has("PreToolUse") | not) or (.hooks.PreToolUse | type == "array")) and
    ((has("PreToolUse") | not) or (.PreToolUse | type == "array")))
' "$SETTINGS_SNAPSHOT" >/dev/null; then
  echo "Claude settings file must contain exactly one valid JSON object: $SETTINGS_FILE" >&2
  exit 1
fi

TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-stage.XXXXXX")"

if ! jq --arg hook "$HOOK_COMMAND" --argjson rules '[
  "Bash(gh*--admin*)",
  "Bash(*--admin*)",
  "Bash(gh api*rulesets*)",
  "Bash(gh api*branches/*/protection*)",
  "Bash(*graphql*BranchProtection*)",
  "Bash(*graphql*Ruleset*)"
]' '
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
  . as $root |
  (($root.hooks // {}) as $hooks | (($hooks.PreToolUse // []) + ($root.PreToolUse // []))) as $pre_tool_use |
  (($root.permissions // {}) | .deny // []) as $existing_deny |
  (reduce $rules[] as $rule ($existing_deny; if index($rule) == null then . + [$rule] else . end)) as $deny |
  ($root.hooks // {}) as $hooks |
  $root
  | .permissions = ((.permissions // {}) + {"deny":$deny})
  | .hooks = ($hooks + {"PreToolUse":($pre_tool_use | install_hook($hook))})
  | del(.PreToolUse)
' "$SETTINGS_SNAPSHOT" > "$TEMP_FILE"; then
  echo "Could not update Claude settings in $SETTINGS_FILE" >&2
  exit 1
fi

if ! jq -s -e --arg hook "$HOOK_COMMAND" --argjson rules '[
  "Bash(gh*--admin*)",
  "Bash(*--admin*)",
  "Bash(gh api*rulesets*)",
  "Bash(gh api*branches/*/protection*)",
  "Bash(*graphql*BranchProtection*)",
  "Bash(*graphql*Ruleset*)"
]' '
  length == 1 and
  (.[0] |
    . as $settings |
    ((has("PreToolUse") | not)) and
    ($settings.hooks.PreToolUse | any(.[]; .matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == $hook))) and
    all($rules[]; . as $rule | $settings.permissions.deny | index($rule) != null))
' "$TEMP_FILE" >/dev/null; then
  echo "Claude supply-chain hook or critical deny rules were missing from generated settings: $SETTINGS_FILE" >&2
  exit 1
fi

CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Claude settings path changed while the supply-chain hook was being installed; refusing to update: $SETTINGS_FILE" >&2
  exit 1
fi
PUBLISH_STARTED=1
if ! python3 "$PUBLISH_HELPER" publish "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SETTINGS_SNAPSHOT" "$TEMP_FILE" "$SETTINGS_MODE"; then
  exit 1
fi
CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Claude settings path changed during the supply-chain hook update: $SETTINGS_FILE" >&2
  exit 1
fi
