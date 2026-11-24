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

for invalid in empty multiple malformed legacy-wrong-type nested-wrong-type deny-wrong-type; do
  SETTINGS="$TEMP_DIR/$invalid.json"
  case "$invalid" in
    empty) : > "$SETTINGS" ;;
    multiple) printf '{}\n{}\n' > "$SETTINGS" ;;
    malformed) printf '{not json\n' > "$SETTINGS" ;;
    legacy-wrong-type) printf '{"PreToolUse":{}}\n' > "$SETTINGS" ;;
    nested-wrong-type) printf '{"hooks":{"PreToolUse":{}}}\n' > "$SETTINGS" ;;
    deny-wrong-type) printf '{"permissions":{"deny":{}}}\n' > "$SETTINGS" ;;
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
if jq -e '
  has("PreToolUse") or
  (.permissions.deny as $deny | [
    "Bash(gh*--admin*)", "Bash(*--admin*)", "Bash(gh api*rulesets*)",
    "Bash(gh api*branches/*/protection*)", "Bash(*graphql*BranchProtection*)",
    "Bash(*graphql*Ruleset*)"
  ] | all(.[]; . as $rule | $deny | index($rule) != null) | not)
' "$SETTINGS" >/dev/null; then
  echo "installer left the legacy hook key or omitted critical deny rules" >&2
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

# Legacy top-level PreToolUse is migrated into Claude's nested schema.
LEGACY_SETTINGS="$TEMP_DIR/legacy-settings.json"
printf '{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo legacy"}]}]}\n' > "$LEGACY_SETTINGS"
"$INSTALLER" "$LEGACY_SETTINGS" "$HOOK"
if ! jq -e 'has("PreToolUse") | not' "$LEGACY_SETTINGS" >/dev/null || ! jq -e '.hooks.PreToolUse | any(.[]; .matcher == "Bash" and any(.hooks[]?; .command == "echo legacy"))' "$LEGACY_SETTINGS" >/dev/null; then
  echo "installer did not preserve legacy entries in nested Claude settings" >&2
  exit 1
fi

# An aliased settings file keeps both the link and target mode.
REAL_SETTINGS="$TEMP_DIR/real-settings.json"
LINKED_SETTINGS="$TEMP_DIR/linked-settings.json"
printf '{"permissions":{"deny":[]}}\n' > "$REAL_SETTINGS"
chmod 0640 "$REAL_SETTINGS"
ln -s "$REAL_SETTINGS" "$LINKED_SETTINGS"
"$INSTALLER" "$LINKED_SETTINGS" "$HOOK"
if [ ! -L "$LINKED_SETTINGS" ] || [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$REAL_SETTINGS")" != "0o640" ]; then
  echo "installer replaced a settings symlink or changed its mode" >&2
  exit 1
fi

for bootstrap in root claude; do
  BOOTSTRAP_REPO="$TEMP_DIR/workspace/$bootstrap/CrossCheck"
  BOOTSTRAP_HOME="$TEMP_DIR/home-$bootstrap"
  mkdir -p "$(dirname "$BOOTSTRAP_REPO")" "$BOOTSTRAP_HOME"
  python3 - "$REPO_ROOT" "$BOOTSTRAP_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
  mkdir -p "$BOOTSTRAP_HOME/.claude"

  if [ "$bootstrap" = root ]; then
    SCRIPT="$BOOTSTRAP_REPO/scripts/bootstrap-crosscheck.sh"
  else
    SCRIPT="$BOOTSTRAP_REPO/claude/scripts/bootstrap-crosscheck.sh"
  fi

  BOOTSTRAP_HOME="$BOOTSTRAP_HOME" BOOTSTRAP_SCRIPT="$SCRIPT" python3 <<'PY'
import os
import pty
import select
import signal
import sys
import time

home = os.environ["BOOTSTRAP_HOME"]
script = os.environ["BOOTSTRAP_SCRIPT"]
pid, fd = pty.fork()
if pid == 0:
    env = os.environ.copy()
    env["HOME"] = home
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    os.execve("/bin/bash", ["bash", script], env)

output = bytearray()
sent_prompts = set()
prompt_fragments = [
    b"Install git hooks globally (all repos)? (Y/n)",
    b"Install Codex review hooks globally? (Y/n)",
    b"Install Claude review hooks globally? (Y/n)",
    b"Install TokenPrint (AI usage dashboard)? (Y/n)",
]
deadline = time.monotonic() + 90
status = None
while time.monotonic() < deadline:
    readable, _, _ = select.select([fd], [], [], 0.2)
    if readable:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            chunk = b""
        if chunk:
            output.extend(chunk)
            for index, prompt in enumerate(prompt_fragments):
                if index not in sent_prompts and prompt in output:
                    os.write(fd, b"n\n")
                    sent_prompts.add(index)
    try:
        waited, wait_status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        waited = pid
        wait_status = status or 0
    if waited == pid:
        status = wait_status
        break
