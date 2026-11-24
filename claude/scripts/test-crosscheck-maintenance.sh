#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-supply-chain-hook.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/test-home"
export HOME="$TEMP_DIR/test-home"
SETTINGS_DIR="$TEMP_DIR/settings"
mkdir -p "$SETTINGS_DIR"

HOOK="$TEMP_DIR/preuse-supply-chain-gate.sh"
cat > "$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'ran\n' >> "$GATE_MARKER"
exit 2
HOOK_EOF
chmod +x "$HOOK"

for invalid in empty multiple malformed legacy-wrong-type nested-wrong-type deny-wrong-type; do
  SETTINGS="$SETTINGS_DIR/$invalid.json"
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

SETTINGS="$SETTINGS_DIR/settings.json"
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
LEGACY_SETTINGS="$SETTINGS_DIR/legacy-settings.json"
printf '{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo legacy"}]}]}\n' > "$LEGACY_SETTINGS"
"$INSTALLER" "$LEGACY_SETTINGS" "$HOOK"
if ! jq -e 'has("PreToolUse") | not' "$LEGACY_SETTINGS" >/dev/null || ! jq -e '.hooks.PreToolUse | any(.[]; .matcher == "Bash" and any(.hooks[]?; .command == "echo legacy"))' "$LEGACY_SETTINGS" >/dev/null; then
  echo "installer did not preserve legacy entries in nested Claude settings" >&2
  exit 1
fi

# An aliased settings file keeps both the link and target mode.
REAL_SETTINGS="$SETTINGS_DIR/real-settings.json"
LINKED_SETTINGS="$SETTINGS_DIR/linked-settings.json"
printf '{"permissions":{"deny":[]}}\n' > "$REAL_SETTINGS"
chmod 0640 "$REAL_SETTINGS"
ln -s "$REAL_SETTINGS" "$LINKED_SETTINGS"
"$INSTALLER" "$LINKED_SETTINGS" "$HOOK"
if [ ! -L "$LINKED_SETTINGS" ] || [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$REAL_SETTINGS")" != "0o640" ]; then
  echo "installer replaced a settings symlink or changed its mode" >&2
  exit 1
fi

# Intermediate settings must remain private even when the caller's umask is
# permissive and the installed settings contain private values.
PRIVATE_SETTINGS="$SETTINGS_DIR/private-settings.json"
PRIVATE_JQ_BIN="$TEMP_DIR/private-jq-bin"
PRIVATE_MODE_MARKER="$TEMP_DIR/private-settings-temp-mode"
mkdir -p "$PRIVATE_JQ_BIN"
printf '{"privateValue":"fixture"}\n' > "$PRIVATE_SETTINGS"
chmod 0600 "$PRIVATE_SETTINGS"
REAL_JQ="$(command -v jq)"
cat > "$PRIVATE_JQ_BIN/jq" <<'SH'
#!/usr/bin/env bash
set -e
python3 - "${@: -1}" "$TEMP_MODE_MARKER" <<'PY'
import glob
import os
import stat
import sys
from pathlib import Path

marker = Path(sys.argv[2])
temps = glob.glob(os.path.join(os.environ["TMPDIR"], "crosscheck-settings-stage.*"))
if temps and not marker.exists():
    mode = stat.S_IMODE(os.stat(temps[0]).st_mode)
    marker.write_text(oct(mode))
    if mode != 0o600:
        raise SystemExit(f"installer exposed its temporary settings file with mode {oct(mode)}")
PY
exec "$REAL_JQ" "$@"
SH
chmod +x "$PRIVATE_JQ_BIN/jq"
(
  umask 022
  PATH="$PRIVATE_JQ_BIN:$PATH" TMPDIR="$TEMP_DIR" REAL_JQ="$REAL_JQ" TEMP_MODE_MARKER="$PRIVATE_MODE_MARKER" TEMP_MODE_TARGET="$PRIVATE_SETTINGS" "$INSTALLER" "$PRIVATE_SETTINGS" "$HOOK"
)
if [ "$(cat "$PRIVATE_MODE_MARKER")" != "0o600" ] || [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$PRIVATE_SETTINGS")" != "0o600" ]; then
  echo "installer did not keep private settings and its intermediate file at mode 0600" >&2
  exit 1
fi
if find "$TEMP_DIR" -maxdepth 1 -name 'crosscheck-settings-stage.*' -print -quit | grep -q .; then
  echo "installer left its private staged settings file in TMPDIR" >&2
  exit 1
fi

run_bootstrap_with_declines() {
  local home="$1"
  local script="$2"
  local scenario="$3"
  BOOTSTRAP_HOME="$home" BOOTSTRAP_SCRIPT="$script" BOOTSTRAP_SCENARIO="$scenario" python3 <<'PY'
import os
import pty
import select
import signal
import sys
import time

home = os.environ["BOOTSTRAP_HOME"]
script = os.environ["BOOTSTRAP_SCRIPT"]
scenario = os.environ["BOOTSTRAP_SCENARIO"]
pid, fd = pty.fork()
if pid == 0:
    env = os.environ.copy()
    env["HOME"] = home
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    os.execve("/bin/bash", ["bash", script], env)

output = bytearray()
sent_prompts = set()
prompt_fragments = (
    b"Install git hooks globally (all repos)? (Y/n)",
    b"Install Codex review hooks globally? (Y/n)",
    b"Install Claude review hooks globally? (Y/n)",
    b"Install TokenPrint (AI usage dashboard)? (Y/n)",
)
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
                    os.write(fd, b"n")
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
    raise SystemExit(f"bootstrap timed out while testing {scenario}")
if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    sys.stderr.write(output.decode(errors="replace"))
    raise SystemExit(f"bootstrap exited unsuccessfully while testing {scenario}: {status}")

declined_outcomes = [
    b"Skipped global git hooks (you can install per-repo later)",
    b"Skipped TokenPrint (/ai-usage will prompt to install when used)",
]
if "/claude/scripts/" in script:
    declined_outcomes.append(b"Skipped Claude review hooks")
else:
    declined_outcomes.append(b"Skipped Codex review hooks")
for declined in declined_outcomes:
    if declined not in output:
        sys.stderr.write(output.decode(errors="replace"))
        raise SystemExit(f"bootstrap did not confirm declined optional install: {declined.decode()}")
PY
}

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

  run_bootstrap_with_declines "$BOOTSTRAP_HOME" "$SCRIPT" "fresh settings install"

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

# Codex bootstrap must detect an atomic edit to global instructions between
# reading the source snapshot and publishing the managed block.
AGENT_RACE_REPO="$TEMP_DIR/workspace/codex-agent-race/CrossCheck"
AGENT_RACE_HOME="$TEMP_DIR/home-codex-agent-race"
AGENT_RACE_SCRIPT="$AGENT_RACE_REPO/codex/scripts/bootstrap-crosscheck.sh"
AGENT_RACE_SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$AGENT_RACE_HOME/.codex/AGENTS.md")"
mkdir -p "$(dirname "$AGENT_RACE_REPO")" "$AGENT_RACE_HOME/.codex"
python3 - "$REPO_ROOT" "$AGENT_RACE_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
printf 'original global instructions\n' > "$AGENT_RACE_HOME/.codex/AGENTS.md"
AGENT_RACE_BIN="$TEMP_DIR/codex-agent-race-bin"
mkdir -p "$AGENT_RACE_BIN"
AGENT_RACE_REAL_PYTHON="$(command -v python3)"
cat > "$AGENT_RACE_BIN/python3" <<'SH'
#!/usr/bin/env bash
set -e
if [ "$1" = "$AGENT_RACE_REPO/scripts/atomic-publish-file.py" ] \
  && [ "$2" = publish ] \
  && [ "$3" = "$HOME/.codex" ] \
  && [ "$4" = AGENTS.md ] \
  && [ ! -e "$AGENT_RACE_MARKER" ]; then
  printf 'concurrent global instruction edit\n' > "$HOME/.codex/AGENTS.md"
  : > "$AGENT_RACE_MARKER"
fi
exec "$AGENT_RACE_REAL_PYTHON" "$@"
SH
chmod +x "$AGENT_RACE_BIN/python3"
if env HOME="$AGENT_RACE_HOME" PATH="$AGENT_RACE_BIN:$PATH" \
  AGENT_RACE_REPO="$AGENT_RACE_REPO" AGENT_RACE_REAL_PYTHON="$AGENT_RACE_REAL_PYTHON" \
  AGENT_RACE_MARKER="$TEMP_DIR/codex-agent-race-injected" TMPDIR="$TEMP_DIR" \
  bash "$AGENT_RACE_SCRIPT" \
  > "$TEMP_DIR/codex-agent-race.log" 2>&1; then
  echo "Codex bootstrap overwrote a concurrent global instruction edit" >&2
  exit 1
fi
if ! grep -Fq "file changed during CrossCheck update, refusing to overwrite: $AGENT_RACE_SETTINGS_TARGET" "$TEMP_DIR/codex-agent-race.log"; then
  echo "Codex bootstrap failed without the concurrent-instruction diagnostic" >&2
  cat "$TEMP_DIR/codex-agent-race.log" >&2
  exit 1
