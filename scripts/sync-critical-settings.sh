#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${1:?usage: sync-critical-settings.sh SETTINGS_FILE [--include-ask]}"
INCLUDE_ASK="${2:-}"
if [ -n "$INCLUDE_ASK" ] && [ "$INCLUDE_ASK" != "--include-ask" ]; then
  echo "usage: sync-critical-settings.sh SETTINGS_FILE [--include-ask]" >&2
  exit 2
fi
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Settings file not found: $SETTINGS_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PUBLISH_HELPER="$SCRIPT_DIR/atomic-publish-file.py"
if [ ! -f "$PUBLISH_HELPER" ]; then
  PUBLISH_HELPER="$(cd "$SCRIPT_DIR/../.." && pwd -P)/scripts/atomic-publish-file.py"
fi
SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
SETTINGS_ROOT="$(dirname "$SETTINGS_TARGET")"
SETTINGS_RELATIVE="$(basename "$SETTINGS_TARGET")"
if stat -c '%a' "$SETTINGS_TARGET" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_TARGET")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_TARGET")"
fi

SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-snapshot.XXXXXX")"
STAGED="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-stage.XXXXXX")"
trap 'rm -f "$SNAPSHOT" "$STAGED"' EXIT
if ! python3 "$PUBLISH_HELPER" snapshot "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SNAPSHOT"; then
  echo "Settings changed or became unsafe while it was being read: $SETTINGS_FILE" >&2
  exit 1
fi

if ! jq -s -e '
  length == 1 and
  (.[0] | type == "object" and
    ((has("permissions") | not) or (.permissions | type == "object")) and
    ((.permissions | has("deny") | not) or (.permissions.deny | type == "array")) and
    ((.permissions | has("ask") | not) or (.permissions.ask | type == "array")))
' "$SNAPSHOT" >/dev/null; then
  echo "Settings must contain exactly one valid JSON object: $SETTINGS_FILE" >&2
  exit 1
fi

if [ "$INCLUDE_ASK" = "--include-ask" ]; then
  jq --argjson rules '[
    "Bash(gh*--admin*)",
    "Bash(*--admin*)",
    "Bash(gh api*rulesets*)",
    "Bash(gh api*branches/*/protection*)",
    "Bash(*graphql*BranchProtection*)",
    "Bash(*graphql*Ruleset*)"
  ]' '
    .permissions = (.permissions // {}) |
    .permissions.deny = reduce $rules[] as $rule (.permissions.deny // []; if index($rule) == null then . + [$rule] else . end) |
    .permissions.ask = ((.permissions.ask // []) | if index("Bash(gh api *)") == null then . + ["Bash(gh api *)"] else . end)
  ' "$SNAPSHOT" > "$STAGED"
else
  jq --argjson rules '[
    "Bash(gh*--admin*)",
    "Bash(*--admin*)",
    "Bash(gh api*rulesets*)",
    "Bash(gh api*branches/*/protection*)",
    "Bash(*graphql*BranchProtection*)",
    "Bash(*graphql*Ruleset*)"
  ]' '
    .permissions = (.permissions // {}) |
    .permissions.deny = reduce $rules[] as $rule (.permissions.deny // []; if index($rule) == null then . + [$rule] else . end)
  ' "$SNAPSHOT" > "$STAGED"
fi

chmod "$SETTINGS_MODE" "$STAGED"
CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Settings path changed during CrossCheck update; refusing to publish: $SETTINGS_FILE" >&2
  exit 1
fi
python3 "$PUBLISH_HELPER" publish "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SNAPSHOT" "$STAGED" "$SETTINGS_MODE"
CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Settings path changed during CrossCheck update: $SETTINGS_FILE" >&2
  exit 1
fi
echo "Updated CrossCheck critical deny rules in $SETTINGS_FILE"
