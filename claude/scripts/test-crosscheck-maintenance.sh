#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-supply-chain-hook.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

HOOK="$TEMP_DIR/preuse-supply-chain-gate.sh"
cat > "$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'ran\n' >> "$GATE_MARKER"
exit 2
HOOK_EOF
chmod +x "$HOOK"

for invalid in empty multiple malformed; do
  SETTINGS="$TEMP_DIR/$invalid.json"
  case "$invalid" in
    empty) : > "$SETTINGS" ;;
    multiple) printf '{}\n{}\n' > "$SETTINGS" ;;
    malformed) printf '{not json\n' > "$SETTINGS" ;;
  esac
  before="$(shasum -a 256 "$SETTINGS" | awk '{print $1}')"
  if "$INSTALLER" "$SETTINGS" "$HOOK" >/dev/null 2>&1; then
    echo "installer unexpectedly accepted $invalid settings" >&2
    exit 1
  fi
  after="$(shasum -a 256 "$SETTINGS" | awk '{print $1}')"
  if [ "$before" != "$after" ]; then
    echo "installer changed $invalid settings" >&2
    exit 1
  fi
done

SETTINGS="$TEMP_DIR/settings.json"
cp "$REPO_ROOT/settings.template.json" "$SETTINGS"
"$INSTALLER" "$SETTINGS" "$HOOK"
COMMAND_COUNT="$(jq -r --arg hook "$HOOK" '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.type == "command" and (.command | contains($hook)))] | length' "$SETTINGS")"
if [ "$COMMAND_COUNT" -ne 1 ]; then
  echo "expected exactly one installed supply-chain hook, found $COMMAND_COUNT" >&2
  exit 1
fi

"$INSTALLER" "$SETTINGS" "$HOOK"
COMMAND_COUNT="$(jq -r --arg hook "$HOOK" '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.type == "command" and (.command | contains($hook)))] | length' "$SETTINGS")"
if [ "$COMMAND_COUNT" -ne 1 ]; then
  echo "reinstall duplicated the supply-chain hook" >&2
  exit 1
fi

INSTALLED_COMMAND="$(jq -r --arg hook "$HOOK" '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.type == "command" and (.command | contains($hook))) | .command' "$SETTINGS")"
if printf '%s' '{"tool_name":"Bash","tool_input":{"command":"npm install"}}' | GATE_MARKER="$TEMP_DIR/invoked" bash -c "$INSTALLED_COMMAND" 2> "$TEMP_DIR/hook.stderr"; then
  echo "installed gate unexpectedly allowed a blocked payload" >&2
  exit 1
else
  STATUS=$?
fi
if [ "$STATUS" -ne 2 ] || [ "$(cat "$TEMP_DIR/invoked")" != "ran" ]; then
  echo "installed gate did not run and preserve its blocking exit status" >&2
  exit 1
fi

grep -Fq 'SUPPLY_CHAIN_INSTALLER="$CROSSCHECK_DIR/claude/scripts/install-supply-chain-hook.sh"' "$REPO_ROOT/scripts/bootstrap-crosscheck.sh"
grep -Fq '"$SUPPLY_CHAIN_INSTALLER" "$HOME/.claude/settings.json" "$SUPPLY_CHAIN_HOOK"' "$REPO_ROOT/scripts/bootstrap-crosscheck.sh"

SYNC_ROOT="$TEMP_DIR/crosscheck"
HOME_FIXTURE="$TEMP_DIR/home"
mkdir -p "$SYNC_ROOT/claude/skill-sources" "$SYNC_ROOT/skill-sources" "$HOME_FIXTURE/.claude/commands" "$HOME_FIXTURE/.crosscheck"
printf 'Claude-specific managed command\n' > "$SYNC_ROOT/claude/skill-sources/managed.md"
printf 'Root command source\n' > "$SYNC_ROOT/skill-sources/managed.md"
printf 'Claude-specific linked command\n' > "$SYNC_ROOT/claude/skill-sources/linked.md"
printf 'Root linked command\n' > "$SYNC_ROOT/skill-sources/linked.md"
printf 'Claude-only new command\n' > "$SYNC_ROOT/claude/skill-sources/new-command.md"
printf 'skip-me\n' > "$SYNC_ROOT/claude/skill-sources/skipped.md"
printf 'Root command source\n' > "$HOME_FIXTURE/.claude/commands/managed.md"
ln -s "$SYNC_ROOT/skill-sources/linked.md" "$HOME_FIXTURE/.claude/commands/linked.md"
printf 'user-owned command\n' > "$HOME_FIXTURE/.claude/commands/custom.md"
printf 'skipped\n' > "$HOME_FIXTURE/.crosscheck/skip-skills"
CROSSCHECK_DIR="$SYNC_ROOT" "$REPO_ROOT/claude/scripts/sync-managed-claude-skills.sh" "$HOME_FIXTURE" >/dev/null

if [ ! -L "$HOME_FIXTURE/.claude/commands/managed.md" ] || [ "$(cat "$HOME_FIXTURE/.claude/commands/managed.md")" != "Claude-specific managed command" ]; then
  echo "managed Claude copy was not refreshed from the Claude mirror" >&2
  exit 1
fi
EXPECTED_LINK="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SYNC_ROOT/claude/skill-sources/linked.md")"
if [ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$HOME_FIXTURE/.claude/commands/linked.md")" != "$EXPECTED_LINK" ]; then
  echo "managed root symlink was not redirected to the Claude mirror" >&2
  exit 1
fi
if [ ! -L "$HOME_FIXTURE/.claude/commands/new-command.md" ] || [ -e "$HOME_FIXTURE/.claude/commands/skipped.md" ]; then
  echo "new or skipped Claude command handling was incorrect" >&2
  exit 1
fi
if [ -L "$HOME_FIXTURE/.claude/commands/custom.md" ] || [ "$(cat "$HOME_FIXTURE/.claude/commands/custom.md")" != "user-owned command" ]; then
  echo "user-owned Claude command was overwritten" >&2
  exit 1
fi

echo "CrossCheck maintenance tests passed"