if status is None:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    sys.stderr.write(output.decode(errors="replace"))
    raise SystemExit("bootstrap timed out while testing its isolated entry point")
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    sys.stderr.write(output.decode(errors="replace"))
    raise SystemExit(f"bootstrap exited unsuccessfully: {status}")
PY

  SETTINGS="$BOOTSTRAP_HOME/.claude/settings.json"
  jq -e '
    (.hooks.PreToolUse | type == "array") and
    (.permissions.deny as $deny | [
      "Bash(gh*--admin*)", "Bash(*--admin*)", "Bash(gh api*rulesets*)",
      "Bash(gh api*branches/*/protection*)", "Bash(*graphql*BranchProtection*)",
      "Bash(*graphql*Ruleset*)"
    ] | all(.[]; . as $rule | $deny | index($rule) != null))
  ' "$SETTINGS" >/dev/null
  [ -f "$SETTINGS" ]
  [ ! -L "$SETTINGS" ]
  jq -e 'has("PreToolUse") | not' "$SETTINGS" >/dev/null
  COMMAND_LINK="$BOOTSTRAP_HOME/.claude/commands/update-crosscheck.md"
  EXPECTED_COMMAND="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BOOTSTRAP_REPO/claude/skill-sources/update-crosscheck.md")"
  ACTUAL_COMMAND="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$COMMAND_LINK")"
  if [ ! -L "$COMMAND_LINK" ] || [ "$ACTUAL_COMMAND" != "$EXPECTED_COMMAND" ]; then
    echo "$bootstrap bootstrap installed $ACTUAL_COMMAND, expected $EXPECTED_COMMAND" >&2
    exit 1
  fi
done

# A malformed template must fail before either bootstrap publishes a settings
# file at the live path.
for bootstrap in root claude; do
  FAIL_REPO="$TEMP_DIR/workspace/fail-$bootstrap/CrossCheck"
  FAIL_HOME="$TEMP_DIR/home-fail-$bootstrap"
  mkdir -p "$(dirname "$FAIL_REPO")" "$FAIL_HOME"
  python3 - "$REPO_ROOT" "$FAIL_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
  if [ "$bootstrap" = root ]; then
    FAIL_TEMPLATE="$FAIL_REPO/settings.template.json"
    FAIL_SCRIPT="$FAIL_REPO/scripts/bootstrap-crosscheck.sh"
  else
    FAIL_TEMPLATE="$FAIL_REPO/claude/settings.template.json"
    FAIL_SCRIPT="$FAIL_REPO/claude/scripts/bootstrap-crosscheck.sh"
  fi
  printf '{not valid json\n' > "$FAIL_TEMPLATE"
  if HOME="$FAIL_HOME" bash "$FAIL_SCRIPT" > "$TEMP_DIR/bootstrap-failure-$bootstrap.log" 2>&1; then
    echo "$bootstrap bootstrap unexpectedly accepted an invalid settings template" >&2
    exit 1
  fi
  if [ -e "$FAIL_HOME/.claude/settings.json" ] || [ -L "$FAIL_HOME/.claude/settings.json" ] || find "$FAIL_HOME/.claude" -name 'settings.json.bootstrap.*' -print -quit | grep -q .; then
    echo "$bootstrap bootstrap left a partially published settings file" >&2
    exit 1
  fi
done

# The updater must pass the checkout explicitly; this caller runs in a fresh
# process and cannot rely on a shell-local CROSSCHECK_DIR.
grep -Fq 'sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"' "$REPO_ROOT/claude/skill-sources/update-crosscheck.md"
grep -Fq 'sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"' "$REPO_ROOT/codex/skills/update-crosscheck/SKILL.md"
if grep -Fq 'for TARGET_DIR in "$HOME/.claude/commands" "$HOME/.codex/commands"' "$REPO_ROOT/codex/skills/update-crosscheck/SKILL.md"; then
  echo "Codex updater still installs Claude commands from root skill sources" >&2
  exit 1
fi