fi
if [ "$(cat "$AGENT_RACE_HOME/.codex/AGENTS.md")" != "concurrent global instruction edit" ]; then
  echo "Codex bootstrap lost the concurrent global instruction edit" >&2
  exit 1
fi
if find "$TEMP_DIR" -maxdepth 1 -name 'crosscheck-codex-agents.*' -print -quit | grep -q .; then
  echo "Codex bootstrap left its private instruction snapshot or stage" >&2
  exit 1
fi

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
  if ! grep -Fq 'Claude settings file must contain exactly one valid JSON object:' "$TEMP_DIR/bootstrap-failure-$bootstrap.log"; then
    echo "$bootstrap bootstrap failed without the installer's settings validation diagnostic" >&2
    cat "$TEMP_DIR/bootstrap-failure-$bootstrap.log" >&2
    exit 1
  fi
  if [ -e "$FAIL_HOME/.claude/settings.json" ] || [ -L "$FAIL_HOME/.claude/settings.json" ] || find "$FAIL_HOME/.claude" -name 'settings.json.bootstrap.*' -print -quit | grep -q .; then
    echo "$bootstrap bootstrap left a partially published settings file" >&2
    exit 1
  fi
done

# Simulate another process creating a file or directory at the settings path
# after staged validation. Files must be preserved and updated; directories
# must fail safely without receiving the staged file.
for race_kind in regular directory regular-edit; do
  for bootstrap in root claude; do
  RACE_REPO="$TEMP_DIR/workspace/race-$race_kind-$bootstrap/CrossCheck"
  RACE_HOME="$TEMP_DIR/home-race-$race_kind-$bootstrap"
  mkdir -p "$(dirname "$RACE_REPO")" "$RACE_HOME/.claude"
  python3 - "$REPO_ROOT" "$RACE_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
  if [ "$bootstrap" = root ]; then
    RACE_SCRIPT="$RACE_REPO/scripts/bootstrap-crosscheck.sh"
  else
    RACE_SCRIPT="$RACE_REPO/claude/scripts/bootstrap-crosscheck.sh"
  fi
  RACE_INSTALLER="$RACE_REPO/claude/scripts/install-supply-chain-hook.sh"
  RACE_JQ_BIN="$RACE_REPO/test-jq-bin"
  RACE_REAL_JQ="$(command -v jq)"
  mkdir -p "$RACE_JQ_BIN"
  cat > "$RACE_JQ_BIN/jq" <<'SH'
#!/usr/bin/env bash
set -e
case " $* " in
  *" --arg hook "*)
    if [ -n "${RACE_EDIT_TARGET:-}" ]; then
      "$RACE_REAL_JQ" "$@"
      printf '{"concurrentWriter":"second edit"}\n' > "$RACE_EDIT_TARGET"
      exit 0
    fi
    ;;
esac
exec "$RACE_REAL_JQ" "$@"
SH
  chmod +x "$RACE_JQ_BIN/jq"
  mv "$RACE_INSTALLER" "${RACE_INSTALLER}.real"
  cat > "$RACE_INSTALLER" <<'SH'
#!/usr/bin/env bash
set -e
REAL_INSTALLER="$(dirname "$0")/install-supply-chain-hook.sh.real"
case "$1" in
  "$HOME"/.claude/settings.json.bootstrap.*)
    "$REAL_INSTALLER" "$@"
    if [ "$RACE_TARGET_KIND" = directory ]; then
      mkdir "$HOME/.claude/settings.json"
    elif [ "$RACE_TARGET_KIND" = regular-edit ]; then
      printf '{"concurrentWriter":"first edit"}\n' > "$HOME/.claude/settings.json"
    else
      printf '{"concurrentWriter":"preserve me"}\n' > "$HOME/.claude/settings.json"
    fi
    ;;
  "$HOME"/.claude/settings.json)
    if [ "$RACE_TARGET_KIND" = regular-edit ]; then
      PATH="$RACE_JQ_BIN:$PATH" RACE_REAL_JQ="$RACE_REAL_JQ" RACE_EDIT_TARGET="$1" "$REAL_INSTALLER" "$@"
    else
      "$REAL_INSTALLER" "$@"
    fi
    ;;
  *)
    "$REAL_INSTALLER" "$@"
    ;;
esac
SH
  chmod +x "$RACE_INSTALLER"
  export RACE_TARGET_KIND="$race_kind"
  RACE_SETTINGS="$RACE_HOME/.claude/settings.json"
  RACE_SETTINGS_TARGET="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$RACE_SETTINGS")"
  if [ "$race_kind" = regular ]; then
    run_bootstrap_with_declines "$RACE_HOME" "$RACE_SCRIPT" "concurrent settings creation"
    if ! jq -e '.concurrentWriter == "preserve me"' "$RACE_SETTINGS" >/dev/null; then
      echo "$bootstrap bootstrap overwrote settings created during first-time setup" >&2
      cat "$RACE_SETTINGS" >&2
      exit 1
    fi
    jq -e '.hooks.PreToolUse | type == "array"' "$RACE_SETTINGS" >/dev/null
  else
    if [ "$race_kind" = directory ]; then
      if HOME="$RACE_HOME" RACE_TARGET_KIND="$race_kind" RACE_JQ_BIN="$RACE_JQ_BIN" RACE_REAL_JQ="$RACE_REAL_JQ" bash "$RACE_SCRIPT" > "$TEMP_DIR/bootstrap-directory-race-$bootstrap.log" 2>&1; then
        echo "$bootstrap bootstrap unexpectedly accepted a directory at the settings path" >&2
        exit 1
      fi
      if ! grep -Fq "Could not safely publish prepared settings at $RACE_SETTINGS" "$TEMP_DIR/bootstrap-directory-race-$bootstrap.log"; then
        echo "$bootstrap bootstrap failed without the safe-publish diagnostic for a directory collision" >&2
        cat "$TEMP_DIR/bootstrap-directory-race-$bootstrap.log" >&2
        exit 1
      fi
      if [ ! -d "$RACE_SETTINGS" ] || find "$RACE_SETTINGS" -mindepth 1 -print -quit | grep -q .; then
        echo "$bootstrap bootstrap wrote staged settings inside a concurrently created directory" >&2
        exit 1
      fi
    else
      if HOME="$RACE_HOME" RACE_TARGET_KIND="$race_kind" RACE_JQ_BIN="$RACE_JQ_BIN" RACE_REAL_JQ="$RACE_REAL_JQ" bash "$RACE_SCRIPT" > "$TEMP_DIR/bootstrap-edit-race-$bootstrap.log" 2>&1; then
        echo "$bootstrap bootstrap unexpectedly overwrote a concurrent settings edit" >&2
        exit 1
      fi
      if ! grep -Fq "file changed during CrossCheck update, refusing to overwrite: $RACE_SETTINGS_TARGET" "$TEMP_DIR/bootstrap-edit-race-$bootstrap.log"; then
        echo "$bootstrap bootstrap failed without the concurrent-edit diagnostic" >&2
        cat "$TEMP_DIR/bootstrap-edit-race-$bootstrap.log" >&2
        exit 1
      fi
      jq -e '.concurrentWriter == "second edit"' "$RACE_SETTINGS" >/dev/null
    fi
  fi
  if find "$RACE_HOME/.claude" -name 'settings.json.bootstrap.*' -print -quit | grep -q .; then
    echo "$bootstrap bootstrap left a staged settings file after resolving a publish collision" >&2
    exit 1
  fi
  done
done

# The updater must pass the checkout explicitly; this caller runs in a fresh
# process and cannot rely on a shell-local CROSSCHECK_DIR.
grep -Fq 'sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"' "$REPO_ROOT/claude/skill-sources/update-crosscheck.md"
grep -Fq 'sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"' "$REPO_ROOT/codex/skills/update-crosscheck/SKILL.md"
for updater in "$REPO_ROOT/skill-sources/update-crosscheck.md" "$REPO_ROOT/claude/skill-sources/update-crosscheck.md" "$REPO_ROOT/codex/skill-sources/update-crosscheck.md" "$REPO_ROOT/codex/skills/update-crosscheck/SKILL.md"; do
  grep -Fq 'scripts/sync-critical-settings.sh' "$updater"
  grep -Fq 'install-supply-chain-hook.sh' "$updater"
  if grep -Fq 'mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"' "$updater"; then
    echo "updater still replaces settings with a check-then-move: $updater" >&2
    exit 1
  fi
  pull_line="$(grep -n -m1 'git pull origin main --quiet' "$updater" | cut -d: -f1)"
  settings_line="$(grep -n -m1 'scripts/sync-critical-settings.sh' "$updater" | cut -d: -f1)"
  if [ -z "$pull_line" ] || [ -z "$settings_line" ] || [ "$settings_line" -le "$pull_line" ]; then
    echo "updater runs the settings helper before pulling the code that provides it: $updater" >&2
    exit 1
  fi
  if ! grep -Fq '"$HOME" --count-only)' "$updater" || grep -Fq 'CLAUDE_SYNC_RESULT##*:' "$updater"; then
    echo "updater does not use the Claude helper's numeric count output: $updater" >&2
    exit 1
  fi
