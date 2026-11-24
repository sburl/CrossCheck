#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="${1:?usage: sync-critical-settings.sh SETTINGS_FILE [--include-ask]}"
shift
INCLUDE_ASK=""
STRICT_ROOT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-ask)
      if [ -n "$INCLUDE_ASK" ]; then
        echo "--include-ask may be specified only once" >&2
        exit 2
      fi
      INCLUDE_ASK="$1"
      ;;
    --strict-root)
      if [ "$STRICT_ROOT" -eq 1 ]; then
        echo "--strict-root may be specified only once" >&2
        exit 2
      fi
      STRICT_ROOT=1
      ;;
    *)
      echo "usage: sync-critical-settings.sh SETTINGS_FILE [--include-ask] [--strict-root]" >&2
      exit 2
      ;;
  esac
  shift
done
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Settings file not found: $SETTINGS_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PUBLISH_HELPER="$SCRIPT_DIR/atomic-publish-file.py"
if [ ! -f "$PUBLISH_HELPER" ]; then
  PUBLISH_HELPER="$(cd "$SCRIPT_DIR/../.." && pwd -P)/scripts/atomic-publish-file.py"
fi
if [ "$STRICT_ROOT" -eq 1 ]; then
  SETTINGS_TARGET="$(python3 -c 'import os,sys; p=os.path.abspath(sys.argv[1]); r=os.path.dirname(p); print(os.path.join(os.path.realpath(os.path.dirname(r)), os.path.basename(r), os.path.basename(p)))' "$SETTINGS_FILE")"
else
  SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
fi
SETTINGS_ROOT="$(dirname "$SETTINGS_TARGET")"
SETTINGS_RELATIVE="$(basename "$SETTINGS_TARGET")"
if stat -c '%a' "$SETTINGS_TARGET" >/dev/null 2>&1; then
  SETTINGS_MODE="$(stat -c '%a' "$SETTINGS_TARGET")"
else
  SETTINGS_MODE="$(stat -f '%Lp' "$SETTINGS_TARGET")"
fi

SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-snapshot.XXXXXX")"
STAGED="$(mktemp "${TMPDIR:-/tmp}/crosscheck-settings-stage.XXXXXX")"
python3 "$PUBLISH_HELPER" private-file "$STAGED"
PUBLISH_STARTED=0
cleanup_settings_stages() {
  local exit_status=$?
  trap - EXIT
  if [ "$PUBLISH_STARTED" -eq 0 ]; then
    python3 "$PUBLISH_HELPER" snapshot-cleanup "$SNAPSHOT" || true
  fi
  rm -f "$SNAPSHOT" "$SNAPSHOT.crosscheck-identity" "$STAGED"
  exit "$exit_status"
}
trap cleanup_settings_stages EXIT
SNAPSHOT_OPTIONS=(--private)
PUBLISH_OPTIONS=()
if [ "$STRICT_ROOT" -eq 1 ]; then
  SNAPSHOT_OPTIONS+=(--strict-root)
  PUBLISH_OPTIONS+=(--strict-root)
fi
if ! python3 "$PUBLISH_HELPER" snapshot "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SNAPSHOT" "${SNAPSHOT_OPTIONS[@]}"; then
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

CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Settings path changed during CrossCheck update; refusing to publish: $SETTINGS_FILE" >&2
  exit 1
fi
if cmp -s <(jq -S -c . "$SNAPSHOT") <(jq -S -c . "$STAGED"); then
  echo "CrossCheck critical deny rules are already current in $SETTINGS_FILE"
  exit 0
fi
PUBLISH_STARTED=1
python3 "$PUBLISH_HELPER" publish "$SETTINGS_ROOT" "$SETTINGS_RELATIVE" "$SNAPSHOT" "$STAGED" "$SETTINGS_MODE" "${PUBLISH_OPTIONS[@]}"
CURRENT_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SETTINGS_FILE")"
if [ "$CURRENT_TARGET" != "$SETTINGS_TARGET" ]; then
  echo "Settings path changed during CrossCheck update: $SETTINGS_FILE" >&2
  exit 1
fi
echo "Updated CrossCheck critical deny rules in $SETTINGS_FILE"