SYNC_ROOT="$TEMP_DIR/crosscheck"
HOME_FIXTURE="$TEMP_DIR/home-sync"
EMPTY_GIT_CONFIG="$TEMP_DIR/empty-git-config"
: > "$EMPTY_GIT_CONFIG"
mkdir -p "$SYNC_ROOT/claude/skill-sources" "$SYNC_ROOT/skill-sources" "$HOME_FIXTURE/.claude/commands" "$HOME_FIXTURE/.crosscheck"
printf 'Old Claude shipped command\n' > "$SYNC_ROOT/claude/skill-sources/managed.md"
printf 'Old root shipped command\n' > "$SYNC_ROOT/skill-sources/managed.md"
git -C "$SYNC_ROOT" init -q
git -C "$SYNC_ROOT" add claude/skill-sources/managed.md skill-sources/managed.md
GIT_CONFIG_GLOBAL="$EMPTY_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 git -C "$SYNC_ROOT" -c user.name='CrossCheck test' -c user.email='crosscheck-test@example.invalid' commit -qm 'old shipped commands'
printf 'Claude-specific managed command\n' > "$SYNC_ROOT/claude/skill-sources/managed.md"
printf 'Root command source\n' > "$SYNC_ROOT/skill-sources/managed.md"
printf 'Claude-specific linked command\n' > "$SYNC_ROOT/claude/skill-sources/linked.md"
printf 'Root linked command\n' > "$SYNC_ROOT/skill-sources/linked.md"
printf 'Same-name command\n' > "$SYNC_ROOT/claude/skill-sources/wrong-name.md"
printf 'Claude-only new command\n' > "$SYNC_ROOT/claude/skill-sources/new-command.md"
printf 'skip-me\n' > "$SYNC_ROOT/claude/skill-sources/skipped.md"
git -C "$SYNC_ROOT" add claude/skill-sources/managed.md skill-sources/managed.md claude/skill-sources/linked.md skill-sources/linked.md claude/skill-sources/wrong-name.md claude/skill-sources/new-command.md claude/skill-sources/skipped.md
GIT_CONFIG_GLOBAL="$EMPTY_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 git -C "$SYNC_ROOT" -c user.name='CrossCheck test' -c user.email='crosscheck-test@example.invalid' commit -qm 'current shipped commands'
git -C "$SYNC_ROOT" update-ref refs/remotes/origin/main "$(git -C "$SYNC_ROOT" rev-parse HEAD)"
printf 'Unpublished skill command\n' > "$SYNC_ROOT/claude/skill-sources/unpublished.md"
git -C "$SYNC_ROOT" add claude/skill-sources/unpublished.md
GIT_CONFIG_GLOBAL="$EMPTY_GIT_CONFIG" GIT_CONFIG_NOSYSTEM=1 git -C "$SYNC_ROOT" -c user.name='CrossCheck test' -c user.email='crosscheck-test@example.invalid' commit -qm 'unpublished local skill'
printf 'Old root shipped command\n' > "$HOME_FIXTURE/.claude/commands/managed.md"
printf 'Unpublished skill command\n' > "$HOME_FIXTURE/.claude/commands/unpublished.md"
ln -s "$SYNC_ROOT/skill-sources/linked.md" "$HOME_FIXTURE/.claude/commands/linked.md"
ln -s "$SYNC_ROOT/claude/skill-sources/linked.md" "$HOME_FIXTURE/.claude/commands/wrong-name.md"
printf 'user-owned command\n' > "$HOME_FIXTURE/.claude/commands/custom.md"
printf 'skipped\n' > "$HOME_FIXTURE/.crosscheck/skip-skills"
"$REPO_ROOT/claude/scripts/sync-managed-claude-skills.sh" "$SYNC_ROOT" "$HOME_FIXTURE" >/dev/null

if [ ! -L "$HOME_FIXTURE/.claude/commands/managed.md" ] || [ "$(cat "$HOME_FIXTURE/.claude/commands/managed.md")" != "Claude-specific managed command" ]; then
  echo "managed Claude copy was not refreshed from the Claude mirror" >&2
  exit 1
fi
EXPECTED_LINK="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SYNC_ROOT/claude/skill-sources/linked.md")"
if [ "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$HOME_FIXTURE/.claude/commands/linked.md")" != "$EXPECTED_LINK" ]; then
  echo "same-name managed root symlink was not redirected to the Claude mirror" >&2
  exit 1
fi
if [ "$(readlink "$HOME_FIXTURE/.claude/commands/wrong-name.md")" != "$SYNC_ROOT/claude/skill-sources/linked.md" ]; then
  echo "custom same-tree alias pointing to a different skill name was rewritten" >&2
  exit 1
fi
if [ -L "$HOME_FIXTURE/.claude/commands/unpublished.md" ] || [ "$(cat "$HOME_FIXTURE/.claude/commands/unpublished.md")" != "Unpublished skill command" ]; then
  echo "a local-only skill version was treated as a published command" >&2
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