done
for drain_skill in "$REPO_ROOT/skill-sources/drain-repo.md" "$REPO_ROOT/claude/skill-sources/drain-repo.md" "$REPO_ROOT/codex/skill-sources/drain-repo.md" "$REPO_ROOT/codex/skills/drain-repo/SKILL.md"; do
  if grep -Fq 'core.hooksPath=/dev/null' "$drain_skill" || grep -Fq 'Merge is YOURS to execute' "$drain_skill"; then
    echo "drain skill still recommends bypassing configured workflow gates: $drain_skill" >&2
    exit 1
  fi
  if ! grep -Fq 'Land through the configured Switchyard route' "$drain_skill" || ! grep -Fq 'Preserve native deployment and environment approvals' "$drain_skill"; then
    echo "drain skill omits required merge or deployment gates: $drain_skill" >&2
    exit 1
  fi
done
for updater in "$REPO_ROOT/skill-sources/update-crosscheck.md" "$REPO_ROOT/codex/skill-sources/update-crosscheck.md"; do
  if ! grep -Fq 'sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"' "$updater"; then
    echo "legacy updater does not refresh Claude commands through the managed mirror: $updater" >&2
    exit 1
  fi
  if grep -Fq 'for TARGET_DIR in "$HOME/.claude/commands"' "$updater"; then
    echo "legacy updater still installs root skill sources into Claude commands: $updater" >&2
    exit 1
  fi
done
if grep -Fq 'for TARGET_DIR in "$HOME/.claude/commands" "$HOME/.codex/commands"' "$REPO_ROOT/codex/skills/update-crosscheck/SKILL.md"; then
  echo "Codex updater still installs Claude commands from root skill sources" >&2
  exit 1
fi
NATIVE_REPO="$TEMP_DIR/codex-native-repo"
mkdir -p "$NATIVE_REPO/codex/skills/drain-repo" "$NATIVE_REPO/codex/skills/update-crosscheck" "$NATIVE_REPO/codex/skills/new-skill" "$NATIVE_REPO/scripts" "$NATIVE_REPO/codex/scripts"
cp "$REPO_ROOT/scripts/atomic-publish-file.py" "$NATIVE_REPO/scripts/atomic-publish-file.py"
cp "$REPO_ROOT/codex/scripts/sync-managed-codex-skills.sh" "$NATIVE_REPO/codex/scripts/sync-managed-codex-skills.sh"
printf 'shipped drain skill\n' > "$NATIVE_REPO/codex/skills/drain-repo/SKILL.md"
printf 'old shipped skill\n' > "$NATIVE_REPO/codex/skills/update-crosscheck/SKILL.md"
printf 'new skill\n' > "$NATIVE_REPO/codex/skills/new-skill/SKILL.md"
printf 'supporting file\n' > "$NATIVE_REPO/codex/skills/new-skill/REFERENCE.md"
git -C "$NATIVE_REPO" init -q
git -C "$NATIVE_REPO" config user.name "CrossCheck Test"
git -C "$NATIVE_REPO" config user.email "crosscheck-test@example.invalid"
mkdir -p "$NATIVE_REPO/no-hooks"
git -C "$NATIVE_REPO" config core.hooksPath "$NATIVE_REPO/no-hooks"
git -C "$NATIVE_REPO" add codex/skills
git -C "$NATIVE_REPO" commit -qm "fixture: old shipped skill"
printf 'current shipped skill\n' > "$NATIVE_REPO/codex/skills/update-crosscheck/SKILL.md"
git -C "$NATIVE_REPO" add codex/skills/update-crosscheck/SKILL.md
git -C "$NATIVE_REPO" commit -qm "fixture: current shipped skill"
git -C "$NATIVE_REPO" update-ref refs/remotes/origin/main "$(git -C "$NATIVE_REPO" rev-parse HEAD)"
NATIVE_HOME="$TEMP_DIR/home-codex-native"
mkdir -p "$NATIVE_HOME/.codex/skills/drain-repo" "$NATIVE_HOME/.codex/skills/update-crosscheck" "$NATIVE_HOME/.crosscheck"
printf 'user customization\n' > "$NATIVE_HOME/.codex/skills/drain-repo/SKILL.md"
printf 'old shipped skill\n' > "$NATIVE_HOME/.codex/skills/update-crosscheck/SKILL.md"
HOME="$NATIVE_HOME" bash "$NATIVE_REPO/codex/scripts/sync-managed-codex-skills.sh" "$NATIVE_REPO" "$NATIVE_HOME" > "$TEMP_DIR/codex-native-update.log" 2>&1
NATIVE_RECOVERY_DIR="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$NATIVE_HOME/.crosscheck-recovery")"
if ! grep -Fq "$NATIVE_RECOVERY_DIR/settings-" "$TEMP_DIR/codex-native-update.log"; then
  echo "Codex native updater did not keep recovery outside its narrowed publisher root" >&2
  cat "$TEMP_DIR/codex-native-update.log" >&2
  exit 1
fi
if [ "$(cat "$NATIVE_HOME/.codex/skills/drain-repo/SKILL.md")" != "user customization" ]; then
  echo "Codex native updater overwrote a customized skill file" >&2
  exit 1
fi
if ! cmp -s "$NATIVE_REPO/codex/skills/update-crosscheck/SKILL.md" "$NATIVE_HOME/.codex/skills/update-crosscheck/SKILL.md"; then
  echo "Codex native updater did not refresh a previously shipped skill file" >&2
  exit 1
fi
if ! cmp -s "$NATIVE_REPO/codex/skills/new-skill/SKILL.md" "$NATIVE_HOME/.codex/skills/new-skill/SKILL.md"; then
  echo "Codex native updater did not install a new skill" >&2
  exit 1
fi
if ! cmp -s "$NATIVE_REPO/codex/skills/new-skill/REFERENCE.md" "$NATIVE_HOME/.codex/skills/new-skill/REFERENCE.md"; then
  echo "Codex native updater skipped a missing file inside a newly created skill directory" >&2
  exit 1
fi

# A non-directory skills root is an operational failure, not a successful
# refresh that silently preserves every managed skill.
BROKEN_NATIVE_HOME="$TEMP_DIR/home-codex-native-broken"
mkdir -p "$BROKEN_NATIVE_HOME/.codex"
printf 'not a directory\n' > "$BROKEN_NATIVE_HOME/.codex/skills"
if HOME="$BROKEN_NATIVE_HOME" bash "$NATIVE_REPO/codex/scripts/sync-managed-codex-skills.sh" "$NATIVE_REPO" "$BROKEN_NATIVE_HOME" > "$TEMP_DIR/codex-native-broken.log" 2>&1; then
  echo "Codex native updater reported success with a non-directory skills root" >&2
  exit 1
fi
if ! grep -Fq "Could not safely snapshot Codex skill file" "$TEMP_DIR/codex-native-broken.log"; then
  echo "Codex native updater failed without reporting its invalid skills root" >&2
  cat "$TEMP_DIR/codex-native-broken.log" >&2
  exit 1
fi

python3 - "$REPO_ROOT/scripts/atomic-publish-file.py" "$TEMP_DIR" <<'PY'
import errno
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("atomic_publish_file", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
scratch = Path(sys.argv[2]) / "atomic-publish-race"
scratch.mkdir()
settings_dir = scratch / ".claude"
settings_dir.mkdir()
target = settings_dir / "settings.json"
snapshot = scratch / "snapshot.json"
staged = scratch / "staged.json"
target.write_text('{"setting":"original"}\n')
snapshot.write_text('{"setting":"original"}\n')
staged.write_text('{"setting":"updated"}\n')
open_file = target.open("r+")
recovery_path = module.publish_file(str(scratch), ".claude/settings.json", str(snapshot), str(staged))
if target.read_text() != '{"setting":"updated"}\n':
    raise SystemExit("atomic publisher did not install the staged settings")
open_file.seek(0)
open_file.truncate()
open_file.write('{"concurrentWriter":"late save"}\n')
open_file.flush()
open_file.close()
if not recovery_path or Path(recovery_path).read_text() != '{"concurrentWriter":"late save"}\n':
    raise SystemExit("atomic publisher did not preserve a save through an already-open settings file")

# A target-parent rename detected after exchange must roll publication back
# while retaining a durable recovery copy outside the moved tree.
settings_dir.rename(scratch / "settings-dir-before-rename-test")
settings_dir.mkdir()
target = settings_dir / "settings.json"
snapshot.write_text('{"setting":"original again"}\n')
target.write_text('{"setting":"original again"}\n')
staged.write_text('{"setting":"updated after rename"}\n')
real_verify = module._verify_parent_path
verify_calls = [0]

def rename_parent_after_publish(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        settings_dir.rename(scratch / "settings-dir-moved-during-publish")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = rename_parent_after_publish
try:
    module.publish_file(str(scratch), ".claude/settings.json", str(snapshot), str(staged))
except module.ConcurrentUpdate as error:
    if not error.recovery_path or Path(error.recovery_path).read_text() != '{"setting":"original again"}\n':
        raise SystemExit("atomic publisher reported a recovery path that did not survive a parent rename")
else:
    raise SystemExit("atomic publisher accepted a target parent rename during publication")
finally:
    module._verify_parent_path = real_verify
if (scratch / "settings-dir-moved-during-publish/settings.json").read_text() != '{"setting":"original again"}\n':
    raise SystemExit("atomic publisher failed to restore the previous settings after a target parent rename")

# Settings callers use the target directory as the publisher root. Moving that
# root after publication must be detected, with recovery outside the root.
root_case = scratch / "settings-root-case"
root_home = scratch / "settings-root-home"
root_home.mkdir()
root_case = root_home / ".crosscheck-recovery"
root_case.mkdir()
root_target = root_case / "settings.json"
root_snapshot = scratch / "root-case-snapshot.json"
root_stage = scratch / "root-case-stage.json"
root_target.write_text('{"rootCase":"original"}\n')
root_snapshot.write_text('{"rootCase":"original"}\n')
root_stage.write_text('{"rootCase":"updated"}\n')
real_verify = module._verify_parent_path
verify_calls = [0]

def rename_root_after_publish(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        Path(root_path).rename(root_case.with_name("settings-root-case-moved"))
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = rename_root_after_publish
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(root_home)
try:
    module.publish_file(str(root_case), "settings.json", str(root_snapshot), str(root_stage))
except module.ConcurrentUpdate as error:
    recovery = Path(error.recovery_path) if error.recovery_path else None
    moved_root = root_home / "settings-root-case-moved"
    if (
        not recovery
        or not recovery.is_file()
        or recovery.read_text() != '{"rootCase":"original"}\n'
        or recovery == moved_root
        or moved_root in recovery.parents
    ):
        raise SystemExit("publisher did not report durable recovery after its root path moved")
else:
    raise SystemExit("publisher accepted a moved root used by the settings installer")
finally:
    os.environ["HOME"] = previous_home
    module._verify_parent_path = real_verify
if (root_home / "settings-root-case-moved/settings.json").read_text() != '{"rootCase":"original"}\n':
    raise SystemExit("publisher failed to restore settings when the publisher root moved")

# If there is no private same-volume recovery location outside both the
# publisher root and target parent, publication must fail before moving live settings.
cross_volume_target = scratch / "cross-volume-preflight/settings.json"
cross_volume_target.parent.mkdir()
cross_volume_target.write_text('{"crossVolume":"original"}\n')
cross_volume_snapshot = scratch / "cross-volume-snapshot.json"
cross_volume_stage = scratch / "cross-volume-stage.json"
cross_volume_snapshot.write_text('{"crossVolume":"original"}\n')
cross_volume_stage.write_text('{"crossVolume":"updated"}\n')
real_open_recovery = module._open_stable_recovery_directory

def force_cross_volume(root_path, parent_path, target_device):
    return real_open_recovery(root_path, parent_path, -1)

module._open_stable_recovery_directory = force_cross_volume
try:
    module.publish_file(
        str(cross_volume_target.parent),
        "settings.json",
        str(cross_volume_snapshot),
        str(cross_volume_stage),
    )
except OSError as error:
    if error.errno != errno.EXDEV or "refusing to replace settings" not in str(error):
        raise
else:
    raise SystemExit("publisher did not fail safely when no same-volume recovery path exists")
finally:
    module._open_stable_recovery_directory = real_open_recovery
if cross_volume_target.read_text() != '{"crossVolume":"original"}\n':
    raise SystemExit("publisher changed settings before finding a same-volume recovery path")
if list(cross_volume_target.parent.glob(".crosscheck-publish-*")):
    raise SystemExit("publisher left temporary recovery data after a cross-volume preflight failure")

# An exchange error must leave the original live settings in place.
error_dir = scratch / "publish-error"
error_dir.mkdir()
(error_dir / ".claude").mkdir()
error_target = error_dir / ".claude/settings.json"
error_snapshot = error_dir / "snapshot.json"
error_stage = error_dir / "staged.json"
error_target.write_text('{"setting":"original"}\n')
error_snapshot.write_text('{"setting":"original"}\n')
error_stage.write_text('{"setting":"updated"}\n')
real_exchange = module._rename_exchange

def fail_stage_publish(first_fd, first, second_fd, second):
    if first == "settings.json" or second == "settings.json":
        raise OSError(95, "injected publish failure")
    return real_exchange(first_fd, first, second_fd, second)

module._rename_exchange = fail_stage_publish
try:
    module.publish_file(str(error_dir), ".claude/settings.json", str(error_snapshot), str(error_stage))
except OSError as error:
    if "injected publish failure" not in str(error):
        raise
else:
    raise SystemExit("atomic publisher accepted an injected publish failure")
finally:
    module._rename_exchange = real_exchange
if error_target.read_text() != '{"setting":"original"}\n':
    raise SystemExit("atomic publisher changed settings after an exchange failure")
if list((error_dir / ".claude").glob(".crosscheck-publish-*")):
    raise SystemExit("atomic publisher left recovery data after successful restoration")

# Replacements both before publication and during rollback must remain live
# and get durable recovery copies.
race_target_dir = scratch / "atomic-exchange-race"
race_target_dir.mkdir()
race_target = race_target_dir / "settings.json"
race_snapshot = scratch / "atomic-exchange-race-snapshot.json"
race_stage = scratch / "atomic-exchange-race-stage.json"
race_target.write_text('{"setting":"original"}\n')
race_snapshot.write_text('{"setting":"original"}\n')
race_stage.write_text('{"setting":"updated"}\n')
real_exchange = module._rename_exchange
exchange_calls = [0]

def replace_user_settings_then_exchange(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    target = race_target_dir / "settings.json"
    if not target.exists():
        raise SystemExit("live settings disappeared before atomic exchange")
    if exchange_calls[0] <= 9:
        save_number = exchange_calls[0]
        competitor = race_target_dir / f"concurrent-settings-{save_number}.json"
        competitor.write_text(f'{{"setting":"concurrent user edit {save_number}"}}\n')
        competitor.replace(target)
    result = real_exchange(first_fd, first, second_fd, second)
    if not target.exists():
        raise SystemExit("live settings disappeared during atomic exchange")
    return result

module._rename_exchange = replace_user_settings_then_exchange
try:
    module.publish_file(str(race_target_dir), "settings.json", str(race_snapshot), str(race_stage))
except module.ConcurrentUpdate as error:
    if not error.recovery_path or Path(error.recovery_path).read_text() != '{"setting":"concurrent user edit 9"}\n':
        raise SystemExit("latest concurrent settings were not preserved in a durable recovery file")
    backups = {path.read_text() for path in Path(error.recovery_path).parent.glob("settings-*.bak")}
    expected_backups = {
        f'{{"setting":"concurrent user edit {save_number}"}}\n'
        for save_number in range(1, 9)
    }
    if not expected_backups.issubset(backups):
        raise SystemExit("rollback did not retain all earlier concurrent settings versions")
else:
    raise SystemExit("atomic publisher overwrote settings replaced by a concurrent writer")
finally:
    module._rename_exchange = real_exchange
if race_target.read_text() != '{"setting":"concurrent user edit 9"}\n':
    raise SystemExit("atomic publisher did not restore the latest concurrent settings to the live path")
if list(race_target_dir.glob(".crosscheck-stage-*")):
    raise SystemExit("atomic publisher left a staged file after a concurrent update")

# A failed recovery link still triggers rollback, so the staged update is not
# left live when the original target can be restored.
link_failure_dir = scratch / "recovery-link-failure"
link_failure_dir.mkdir()
link_failure_target = link_failure_dir / "settings.json"
link_failure_snapshot = scratch / "recovery-link-failure-snapshot.json"
link_failure_stage = scratch / "recovery-link-failure-stage.json"
link_failure_target.write_text('{"setting":"original"}\n')
link_failure_snapshot.write_text('{"setting":"original"}\n')
link_failure_stage.write_text('{"setting":"updated"}\n')
real_verify = module._verify_parent_path
verify_calls = [0]

def fail_after_recovery_link(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        raise module.ConcurrentUpdate("injected post-exchange verification failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

real_recovery_link = module._new_stable_recovery_link
link_calls = [0]

def fail_competing_recovery_link(source_fd, source_name, recovery_fd, recovery_dir):
    link_calls[0] += 1
    if link_calls[0] == 2:
        raise OSError(28, "injected recovery link failure")
    return real_recovery_link(source_fd, source_name, recovery_fd, recovery_dir)

module._verify_parent_path = fail_after_recovery_link
module._new_stable_recovery_link = fail_competing_recovery_link
try:
    module.publish_file(
        str(link_failure_dir), "settings.json", str(link_failure_snapshot), str(link_failure_stage)
    )
except module.ConcurrentUpdate as error:
    if "injected post-exchange" not in str(error):
        raise
else:
    raise SystemExit("atomic publisher accepted an injected post-exchange failure")
finally:
    module._verify_parent_path = real_verify
    module._new_stable_recovery_link = real_recovery_link
if link_failure_target.read_text() != '{"setting":"original"}\n':
    raise SystemExit("atomic publisher left staged settings live after recovery-link failure")

# A failed first backup must not mark that edit safe to discard if a second
# writer appears during rollback.
edit_race_dir = scratch / "failed-first-backup-race"
edit_race_dir.mkdir()
edit_race_target = edit_race_dir / "settings.json"
edit_race_snapshot = scratch / "failed-first-backup-snapshot.json"
edit_race_stage = scratch / "failed-first-backup-stage.json"
edit_race_target.write_text('{"setting":"original"}\n')
edit_race_snapshot.write_text('{"setting":"original"}\n')
edit_race_stage.write_text('{"setting":"updated"}\n')
real_exchange = module._rename_exchange
exchange_calls = [0]

def inject_two_edits(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    if exchange_calls[0] in (1, 2):
        edit_number = exchange_calls[0]
        competitor = edit_race_dir / f"edit-{edit_number}.json"
        competitor.write_text(f'{{"setting":"concurrent edit {edit_number}"}}\n')
        competitor.replace(edit_race_target)
    return real_exchange(first_fd, first, second_fd, second)

real_recovery_link = module._new_stable_recovery_link
link_calls = [0]

def fail_first_concurrent_backup(source_fd, source_name, recovery_fd, recovery_dir):
    link_calls[0] += 1
    if link_calls[0] == 2:
        raise OSError(28, "injected first concurrent backup failure")
    return real_recovery_link(source_fd, source_name, recovery_fd, recovery_dir)

module._rename_exchange = inject_two_edits
module._new_stable_recovery_link = fail_first_concurrent_backup
try:
    module.publish_file(str(edit_race_dir), "settings.json", str(edit_race_snapshot), str(edit_race_stage))
except module.ConcurrentUpdate as error:
    backup_contents = {
        path.read_text()
        for path in Path(error.recovery_path).parent.glob("settings-*.bak")
    } if error.recovery_path else set()
    if '{"setting":"concurrent edit 1"}\n' not in backup_contents or '{"setting":"concurrent edit 2"}\n' not in backup_contents:
        raise SystemExit("atomic publisher discarded an edit whose first recovery link failed")
else:
    raise SystemExit("atomic publisher accepted two concurrent edits after a recovery-link failure")
finally:
    module._rename_exchange = real_exchange
    module._new_stable_recovery_link = real_recovery_link
if edit_race_target.read_text() != '{"setting":"concurrent edit 2"}\n':
    raise SystemExit("atomic publisher did not keep the latest concurrent edit live")

# If a writer saves through a descriptor to the displaced original after the
# exchange, preserve later saves through a descriptor to the staged new inode
# before cleanup unlinks its staging name.
late_stage_race_dir = scratch / "late-stage-save-race"
late_stage_race_dir.mkdir()
late_stage_target = late_stage_race_dir / "settings.json"
late_stage_snapshot = scratch / "late-stage-save-snapshot.json"
late_stage_file = scratch / "late-stage-save-stage.json"
late_stage_target.write_text('{"setting":"original"}\n')
late_stage_snapshot.write_text('{"setting":"original"}\n')
late_stage_file.write_text('{"setting":"updated"}\n')
original_handle = late_stage_target.open("r+")
new_inode_handles = []
real_exchange = module._rename_exchange
exchange_calls = [0]

def retain_new_inode_descriptor(first_fd, first, second_fd, second):
    result = real_exchange(first_fd, first, second_fd, second)
    exchange_calls[0] += 1
    if exchange_calls[0] == 1:
        new_inode_handles.append(late_stage_target.open("r+"))
    return result

real_verify = module._verify_parent_path
verify_calls = [0]

def edit_displaced_original_then_fail(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        original_handle.seek(0)
        original_handle.truncate()
        original_handle.write('{"setting":"late original edit"}\n')
        original_handle.flush()
        raise module.ConcurrentUpdate("injected failure after displaced-original save")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

real_entry_state = module._entry_state_at
stage_edit_calls = [0]

def edit_new_inode_after_stage_sample(directory_fd, name):
    state = real_entry_state(directory_fd, name)
    if exchange_calls[0] == 2 and name.startswith(".crosscheck-stage-") and stage_edit_calls[0] == 0:
        stage_edit_calls[0] += 1
        new_inode_handles[0].seek(0)
        new_inode_handles[0].truncate()
        new_inode_handles[0].write('{"setting":"late staged-new-inode edit"}\n')
        new_inode_handles[0].flush()
    return state

module._rename_exchange = retain_new_inode_descriptor
module._verify_parent_path = edit_displaced_original_then_fail
module._entry_state_at = edit_new_inode_after_stage_sample
try:
    module.publish_file(str(late_stage_race_dir), "settings.json", str(late_stage_snapshot), str(late_stage_file))
except module.ConcurrentUpdate as error:
    if not error.recovery_path:
        raise SystemExit("rollback did not report its displaced-original recovery link")
    backup_contents = {
        path.read_text()
        for path in Path(error.recovery_path).parent.glob("settings-*.bak")
    }
    if '{"setting":"late staged-new-inode edit"}\n' not in backup_contents:
        raise SystemExit("rollback cleanup discarded a late save through the staged inode")
    if late_stage_target.read_text() != '{"setting":"late original edit"}\n':
        raise SystemExit("rollback failed to keep the edited original inode live")
else:
    raise SystemExit("atomic publisher accepted a failed update after a displaced-original save")
finally:
    module._rename_exchange = real_exchange
    module._verify_parent_path = real_verify
    module._entry_state_at = real_entry_state
    original_handle.close()
    for new_inode_handle in new_inode_handles:
        new_inode_handle.close()

# If rollback cannot link the published inode and a writer saves after the
# final recovery sample, retain the staged entry and return a fatal status.
failed_backup_dir = scratch / "failed-published-backup-race"
failed_backup_dir.mkdir()
failed_backup_target = failed_backup_dir / "settings.json"
failed_backup_snapshot = scratch / "failed-published-backup-snapshot.json"
failed_backup_stage = scratch / "failed-published-backup-stage.json"
failed_backup_target.write_text('{"setting":"original"}\n')
failed_backup_snapshot.write_text('{"setting":"original"}\n')
failed_backup_stage.write_text('{"setting":"updated"}\n')
published_identity = [None]
exchange_count = [0]
published_handle = []
real_exchange = module._rename_exchange

def capture_published_inode(first_fd, first, second_fd, second):
    result = real_exchange(first_fd, first, second_fd, second)
    exchange_count[0] += 1
    if exchange_count[0] == 1:
        published_stat = os.stat(first, dir_fd=first_fd, follow_symlinks=False)
        published_identity[0] = (published_stat.st_dev, published_stat.st_ino)
        published_handle.append(failed_backup_target.open("r+"))
    return result

real_recovery_link = module._new_stable_recovery_link

def fail_published_inode_recovery(source_fd, source_name, recovery_fd, recovery_dir):
    source_stat = os.stat(source_name, dir_fd=source_fd, follow_symlinks=False)
    if (source_stat.st_dev, source_stat.st_ino) == published_identity[0]:
        raise OSError(errno.ENOSPC, "injected full recovery volume")
    return real_recovery_link(source_fd, source_name, recovery_fd, recovery_dir)

real_entry_state = module._entry_state_at
published_stage_reads = [0]

def write_after_final_published_sample(directory_fd, name):
    state = real_entry_state(directory_fd, name)
    if (
        exchange_count[0] == 2
        and name.startswith(".crosscheck-stage-")
        and state[0][:2] == published_identity[0]
    ):
        published_stage_reads[0] += 1
        if published_stage_reads[0] == 2:
            published_handle[0].seek(0)
            published_handle[0].truncate()
            published_handle[0].write('{"setting":"late published save"}\n')
            published_handle[0].flush()
    return state

real_verify = module._verify_parent_path

def fail_after_publishing(root_fd, root_path, relative_target, parent_fd):
    if published_identity[0] is not None:
        raise module.ConcurrentUpdate("injected post-publish failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._rename_exchange = capture_published_inode
module._new_stable_recovery_link = fail_published_inode_recovery
module._entry_state_at = write_after_final_published_sample
module._verify_parent_path = fail_after_publishing
try:
    module.publish_file(
        str(failed_backup_dir), "settings.json", str(failed_backup_snapshot), str(failed_backup_stage)
    )
except module.RestorationFailed as error:
    if not error.recovery_path or not Path(error.recovery_path).is_file():
        raise SystemExit("failed backup did not leave a reported staged recovery path")
    if Path(error.recovery_path).read_text() != '{"setting":"late published save"}\n':
        raise SystemExit("failed recovery-link creation discarded the late published save")
    if failed_backup_target.read_text() != '{"setting":"original"}\n':
        raise SystemExit("failed published backup rollback did not restore the original settings")
except module.ConcurrentUpdate:
    raise SystemExit("rollback reported safe recovery after the published inode backup failed")
else:
    raise SystemExit("rollback succeeded without a durable link to the published inode")
finally:
    module._rename_exchange = real_exchange
    module._new_stable_recovery_link = real_recovery_link
    module._entry_state_at = real_entry_state
    module._verify_parent_path = real_verify
    for handle in published_handle:
        handle.close()

# A byte-identical replacement is still a different displaced inode. Its
# held descriptor must remain visible through the returned recovery link.
inode_race_dir = scratch / "same-content-inode-race"
inode_race_dir.mkdir()
inode_race_target = inode_race_dir / "settings.json"
inode_race_snapshot = scratch / "same-content-inode-snapshot.json"
inode_race_stage = scratch / "same-content-inode-stage.json"
inode_race_target.write_text('{"setting":"original"}\n')
inode_race_snapshot.write_text('{"setting":"original"}\n')
inode_race_stage.write_text('{"setting":"updated"}\n')
held_replacement = []
real_exchange = module._rename_exchange
exchange_calls = [0]

def replace_with_identical_inode(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    if exchange_calls[0] == 1:
        replacement = inode_race_dir / "replacement.json"
        replacement.write_text('{"setting":"original"}\n')
        held_replacement.append(replacement.open("r+"))
        replacement.replace(inode_race_target)
    return real_exchange(first_fd, first, second_fd, second)

module._rename_exchange = replace_with_identical_inode
try:
    module.publish_file(str(inode_race_dir), "settings.json", str(inode_race_snapshot), str(inode_race_stage))
except module.ConcurrentUpdate as error:
    if not error.recovery_path:
        raise SystemExit("atomic publisher did not preserve the replaced inode")
    held_replacement[0].seek(0)
    held_replacement[0].truncate()
    held_replacement[0].write('{"setting":"late edit"}\n')
    held_replacement[0].flush()
    if Path(error.recovery_path).read_text() != '{"setting":"late edit"}\n':
        raise SystemExit("atomic publisher reported a backup of the wrong inode")
else:
    raise SystemExit("atomic publisher accepted a byte-identical replacement inode")
finally:
    module._rename_exchange = real_exchange
    for replacement_file in held_replacement:
        replacement_file.close()

# Failed rollback is surfaced with a distinct fatal status so callers do not
# mistake it for an ordinary preserved concurrent edit.
rollback_failure_dir = scratch / "rollback-failure"
rollback_failure_dir.mkdir()
rollback_failure_target = rollback_failure_dir / "settings.json"
rollback_failure_snapshot = scratch / "rollback-failure-snapshot.json"
rollback_failure_stage = scratch / "rollback-failure-stage.json"
rollback_failure_target.write_text('{"setting":"original"}\n')
rollback_failure_snapshot.write_text('{"setting":"original"}\n')
rollback_failure_stage.write_text('{"setting":"updated"}\n')
real_verify = module._verify_parent_path
verify_calls = [0]

def fail_after_exchange_again(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        raise module.ConcurrentUpdate("injected post-exchange verification failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

real_exchange = module._rename_exchange
exchange_calls = [0]

def fail_rollback_exchange(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    if exchange_calls[0] == 2:
        raise OSError(5, "injected rollback exchange failure")
    return real_exchange(first_fd, first, second_fd, second)

module._verify_parent_path = fail_after_exchange_again
module._rename_exchange = fail_rollback_exchange
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "publish", str(rollback_failure_dir), "settings.json",
    str(rollback_failure_snapshot), str(rollback_failure_stage),
]
try:
    if module.main() != 5:
        raise SystemExit("atomic publisher did not report incomplete restoration with fatal status 5")
finally:
    module.sys.argv = original_argv
    module._verify_parent_path = real_verify
    module._rename_exchange = real_exchange

# The Claude sync caller must count a race that became a no-op as preserved,
# not as an updated command.
noop_sync_root = scratch / "claude-noop-sync-repo"
noop_sync_home = scratch / "claude-noop-sync-home"
noop_sync_root.joinpath("claude/skill-sources").mkdir(parents=True)
noop_sync_root.joinpath("skill-sources").mkdir()
noop_sync_root.joinpath("scripts").mkdir()
noop_sync_home.joinpath(".claude/commands").mkdir(parents=True)
noop_sync_home.joinpath(".crosscheck").mkdir()
(noop_sync_root / "scripts/atomic-publish-file.py").write_bytes(Path(sys.argv[1]).read_bytes())
noop_sync_claude = noop_sync_root / "claude/skill-sources/managed.md"
noop_sync_root_skill = noop_sync_root / "skill-sources/managed.md"
noop_sync_claude.write_text("old Claude command\n")
noop_sync_root_skill.write_text("old root command\n")
subprocess.run(["git", "init", "-q", str(noop_sync_root)], check=True)
subprocess.run(["git", "-C", str(noop_sync_root), "add", "."], check=True)
subprocess.run(
    ["git", "-C", str(noop_sync_root), "-c", "user.name=CrossCheck test", "-c",
     "user.email=crosscheck-test@example.invalid", "commit", "-qm", "fixture"],
    check=True,
)
subprocess.run(
    ["git", "-C", str(noop_sync_root), "update-ref", "refs/remotes/origin/main", "HEAD"], check=True
)
noop_sync_claude.write_text("new Claude command\n")
noop_sync_target = noop_sync_home / ".claude/commands/managed.md"
noop_sync_target.symlink_to(noop_sync_root_skill)
readlink_shims = scratch / "readlink-shims"
readlink_shims.mkdir()
readlink_path = subprocess.run(["/usr/bin/which", "readlink"], check=True, text=True, capture_output=True).stdout.strip()
readlink_shim = readlink_shims / "readlink"
readlink_shim.write_text(
    "#!/bin/sh\n"
    'if [ "$1" = "$RACE_TARGET" ]; then\n'
    '  old_link=$("$REAL_READLINK" "$1")\n'
    '  ln -s "$RACE_NEW_LINK" "$RACE_TARGET.next"\n'
    '  mv -f "$RACE_TARGET.next" "$RACE_TARGET"\n'
    '  printf "%s\\n" "$old_link"\n'
    'else\n'
    '  exec "$REAL_READLINK" "$@"\n'
    'fi\n'
)
readlink_shim.chmod(0o755)
sync_env = os.environ.copy()
sync_env.update(
    PATH=f"{readlink_shims}:{sync_env['PATH']}",
    REAL_READLINK=readlink_path,
    RACE_TARGET=str(noop_sync_target.parent.resolve() / noop_sync_target.name),
    RACE_NEW_LINK=str(noop_sync_claude.resolve()),
)
sync_result = subprocess.run(
    ["bash", str(Path(sys.argv[1]).parents[1] / "claude/scripts/sync-managed-claude-skills.sh"),
     str(noop_sync_root), str(noop_sync_home)],
    check=False,
    text=True,
    capture_output=True,
    env=sync_env,
)
if sync_result.returncode != 0:
    raise SystemExit(f"Claude sync race fixture failed: {sync_result.stderr}\n{sync_result.stdout}")
if "Claude command links added or refreshed: 0; preserved 1" not in sync_result.stdout:
    raise SystemExit(
        "Claude sync counted a concurrent no-op as an updated command: "
        f"stdout={sync_result.stdout!r}; stderr={sync_result.stderr!r}; "
        f"link={os.readlink(noop_sync_target)!r}"
    )
if os.path.realpath(noop_sync_target) != str(noop_sync_claude.resolve()):
    raise SystemExit("Claude sync race fixture did not leave the user's current symlink live")

# If syncing the removal of a failed new symlink errors, still attempt to
# restore the displaced command before returning a fatal status.
symlink_rollback_home = scratch / "symlink-rollback-home"
symlink_rollback_home.joinpath(".claude/commands").mkdir(parents=True)
symlink_rollback_target = symlink_rollback_home / ".claude/commands/managed.md"
symlink_rollback_snapshot = scratch / "symlink-rollback-snapshot.md"
symlink_rollback_source = scratch / "symlink-rollback-source.md"
symlink_rollback_target.write_text("old command\n")
symlink_rollback_snapshot.write_text("old command\n")
symlink_rollback_source.write_text("new command\n")
real_verify = module._verify_parent_path
real_fsync = module.os.fsync
fsync_calls = [0]
verify_calls = [0]

def fail_after_install(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 1:
        raise module.ConcurrentUpdate("injected post-link verification failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

def fail_unlink_sync(directory_fd):
    fsync_calls[0] += 1
    if fsync_calls[0] >= 9 and not symlink_rollback_target.exists():
        raise OSError(5, "injected rollback directory fsync failure")
    return real_fsync(directory_fd)

module._verify_parent_path = fail_after_install
module.os.fsync = fail_unlink_sync
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "symlink", str(symlink_rollback_home),
    ".claude/commands/managed.md", "snapshot", str(symlink_rollback_snapshot),
    str(symlink_rollback_source),
]
try:
    if module.main() != 5:
        raise SystemExit("Claude symlink rollback failure did not return fatal status 5")
finally:
    module.sys.argv = original_argv
    module._verify_parent_path = real_verify
    module.os.fsync = real_fsync
if symlink_rollback_target.is_symlink() or symlink_rollback_target.read_text() != "old command\n":
    raise SystemExit("Claude symlink rollback left the live command missing")

# If the command directory moves after symlink creation, do not report a safe
# rollback through the detached directory descriptor as status 3.
moved_commands_home = scratch / "moved-commands-home"
moved_commands_dir = moved_commands_home / ".claude/commands"
moved_commands_dir.mkdir(parents=True)
moved_commands_target = moved_commands_dir / "managed.md"
moved_commands_snapshot = scratch / "moved-commands-snapshot.md"
moved_commands_source = scratch / "moved-commands-source.md"
moved_commands_target.write_text("old command\n")
moved_commands_snapshot.write_text("old command\n")
moved_commands_source.write_text("new command\n")
real_verify = module._verify_parent_path
verify_calls = [0]

def move_commands_dir_after_link(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 1:
        moved_commands_dir.rename(moved_commands_dir.with_name("commands-moved"))
        moved_commands_dir.mkdir()
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = move_commands_dir_after_link
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(moved_commands_home)
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "symlink", str(moved_commands_home),
    ".claude/commands/managed.md", "snapshot", str(moved_commands_snapshot),
    str(moved_commands_source),
]
try:
    if module.main() != 5:
        raise SystemExit("detached Claude command rollback was not reported as fatal status 5")
finally:
    module.sys.argv = original_argv
    module._verify_parent_path = real_verify
    os.environ["HOME"] = previous_home
stable_command_backups = list((moved_commands_home / ".crosscheck-recovery").glob("settings-*.bak"))
if not any(path.read_text() == "old command\n" for path in stable_command_backups):
    raise SystemExit("moved Claude command did not retain its stable recovery copy")
if moved_commands_target.exists() or moved_commands_target.is_symlink():
    raise SystemExit("test fixture unexpectedly restored through the detached command directory")

# If the command file is replaced with identical bytes after the initial
# recovery link, a later parent move must report a backup of the displaced inode.
replaced_commands_home = scratch / "replaced-commands-home"
replaced_commands_dir = replaced_commands_home / ".claude/commands"
replaced_commands_dir.mkdir(parents=True)
replaced_commands_target = replaced_commands_dir / "managed.md"
replaced_commands_snapshot = scratch / "replaced-commands-snapshot.md"
replaced_commands_source = scratch / "replaced-commands-source.md"
replaced_commands_target.write_text("old command\n")
replaced_commands_snapshot.write_text("old command\n")
replaced_commands_source.write_text("new command\n")
old_command_identity = (replaced_commands_target.stat().st_dev, replaced_commands_target.stat().st_ino)
displaced_command_identity = [None]
real_new_recovery_directory = module._new_recovery_directory

def replace_command_after_recovery_directory(parent_fd, parent_path):
    result = real_new_recovery_directory(parent_fd, parent_path)
    replacement_path = replaced_commands_target.with_name("managed.replacement")
    replacement_path.write_text("old command\n")
    os.replace(replacement_path, replaced_commands_target)
    replacement_stat = replaced_commands_target.stat()
    displaced_command_identity[0] = (replacement_stat.st_dev, replacement_stat.st_ino)
    return result

real_verify = module._verify_parent_path
parent_verify_calls = [0]

def move_replaced_command_parent(root_fd, root_path, relative_target, parent_fd):
    parent_verify_calls[0] += 1
    if parent_verify_calls[0] == 1:
        replaced_commands_dir.rename(replaced_commands_dir.with_name("commands-moved"))
        replaced_commands_dir.mkdir()
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._new_recovery_directory = replace_command_after_recovery_directory
module._verify_parent_path = move_replaced_command_parent
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(replaced_commands_home)
try:
    module.sync_symlink(
        str(replaced_commands_home), ".claude/commands/managed.md", "snapshot",
        str(replaced_commands_snapshot), str(replaced_commands_source),
    )
except module.RestorationFailed as error:
    if not error.recovery_path or not Path(error.recovery_path).is_file():
        raise SystemExit("moved parent did not report the displaced command recovery backup")
    recovery_stat = Path(error.recovery_path).stat()
    if (recovery_stat.st_dev, recovery_stat.st_ino) != displaced_command_identity[0]:
        raise SystemExit("moved parent reported a recovery backup for the pre-replacement inode")
else:
    raise SystemExit("moved command parent did not report incomplete restoration")
finally:
    module._new_recovery_directory = real_new_recovery_directory
    module._verify_parent_path = real_verify
    os.environ["HOME"] = previous_home
moved_replacement_entries = list(replaced_commands_home.rglob(".crosscheck-publish-*/original"))
if not any(
    (entry.stat().st_dev, entry.stat().st_ino) == displaced_command_identity[0]
    for entry in moved_replacement_entries
):
    raise SystemExit("moved command directory lost the actually displaced inode")
if (old_command_identity == displaced_command_identity[0]):
    raise SystemExit("test did not create a distinct byte-identical replacement inode")

# A symlink created after an absent-path check is a preserved no-op.
absent_race_home = scratch / "absent-link-race-home"
absent_race_home.joinpath(".claude/commands").mkdir(parents=True)
absent_race_target = absent_race_home / ".claude/commands/managed.md"
absent_race_source = scratch / "absent-link-race-source.md"
absent_race_source.write_text("new command\n")
real_symlink = module.os.symlink

def create_concurrent_desired_link(source, destination, **kwargs):
    real_symlink(source, destination, **kwargs)
    raise FileExistsError(errno.EEXIST, "injected concurrent symlink creation", destination)

module.os.symlink = create_concurrent_desired_link
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "symlink", str(absent_race_home),
    ".claude/commands/managed.md", "absent", "-", str(absent_race_source),
]
try:
    if module.main() != 4:
        raise SystemExit("concurrent Claude symlink creation did not return no-op status 4")
finally:
    module.sys.argv = original_argv
    module.os.symlink = real_symlink
if os.path.realpath(absent_race_target) != str(absent_race_source.resolve()):
    raise SystemExit("concurrent desired Claude symlink was not preserved")

# Recovery reports must not succeed after their opened directory is renamed.
recovery_rename_home = scratch / "recovery-rename-home"
recovery_rename_root = scratch / "recovery-rename-root"
recovery_rename_home.mkdir()
recovery_rename_root.mkdir()
recovery_rename_target = recovery_rename_root / "settings.json"
recovery_rename_snapshot = scratch / "recovery-rename-snapshot.json"
recovery_rename_stage = scratch / "recovery-rename-stage.json"
recovery_rename_target.write_text('{"setting":"original"}\n')
recovery_rename_snapshot.write_text('{"setting":"original"}\n')
recovery_rename_stage.write_text('{"setting":"updated"}\n')
real_recovery_link = module._new_stable_recovery_link
recovery_link_calls = [0]

def rename_recovery_directory_after_link(source_fd, source_name, recovery_fd, recovery_dir):
    result = real_recovery_link(source_fd, source_name, recovery_fd, recovery_dir)
    recovery_link_calls[0] += 1
    if recovery_link_calls[0] == 1:
        Path(recovery_dir).rename(Path(recovery_dir).with_name(".crosscheck-recovery-moved"))
    return result

module._new_stable_recovery_link = rename_recovery_directory_after_link
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(recovery_rename_home)
try:
    module.publish_file(
        str(recovery_rename_root), "settings.json", str(recovery_rename_snapshot), str(recovery_rename_stage)
    )
except OSError:
    pass
else:
    raise SystemExit("atomic publisher reported success with a moved recovery directory")
finally:
    os.environ["HOME"] = previous_home
    module._new_stable_recovery_link = real_recovery_link
if recovery_rename_target.read_text() != '{"setting":"original"}\n':
    raise SystemExit("publisher changed settings before validating the recovery pathname")

# Managed link no-ops have an explicit status instead of looking like updates.
noop_root = scratch / "managed-link-noop"
noop_target = noop_root / ".claude/commands/managed.md"
noop_target.parent.mkdir(parents=True)
noop_target.symlink_to("/current/managed.md")
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "symlink", str(noop_root), ".claude/commands/managed.md",
    "link", "/previous/managed.md", "/current/managed.md",
]
try:
    if module.main() != 4:
        raise SystemExit("managed link no-op did not return its distinct status 4")
finally:
    module.sys.argv = original_argv

# A directory symlink introduced during staging must not redirect publication.
link_root = scratch / "codex-home"
skill_dir = link_root / ".codex/skills/example"
outside = scratch / "outside"
skill_dir.mkdir(parents=True)
outside.mkdir()
link_stage = scratch / "skill-stage"
link_stage.write_text("managed skill\n")
real_copy = module._copy_into_directory

def swap_skill_directory(source_path, directory_fd):
    moved_dir = skill_dir.with_name("example-moved")
    skill_dir.rename(moved_dir)
    skill_dir.symlink_to(outside, target_is_directory=True)
    return real_copy(source_path, directory_fd)

module._copy_into_directory = swap_skill_directory
try:
    module.publish_file(str(link_root), ".codex/skills/example/SKILL.md", None, str(link_stage))
except (module.ConcurrentUpdate, OSError):
    pass
else:
    raise SystemExit("atomic publisher followed a directory symlink introduced during staging")
finally:
    module._copy_into_directory = real_copy
if (outside / "SKILL.md").exists():
    raise SystemExit("atomic publisher wrote a Codex skill through a concurrent directory symlink")

# A successful first-time publish must sync the directory after the final rename.
absent_publish_root = scratch / "absent-publish-fsync"
absent_publish_root.mkdir()
absent_publish_target = absent_publish_root / "settings.json"
absent_publish_stage = scratch / "absent-publish-stage.json"
absent_publish_stage.write_text('{"setting":"first"}\n')
real_fsync_directory = module._fsync_directory
final_sync_failed = [False]

def fail_final_publish_directory_sync(directory_fd):
    if absent_publish_target.exists():
        raise OSError(errno.EIO, "injected final publish directory fsync failure")
    return real_fsync_directory(directory_fd)

module._fsync_directory = fail_final_publish_directory_sync
try:
    module.publish_file(str(absent_publish_root), "settings.json", None, str(absent_publish_stage))
except OSError as error:
    if error.errno != errno.EIO:
        raise SystemExit(f"final publish sync failed with the wrong error: {error}")
    final_sync_failed[0] = True
finally:
    module._fsync_directory = real_fsync_directory
if not final_sync_failed[0]:
    raise SystemExit("first-time publish returned success without syncing its final name")
if not absent_publish_target.is_file() or absent_publish_target.read_text() != '{"setting":"first"}\n':
    raise SystemExit("final publish sync failure did not leave the first-published file intact")

# Managed Claude-copy migration must preserve a concurrent editor save.
claude_home = scratch / "claude-home"
command_dir = claude_home / ".claude/commands"
command_dir.mkdir(parents=True)
command = command_dir / "managed.md"
command_snapshot = scratch / "command-snapshot.md"
command.write_text("published command\n")
command_snapshot.write_text("published command\n")
command_fd = command.open("r+")
command_backup = module.sync_symlink(
    str(claude_home), ".claude/commands/managed.md", "snapshot", str(command_snapshot), "/repo/claude/skill-sources/managed.md"
)
if not command.is_symlink() or not command_backup:
    raise SystemExit("managed Claude command was not migrated with a recovery copy")
command_fd.seek(0)
command_fd.truncate()
command_fd.write("late user edit\n")
command_fd.flush()
command_fd.close()
if Path(command_backup).read_text() != "late user edit\n":
    raise SystemExit("Claude command migration lost a save through an open file descriptor")

race_dir = scratch / "command-race-home"
race_command = race_dir / ".claude/commands/managed.md"
race_command.parent.mkdir(parents=True)
race_snapshot = scratch / "command-race-snapshot.md"
race_command.write_text("published command\n")
race_snapshot.write_text("published command\n")
real_rename = module._rename_noreplace

def edit_command_after_claim(source_fd, source, destination_fd, destination):
    result = real_rename(source_fd, source, destination_fd, destination)
    if destination == "original" and source == "managed.md":
        (race_command.parent / next(race_command.parent.glob(".crosscheck-publish-*")) / "original").write_text("concurrent user edit\n")
    return result

module._rename_noreplace = edit_command_after_claim
try:
    module.sync_symlink(
        str(race_dir), ".claude/commands/managed.md", "snapshot", str(race_snapshot), "/repo/claude/skill-sources/managed.md"
    )
finally:
    module._rename_noreplace = real_rename
if race_command.is_symlink() or race_command.read_text() != "concurrent user edit\n":
    raise SystemExit("Claude command migration replaced a concurrently edited command")
PY

CRITICAL_HOME="$TEMP_DIR/critical-settings-home"
mkdir -p "$CRITICAL_HOME/.claude"
printf '{"permissions":{"deny":[],"ask":[]},"custom":"keep"}\n' > "$CRITICAL_HOME/.claude/actual.json"
ln -s "$CRITICAL_HOME/.claude/actual.json" "$CRITICAL_HOME/.claude/settings.json"
TMPDIR="$TEMP_DIR" "$REPO_ROOT/scripts/sync-critical-settings.sh" "$CRITICAL_HOME/.claude/settings.json" --include-ask
if [ ! -L "$CRITICAL_HOME/.claude/settings.json" ] || ! jq -e '.custom == "keep" and (.permissions.deny | length == 6) and (.permissions.ask | index("Bash(gh api *)") != null)' "$CRITICAL_HOME/.claude/settings.json" >/dev/null; then
  echo "critical settings sync replaced its symlink or missed a security rule" >&2
  exit 1
fi
for install_guide in "$REPO_ROOT/skill-sources/INSTALL.md" "$REPO_ROOT/claude/skill-sources/INSTALL.md"; do
  if ! grep -Fq 'sync-managed-claude-skills.sh ~/.crosscheck "$HOME"' "$install_guide"; then
    echo "install guide does not use the managed Claude command sync: $install_guide" >&2
    exit 1
  fi
  if grep -Fq 'cp ~/.crosscheck/claude/skill-sources/*.md ~/.claude/commands/' "$install_guide"; then
    echo "install guide still copies Claude commands through existing destination symlinks: $install_guide" >&2
    exit 1
  fi
done
for troubleshooting in "$REPO_ROOT/TROUBLESHOOTING.md" "$REPO_ROOT/claude/TROUBLESHOOTING.md"; do
  if ! grep -Fq 'sync-managed-claude-skills.sh ~/Documents/Developer/CrossCheck "$HOME"' "$troubleshooting"; then
    echo "troubleshooting guide does not use the managed Claude command sync: $troubleshooting" >&2
    exit 1
  fi
  if grep -Fq 'cp ~/Documents/Developer/CrossCheck/skill-sources/*.md ~/.claude/commands/' "$troubleshooting" || grep -Fq '35 files (34 skills + INSTALL.md)' "$troubleshooting"; then
    echo "troubleshooting guide still recommends unsafe copying or counts INSTALL.md as a command: $troubleshooting" >&2
    exit 1
  fi
done
if ! grep -Fq 'sync-managed-codex-skills.sh ~/Documents/Developer/CrossCheck "$HOME"' "$REPO_ROOT/codex/TROUBLESHOOTING.md"; then
  echo "Codex troubleshooting guide does not use the managed native-skill sync" >&2
  exit 1
fi
if grep -Fq 'cp -R ~/Documents/Developer/CrossCheck/codex/skills/* ~/.codex/skills/' "$REPO_ROOT/codex/TROUBLESHOOTING.md" || grep -Fq 'cp -R ~/Documents/Developer/CrossCheck/codex/skills/* ~/.codex/skills/' "$REPO_ROOT/codex/skills/INSTALL.md"; then
  echo "Codex documentation still recommends recursive skill copying" >&2
  exit 1
fi
if ! grep -Fq 'sync-managed-codex-skills.sh ~/Documents/Developer/CrossCheck "$HOME"' "$REPO_ROOT/codex/skills/INSTALL.md"; then
  echo "Codex skill installation guide does not use the managed native-skill sync" >&2
  exit 1
fi
if ! grep -Fq 'sync-managed-codex-skills.sh' "$REPO_ROOT/codex/scripts/bootstrap-crosscheck.sh"; then
  echo "Codex bootstrap does not use the managed native-skill sync" >&2
  exit 1
fi
if grep -Fq 'cp -R ~/.crosscheck/codex/skills/* ~/.codex/skills/' "$REPO_ROOT/skill-sources/INSTALL.md" || ! grep -Fq 'sync-managed-codex-skills.sh ~/.crosscheck "$HOME"' "$REPO_ROOT/skill-sources/INSTALL.md"; then
  echo "root installation guide does not use safe managed Codex skill sync" >&2
  exit 1
fi
if ! grep -Fq 'atomic-publish-file.py" publish' "$REPO_ROOT/codex/scripts/bootstrap-crosscheck.sh" || ! grep -Fq 'sync-critical-settings.sh' "$REPO_ROOT/codex/scripts/bootstrap-crosscheck.sh"; then
  echo "Codex bootstrap does not publish and update settings through the safe helpers" >&2
  exit 1
fi

SYNC_ROOT="$TEMP_DIR/crosscheck"
HOME_FIXTURE="$TEMP_DIR/home-sync"
EMPTY_GIT_CONFIG="$TEMP_DIR/empty-git-config"
: > "$EMPTY_GIT_CONFIG"
mkdir -p "$SYNC_ROOT/claude/skill-sources" "$SYNC_ROOT/skill-sources" "$SYNC_ROOT/scripts" "$HOME_FIXTURE/.claude/commands" "$HOME_FIXTURE/.crosscheck"
cp "$REPO_ROOT/scripts/atomic-publish-file.py" "$SYNC_ROOT/scripts/atomic-publish-file.py"
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
COUNT_HOME="$TEMP_DIR/claude-sync-count-home"
mkdir -p "$COUNT_HOME"
COUNT_OUTPUT="$("$REPO_ROOT/claude/scripts/sync-managed-claude-skills.sh" "$SYNC_ROOT" "$COUNT_HOME" --count-only 2> "$TEMP_DIR/claude-sync-count-summary")"
case "$COUNT_OUTPUT" in
  ''|*[!0-9]*)
    echo "Claude sync count mode did not return an integer: $COUNT_OUTPUT" >&2
    exit 1
    ;;
esac
if [ "$COUNT_OUTPUT" -eq 0 ]; then
  echo "Claude sync count mode did not count links from a fresh home" >&2
  exit 1
fi
if ! grep -Fq 'Claude command links added or refreshed:' "$TEMP_DIR/claude-sync-count-summary"; then
  echo "Claude sync count mode omitted its human-readable summary" >&2
  exit 1
fi

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
