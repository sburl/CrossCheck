#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-supply-chain-hook.sh"
TEMP_DIR="$(mktemp -d)"
CROSS_FS_TMP=""
trap 'rm -rf "$TEMP_DIR" "$CROSS_FS_TMP"' EXIT
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
python3 - "$SETTINGS" <<'PY'
import json
import sys
from pathlib import Path

settings = Path(sys.argv[1])
settings.write_text(json.dumps(json.loads(settings.read_text()), separators=(",", ":")) + "\n")
PY
HOOK_SETTINGS_INODE="$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(f"{s.st_dev}:{s.st_ino}")' "$SETTINGS")"
HOOK_BACKUP_COUNT="$(find "$HOME/.crosscheck-recovery" -maxdepth 1 -name 'settings-*.bak' -type f 2>/dev/null | wc -l | tr -d ' ')"
if ! "$INSTALLER" "$SETTINGS" "$HOOK" | grep -Fq 'already current'; then
  echo "installer did not report an unchanged semantic-settings no-op" >&2
  exit 1
fi
if [ "$HOOK_SETTINGS_INODE" != "$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(f"{s.st_dev}:{s.st_ino}")' "$SETTINGS")" ] \
  || [ "$HOOK_BACKUP_COUNT" != "$(find "$HOME/.crosscheck-recovery" -maxdepth 1 -name 'settings-*.bak' -type f 2>/dev/null | wc -l | tr -d ' ')" ]; then
  echo "unchanged installer replaced the settings inode or added a recovery backup" >&2
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
PRIVATE_HOME="$TEMP_DIR/private-settings-home"
mkdir -p "$PRIVATE_HOME/.claude"
chmod 0700 "$PRIVATE_HOME/.claude"
PRIVATE_SETTINGS="$PRIVATE_HOME/.claude/settings.json"
PRIVATE_JQ_BIN="$TEMP_DIR/private-jq-bin"
PRIVATE_MODE_MARKER="$TEMP_DIR/private-settings-temp-mode"
PRIVATE_SNAPSHOT_MODE_MARKER="$TEMP_DIR/private-settings-snapshot-mode"
PRIVATE_SHARED_TMP="$(mktemp -d /tmp/crosscheck-shared-temp.XXXXXX)"
chmod 1777 "$PRIVATE_SHARED_TMP"
trap 'rm -rf "$TEMP_DIR" "$PRIVATE_SHARED_TMP" "$CROSS_FS_TMP"' EXIT
mkdir -p "$PRIVATE_JQ_BIN"
printf '{"privateValue":"fixture"}\n' > "$PRIVATE_SETTINGS"
chmod 0644 "$PRIVATE_SETTINGS"
REAL_JQ="$(command -v jq)"
REAL_PYTHON="$(command -v python3)"
cat > "$PRIVATE_JQ_BIN/python3" <<'SH'
#!/usr/bin/env bash
set -e
if [ "$1" = "$PRIVATE_PUBLISH_HELPER" ] && [ "$2" = snapshot ]; then
  "$REAL_PYTHON" "$@"
  "$REAL_PYTHON" - "$5" "$PRIVATE_SNAPSHOT_MODE_MARKER" <<'PY'
import os
import stat
import sys

mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
open(sys.argv[2], "w").write(oct(mode))
if mode != 0o600:
    raise SystemExit(f"settings snapshot is exposed in shared TMPDIR with mode {oct(mode)}")
PY
  exit 0
fi
exec "$REAL_PYTHON" "$@"
SH
chmod +x "$PRIVATE_JQ_BIN/python3"
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
  PATH="$PRIVATE_JQ_BIN:$PATH" TMPDIR="$PRIVATE_SHARED_TMP" REAL_JQ="$REAL_JQ" REAL_PYTHON="$REAL_PYTHON" PRIVATE_PUBLISH_HELPER="$REPO_ROOT/scripts/atomic-publish-file.py" PRIVATE_SNAPSHOT_MODE_MARKER="$PRIVATE_SNAPSHOT_MODE_MARKER" TEMP_MODE_MARKER="$PRIVATE_MODE_MARKER" TEMP_MODE_TARGET="$PRIVATE_SETTINGS" "$INSTALLER" "$PRIVATE_SETTINGS" "$HOOK"
)
if [ "$(cat "$PRIVATE_MODE_MARKER")" != "0o600" ] || [ "$(cat "$PRIVATE_SNAPSHOT_MODE_MARKER")" != "0o600" ] || [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$PRIVATE_SETTINGS")" != "0o644" ]; then
  echo "installer did not keep private settings and its intermediate file at mode 0600" >&2
  exit 1
fi
if find "$PRIVATE_SHARED_TMP" -mindepth 1 -print -quit | grep -q .; then
  echo "installer left its private staged settings file in TMPDIR" >&2
  exit 1
fi

for SETTINGS_SYNC in "$REPO_ROOT/scripts/sync-critical-settings.sh" \
  "$REPO_ROOT/claude/scripts/sync-critical-settings.sh" \
  "$REPO_ROOT/codex/scripts/sync-critical-settings.sh"; do
  printf '{"privateValue":"fixture"}\n' > "$PRIVATE_SETTINGS"
  chmod 0644 "$PRIVATE_SETTINGS"
  rm -f "$PRIVATE_MODE_MARKER" "$PRIVATE_SNAPSHOT_MODE_MARKER"
  (
    umask 022
    PATH="$PRIVATE_JQ_BIN:$PATH" TMPDIR="$PRIVATE_SHARED_TMP" REAL_JQ="$REAL_JQ" \
      REAL_PYTHON="$REAL_PYTHON" PRIVATE_PUBLISH_HELPER="$REPO_ROOT/scripts/atomic-publish-file.py" \
      PRIVATE_SNAPSHOT_MODE_MARKER="$PRIVATE_SNAPSHOT_MODE_MARKER" TEMP_MODE_MARKER="$PRIVATE_MODE_MARKER" \
      TEMP_MODE_TARGET="$PRIVATE_SETTINGS" "$SETTINGS_SYNC" "$PRIVATE_SETTINGS"
  )
  if [ "$(cat "$PRIVATE_MODE_MARKER")" != "0o600" ] \
    || [ "$(cat "$PRIVATE_SNAPSHOT_MODE_MARKER")" != "0o600" ] \
    || [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$PRIVATE_SETTINGS")" != "0o644" ]; then
    echo "$SETTINGS_SYNC did not keep settings snapshots and staged files private" >&2
    exit 1
  fi
  if find "$PRIVATE_SHARED_TMP" -mindepth 1 -print -quit | grep -q .; then
    echo "$SETTINGS_SYNC left private intermediate files in TMPDIR" >&2
    exit 1
  fi
done

run_bootstrap_with_declines() {
  local home="$1"
  local script="$2"
  local scenario="$3"
  local temporary_directory="${4:-$TEMP_DIR}"
  BOOTSTRAP_HOME="$home" BOOTSTRAP_SCRIPT="$script" BOOTSTRAP_SCENARIO="$scenario" TMPDIR="$temporary_directory" python3 <<'PY'
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
decline_response = b"n\n" if "/codex/scripts/" in script else b"n"
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
                    os.write(fd, decline_response)
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

for bootstrap in root claude codex; do
  BOOTSTRAP_REPO="$TEMP_DIR/workspace/$bootstrap/CrossCheck"
  BOOTSTRAP_HOME="$TEMP_DIR/home-$bootstrap"
  mkdir -p "$(dirname "$BOOTSTRAP_REPO")" "$BOOTSTRAP_HOME"
  python3 - "$REPO_ROOT" "$BOOTSTRAP_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
  if [ "$bootstrap" = root ]; then
    SCRIPT="$BOOTSTRAP_REPO/scripts/bootstrap-crosscheck.sh"
  elif [ "$bootstrap" = claude ]; then
    SCRIPT="$BOOTSTRAP_REPO/claude/scripts/bootstrap-crosscheck.sh"
  else
    SCRIPT="$BOOTSTRAP_REPO/codex/scripts/bootstrap-crosscheck.sh"
  fi

  run_bootstrap_with_declines "$BOOTSTRAP_HOME" "$SCRIPT" "fresh settings install"

  if [ "$bootstrap" = codex ]; then
    SETTINGS="$BOOTSTRAP_HOME/.codex/settings.json"
    COMMAND_LINK="$BOOTSTRAP_HOME/.codex/skills/update-crosscheck/SKILL.md"
    EXPECTED_COMMAND="$BOOTSTRAP_REPO/codex/skills/update-crosscheck/SKILL.md"
    jq -e '
      .model == "gpt-5-codex" and
      .env.CODEX_EXPERIMENTAL_AGENT_TEAMS == "1" and
      ((.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // "") == "") and
      (.permissions.deny as $deny | [
        "Bash(gh*--admin*)", "Bash(*--admin*)", "Bash(gh api*rulesets*)",
        "Bash(gh api*branches/*/protection*)", "Bash(*graphql*BranchProtection*)",
        "Bash(*graphql*Ruleset*)"
      ] | all(.[]; . as $rule | $deny | index($rule) != null))
    ' "$SETTINGS" >/dev/null
  else
    SETTINGS="$BOOTSTRAP_HOME/.claude/settings.json"
    COMMAND_LINK="$BOOTSTRAP_HOME/.claude/commands/update-crosscheck.md"
    EXPECTED_COMMAND="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BOOTSTRAP_REPO/claude/skill-sources/update-crosscheck.md")"
    jq -e '
      (.hooks.PreToolUse | type == "array") and
      (.permissions.deny as $deny | [
      "Bash(gh*--admin*)", "Bash(*--admin*)", "Bash(gh api*rulesets*)",
      "Bash(gh api*branches/*/protection*)", "Bash(*graphql*BranchProtection*)",
      "Bash(*graphql*Ruleset*)"
      ] | all(.[]; . as $rule | $deny | index($rule) != null))
    ' "$SETTINGS" >/dev/null
  fi
  [ -f "$SETTINGS" ]
  [ ! -L "$SETTINGS" ]
  jq -e 'has("PreToolUse") | not' "$SETTINGS" >/dev/null
  if [ "$bootstrap" = codex ]; then
    if [ ! -f "$COMMAND_LINK" ] || ! cmp -s "$EXPECTED_COMMAND" "$COMMAND_LINK"; then
      echo "Codex bootstrap did not install the managed native skill from $EXPECTED_COMMAND" >&2
      exit 1
    fi
  else
    ACTUAL_COMMAND="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$COMMAND_LINK")"
    if [ ! -L "$COMMAND_LINK" ] || [ "$ACTUAL_COMMAND" != "$EXPECTED_COMMAND" ]; then
      echo "$bootstrap bootstrap installed $ACTUAL_COMMAND, expected $EXPECTED_COMMAND" >&2
      exit 1
    fi
  fi
done

# Bootstrap stages for settings must stay on the destination filesystem even
# when TMPDIR is mounted separately (for example, /dev/shm on Linux).
if [ -d /dev/shm ] && [ "$(stat -c '%d' /dev/shm)" != "$(stat -c '%d' "$TEMP_DIR")" ]; then
  CROSS_FS_TMP="$(mktemp -d /dev/shm/crosscheck-separate-temp.XXXXXX)"
  chmod 0700 "$CROSS_FS_TMP"
  for bootstrap in root claude codex; do
    CROSS_FS_HOME="$TEMP_DIR/home-separate-tmp-$bootstrap"
    if [ "$bootstrap" = root ]; then
      CROSS_FS_SCRIPT="$TEMP_DIR/workspace/root/CrossCheck/scripts/bootstrap-crosscheck.sh"
      CROSS_FS_SETTINGS="$CROSS_FS_HOME/.claude/settings.json"
    elif [ "$bootstrap" = claude ]; then
      CROSS_FS_SCRIPT="$TEMP_DIR/workspace/claude/CrossCheck/claude/scripts/bootstrap-crosscheck.sh"
      CROSS_FS_SETTINGS="$CROSS_FS_HOME/.claude/settings.json"
    else
      CROSS_FS_SCRIPT="$TEMP_DIR/workspace/codex/CrossCheck/codex/scripts/bootstrap-crosscheck.sh"
      CROSS_FS_SETTINGS="$CROSS_FS_HOME/.codex/settings.json"
    fi
    mkdir -p "$CROSS_FS_HOME"
    run_bootstrap_with_declines "$CROSS_FS_HOME" "$CROSS_FS_SCRIPT" "separate-filesystem TMPDIR" "$CROSS_FS_TMP"
    if [ ! -f "$CROSS_FS_SETTINGS" ]; then
      echo "$bootstrap bootstrap did not publish settings with a separate-filesystem TMPDIR" >&2
      exit 1
    fi
  done
  rm -rf "$CROSS_FS_TMP"
fi

# Codex bootstrap must preserve every user byte around the managed block,
# including CRLF line endings and Markdown hard breaks, while retaining mode.
CODEX_BYTE_REPO="$TEMP_DIR/workspace/codex-byte-preservation/CrossCheck"
CODEX_BYTE_HOME="$TEMP_DIR/home-codex-byte-preservation"
CODEX_BYTE_SCRIPT="$CODEX_BYTE_REPO/codex/scripts/bootstrap-crosscheck.sh"
mkdir -p "$(dirname "$CODEX_BYTE_REPO")" "$CODEX_BYTE_HOME/.codex"
python3 - "$REPO_ROOT" "$CODEX_BYTE_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
CODEX_BYTE_PREFIX=$'## personal\r\nline with hard break  \r\nnext line\r\n'
CODEX_BYTE_OLD_BLOCK=$'<!-- BEGIN CrossCheck managed workflow -->\r\nold managed workflow\r\n<!-- END CrossCheck managed workflow -->'
CODEX_BYTE_SUFFIX=$'\r\n## preserved tail\r\nlast hard break  \r\n'
printf '%s' "$CODEX_BYTE_PREFIX$CODEX_BYTE_OLD_BLOCK$CODEX_BYTE_SUFFIX" > "$CODEX_BYTE_HOME/.codex/AGENTS.md"
chmod 0640 "$CODEX_BYTE_HOME/.codex/AGENTS.md"
run_bootstrap_with_declines "$CODEX_BYTE_HOME" "$CODEX_BYTE_SCRIPT" "Codex existing instruction byte preservation"
python3 - "$CODEX_BYTE_HOME/.codex/AGENTS.md" "$CODEX_BYTE_REPO/codex/CODEX.md" <<'PY'
import os
import stat
import sys
from pathlib import Path

actual = Path(sys.argv[1]).read_bytes()
workflow = Path(sys.argv[2]).resolve()
prefix = b"## personal\r\nline with hard break  \r\nnext line\r\n"
suffix = b"\r\n## preserved tail\r\nlast hard break  \r\n"
expected_block = (
    b"<!-- BEGIN CrossCheck managed workflow -->\r\n"
    + f"Read and follow the CrossCheck Codex workflow at {workflow}".encode()
    + b"\r\n<!-- END CrossCheck managed workflow -->"
)
if not actual.startswith(prefix) or not actual.endswith(suffix):
    raise SystemExit("Codex bootstrap changed user bytes outside its managed workflow block")
if actual.count(expected_block) != 1:
    raise SystemExit("Codex bootstrap did not install one CRLF managed workflow block")
if stat.S_IMODE(os.stat(sys.argv[1]).st_mode) != 0o640:
    raise SystemExit("Codex bootstrap changed the existing AGENTS.md mode")
PY

# Codex bootstrap must reject a replacement .codex symlink at the settings
# sync boundary, including when settings existed during the shell preflight.
CODEX_SETTINGS_RACE_REPO="$TEMP_DIR/workspace/codex-settings-symlink-race/CrossCheck"
CODEX_SETTINGS_RACE_HOME="$TEMP_DIR/home-codex-settings-symlink-race"
CODEX_SETTINGS_RACE_OUTSIDE="$TEMP_DIR/codex-settings-symlink-outside"
CODEX_SETTINGS_RACE_MARKER="$TEMP_DIR/codex-settings-symlink-swapped"
mkdir -p "$(dirname "$CODEX_SETTINGS_RACE_REPO")" "$CODEX_SETTINGS_RACE_HOME/.codex" "$CODEX_SETTINGS_RACE_OUTSIDE"
python3 - "$REPO_ROOT" "$CODEX_SETTINGS_RACE_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
printf '{"permissions":{"deny":[]}}\n' > "$CODEX_SETTINGS_RACE_HOME/.codex/settings.json"
printf '{"outside":"must stay unchanged"}\n' > "$CODEX_SETTINGS_RACE_OUTSIDE/settings.json"
mv "$CODEX_SETTINGS_RACE_REPO/scripts/sync-critical-settings.sh" \
  "$CODEX_SETTINGS_RACE_REPO/scripts/sync-critical-settings-real.sh"
cat > "$CODEX_SETTINGS_RACE_REPO/scripts/sync-critical-settings.sh" <<'SH'
#!/usr/bin/env bash
set -e
if [ "$1" = "$HOME/.codex/settings.json" ] && [ ! -e "$CODEX_SETTINGS_RACE_MARKER" ]; then
  mv "$HOME/.codex" "$HOME/.codex-before-symlink"
  ln -s "$CODEX_SETTINGS_RACE_OUTSIDE" "$HOME/.codex"
  : > "$CODEX_SETTINGS_RACE_MARKER"
fi
exec "$(dirname "$0")/sync-critical-settings-real.sh" "$@"
SH
chmod +x "$CODEX_SETTINGS_RACE_REPO/scripts/sync-critical-settings.sh"
if HOME="$CODEX_SETTINGS_RACE_HOME" CODEX_SETTINGS_RACE_MARKER="$CODEX_SETTINGS_RACE_MARKER" \
  CODEX_SETTINGS_RACE_OUTSIDE="$CODEX_SETTINGS_RACE_OUTSIDE" TMPDIR="$TEMP_DIR" \
  bash "$CODEX_SETTINGS_RACE_REPO/codex/scripts/bootstrap-crosscheck.sh" \
  > "$TEMP_DIR/codex-settings-symlink-race.log" 2>&1; then
  echo "Codex bootstrap followed a replacement .codex symlink while syncing settings" >&2
  exit 1
fi
if [ ! -e "$CODEX_SETTINGS_RACE_MARKER" ] \
  || ! grep -Fq "Settings changed or became unsafe while it was being read" "$TEMP_DIR/codex-settings-symlink-race.log" \
  || [ "$(cat "$CODEX_SETTINGS_RACE_OUTSIDE/settings.json")" != '{"outside":"must stay unchanged"}' ]; then
  echo "Codex bootstrap did not fail safely on a replacement .codex symlink" >&2
  cat "$TEMP_DIR/codex-settings-symlink-race.log" >&2
  exit 1
fi

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
for bootstrap in root claude codex; do
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
    FAIL_SETTINGS="$FAIL_HOME/.claude/settings.json"
    EXPECTED_VALIDATION='Claude settings file must contain exactly one valid JSON object:'
  elif [ "$bootstrap" = claude ]; then
    FAIL_TEMPLATE="$FAIL_REPO/claude/settings.template.json"
    FAIL_SCRIPT="$FAIL_REPO/claude/scripts/bootstrap-crosscheck.sh"
    FAIL_SETTINGS="$FAIL_HOME/.claude/settings.json"
    EXPECTED_VALIDATION='Claude settings file must contain exactly one valid JSON object:'
  else
    FAIL_TEMPLATE="$FAIL_REPO/codex/settings.template.json"
    FAIL_SCRIPT="$FAIL_REPO/codex/scripts/bootstrap-crosscheck.sh"
    FAIL_SETTINGS="$FAIL_HOME/.codex/settings.json"
    EXPECTED_VALIDATION='Settings must contain exactly one valid JSON object:'
  fi
  printf '{not valid json\n' > "$FAIL_TEMPLATE"
  if HOME="$FAIL_HOME" TMPDIR="$TEMP_DIR" bash "$FAIL_SCRIPT" > "$TEMP_DIR/bootstrap-failure-$bootstrap.log" 2>&1; then
    echo "$bootstrap bootstrap unexpectedly accepted an invalid settings template" >&2
    exit 1
  fi
  if ! grep -Fq "$EXPECTED_VALIDATION" "$TEMP_DIR/bootstrap-failure-$bootstrap.log"; then
    echo "$bootstrap bootstrap failed without the installer's settings validation diagnostic" >&2
    cat "$TEMP_DIR/bootstrap-failure-$bootstrap.log" >&2
    exit 1
  fi
  if [ -e "$FAIL_SETTINGS" ] || [ -L "$FAIL_SETTINGS" ] \
    || find "$FAIL_HOME" -maxdepth 2 -name '.crosscheck-settings.*' -print -quit | grep -q . \
    || find "$TEMP_DIR" -maxdepth 1 -name 'crosscheck-codex-agents.*' -print -quit | grep -q .; then
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
  "$HOME"/.claude/.crosscheck-settings.*)
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
    if HOME="$RACE_HOME" TMPDIR="$TEMP_DIR" RACE_TARGET_KIND="$race_kind" RACE_JQ_BIN="$RACE_JQ_BIN" RACE_REAL_JQ="$RACE_REAL_JQ" bash "$RACE_SCRIPT" > "$TEMP_DIR/bootstrap-directory-race-$bootstrap.log" 2>&1; then
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
      if HOME="$RACE_HOME" TMPDIR="$TEMP_DIR" RACE_TARGET_KIND="$race_kind" RACE_JQ_BIN="$RACE_JQ_BIN" RACE_REAL_JQ="$RACE_REAL_JQ" bash "$RACE_SCRIPT" > "$TEMP_DIR/bootstrap-edit-race-$bootstrap.log" 2>&1; then
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
  if find "$RACE_HOME/.claude" -maxdepth 1 -name '.crosscheck-settings.*' -print -quit | grep -q .; then
    echo "$bootstrap bootstrap left its validated settings stage after resolving a publish collision" >&2
    exit 1
  fi
  done
done

# Both Claude entry points must fail visibly when syncing the first live
# settings directory fails after its no-clobber publish.
DIRSYNC_REPO="$TEMP_DIR/workspace/bootstrap-dirsync-failure/CrossCheck"
mkdir -p "$(dirname "$DIRSYNC_REPO")"
python3 - "$REPO_ROOT" "$DIRSYNC_REPO" <<'PY'
import shutil
import sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(".git"))
PY
DIRSYNC_REAL_HELPER="$DIRSYNC_REPO/scripts/atomic-publish-file-real.py"
mv "$DIRSYNC_REPO/scripts/atomic-publish-file.py" "$DIRSYNC_REAL_HELPER"
cat > "$DIRSYNC_REPO/scripts/atomic-publish-file.py" <<'PY'
#!/usr/bin/env python3
import errno
import importlib.util
import os
import sys

helper_path = os.path.join(os.path.dirname(__file__), "atomic-publish-file-real.py")
spec = importlib.util.spec_from_file_location("atomic_publish_file_real", helper_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if (
    len(sys.argv) >= 6
    and sys.argv[1] == "publish"
    and os.path.abspath(sys.argv[2]) == os.path.abspath(os.environ["HOME"])
    and sys.argv[3] == ".claude/settings.json"
    and sys.argv[4] == "--absent"
):
    real_fsync_directory = module._fsync_directory
    target = os.path.join(os.environ["HOME"], ".claude", "settings.json")

    def fail_after_live_settings_publish(directory_fd):
        if os.path.lexists(target):
            raise OSError(errno.EIO, "injected live settings directory sync failure")
        return real_fsync_directory(directory_fd)

    module._fsync_directory = fail_after_live_settings_publish
sys.exit(module.main())
PY
chmod +x "$DIRSYNC_REPO/scripts/atomic-publish-file.py"
for bootstrap in root claude; do
  DIRSYNC_HOME="$TEMP_DIR/home-dirsync-$bootstrap"
  mkdir -p "$DIRSYNC_HOME"
  if [ "$bootstrap" = root ]; then
    DIRSYNC_SCRIPT="$DIRSYNC_REPO/scripts/bootstrap-crosscheck.sh"
  else
    DIRSYNC_SCRIPT="$DIRSYNC_REPO/claude/scripts/bootstrap-crosscheck.sh"
  fi
  if HOME="$DIRSYNC_HOME" TMPDIR="$TEMP_DIR" bash "$DIRSYNC_SCRIPT" > "$TEMP_DIR/bootstrap-dirsync-$bootstrap.log" 2>&1; then
    echo "$bootstrap bootstrap reported success after a settings directory sync failure" >&2
    exit 1
  fi
  if ! grep -Fq "Could not safely publish prepared settings at $DIRSYNC_HOME/.claude/settings.json" "$TEMP_DIR/bootstrap-dirsync-$bootstrap.log"; then
    echo "$bootstrap bootstrap failed without the settings publication diagnostic" >&2
    cat "$TEMP_DIR/bootstrap-dirsync-$bootstrap.log" >&2
    exit 1
  fi
  if ! jq -e '.hooks.PreToolUse | type == "array"' "$DIRSYNC_HOME/.claude/settings.json" >/dev/null; then
    echo "$bootstrap bootstrap did not leave the fully validated settings file after the injected sync failure" >&2
    exit 1
  fi
  if grep -Fq 'Claude supply-chain hook points to' "$TEMP_DIR/bootstrap-dirsync-$bootstrap.log"; then
    echo "$bootstrap bootstrap announced success after its settings publication failed" >&2
    exit 1
  fi
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
python3 - "$REPO_ROOT" "$TEMP_DIR" <<'PY'
import os
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
scratch = Path(sys.argv[2])
recipes = (
    repo / "skill-sources/update-crosscheck.md",
    repo / "claude/skill-sources/update-crosscheck.md",
    repo / "codex/skill-sources/update-crosscheck.md",
    repo / "codex/skills/update-crosscheck/SKILL.md",
)
for recipe in recipes:
    source = recipe.read_text()
    step = source.split("## Step 4:", 1)[1]
    start = step.index("```bash\n") + len("```bash\n")
    end = step.index("\n```", start)
    script = step[start:end]
    if '"$HOME/.gemini/settings.json"' not in script:
        raise SystemExit(f"updater recipe no longer refreshes Gemini settings: {recipe}")
    for failed_app in (".claude", ".codex"):
        recipe_name = str(recipe.relative_to(repo)).replace("/", "-")
        root = scratch / f"gemini-after-{failed_app[1:]}-failure-{recipe_name}"
        home = root / "home"
        checkout = root / "checkout"
        for app in (".claude", ".codex", ".gemini"):
            app_dir = home / app
            app_dir.mkdir(parents=True, exist_ok=True)
            (app_dir / "settings.json").write_text("{}\n")
        helper = checkout / "scripts" / "sync-critical-settings.sh"
        helper.parent.mkdir(parents=True)
        helper.write_text(
            "#!/usr/bin/env bash\n"
            "set -e\n"
            "app=$(basename \"$(dirname \"$1\")\")\n"
            "printf '%s\\n' \"$app\" >> \"$SYNC_LOG\"\n"
            "if [ \"$app\" = \"$FAIL_APP\" ]; then exit 1; fi\n"
            "if [ \"$app\" = .gemini ]; then : > \"$HOME/.gemini/refreshed\"; fi\n"
        )
        helper.chmod(0o755)
        hook = checkout / "claude" / "scripts" / "install-supply-chain-hook.sh"
        hook.parent.mkdir(parents=True)
        hook.write_text("#!/usr/bin/env bash\nprintf called > \"$HOOK_CALLED\"\n")
        hook.chmod(0o755)
        env = os.environ.copy()
        env.update(
            HOME=str(home),
            CROSSCHECK_DIR=str(checkout),
            SYNC_LOG=str(root / "sync.log"),
            HOOK_CALLED=str(root / "hook-called"),
            FAIL_APP=failed_app,
        )
        result = subprocess.run(["/bin/bash", "-c", script], env=env, capture_output=True, text=True)
        calls = (root / "sync.log").read_text().splitlines()
        if result.returncode == 0 or calls != [".claude", ".codex", ".gemini"]:
            raise SystemExit(f"{recipe} stopped before Gemini after {failed_app} sync failed: {calls!r}; {result.stderr}")
        if not (home / ".gemini" / "refreshed").exists():
            raise SystemExit(f"{recipe} did not refresh Gemini settings after {failed_app} sync failed")
        hook_called = (root / "hook-called").exists()
        if hook_called == (failed_app == ".claude"):
            raise SystemExit(f"{recipe} installed or skipped the Claude hook incorrectly after {failed_app} failure")
PY
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
if ! grep -Eq "$NATIVE_RECOVERY_DIR/(settings|snapshot)-" "$TEMP_DIR/codex-native-update.log"; then
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

# Replacing ~/.codex with a symlink after the shell preflight must fail at the
# snapshot boundary without writing into the symlink destination.
SYMLINK_NATIVE_HOME="$TEMP_DIR/home-codex-native-symlink-race"
SYMLINK_NATIVE_OUTSIDE="$TEMP_DIR/codex-native-symlink-outside"
SYMLINK_NATIVE_BIN="$TEMP_DIR/codex-native-symlink-bin"
SYMLINK_NATIVE_MARKER="$TEMP_DIR/codex-native-symlink-swapped"
SYMLINK_NATIVE_LOG="$TEMP_DIR/codex-native-symlink.log"
SYMLINK_NATIVE_REAL_PYTHON="$(command -v python3)"
mkdir -p "$SYMLINK_NATIVE_HOME" "$SYMLINK_NATIVE_OUTSIDE" "$SYMLINK_NATIVE_BIN"
SYMLINK_NATIVE_HOME="$(cd "$SYMLINK_NATIVE_HOME" && pwd -P)"
cat > "$SYMLINK_NATIVE_BIN/python3" <<'SH'
#!/usr/bin/env bash
set -e
if [ "$2" = snapshot ] \
  && [ ! -e "$SYMLINK_NATIVE_MARKER" ]; then
  mv "$SYMLINK_NATIVE_HOME/.codex" "$SYMLINK_NATIVE_HOME/.codex-before-symlink"
  ln -s "$SYMLINK_NATIVE_OUTSIDE" "$SYMLINK_NATIVE_HOME/.codex"
  : > "$SYMLINK_NATIVE_MARKER"
fi
exec "$SYMLINK_NATIVE_REAL_PYTHON" "$@"
SH
chmod +x "$SYMLINK_NATIVE_BIN/python3"
export NATIVE_REPO SYMLINK_NATIVE_HOME SYMLINK_NATIVE_OUTSIDE SYMLINK_NATIVE_MARKER SYMLINK_NATIVE_REAL_PYTHON
if HOME="$SYMLINK_NATIVE_HOME" PATH="$SYMLINK_NATIVE_BIN:$PATH" \
  bash "$NATIVE_REPO/codex/scripts/sync-managed-codex-skills.sh" "$NATIVE_REPO" "$SYMLINK_NATIVE_HOME" \
  > "$SYMLINK_NATIVE_LOG" 2>&1; then
  echo "Codex native updater accepted a .codex symlink installed after its preflight" >&2
  cat "$SYMLINK_NATIVE_LOG" >&2
  exit 1
fi
if [ ! -e "$SYMLINK_NATIVE_MARKER" ] \
  || ! grep -Fq "Could not safely snapshot Codex skill file" "$SYMLINK_NATIVE_LOG" \
  || find "$SYMLINK_NATIVE_OUTSIDE" -mindepth 1 -print -quit | grep -q .; then
  echo "Codex native updater did not fail safely on a replacement .codex symlink" >&2
  cat "$SYMLINK_NATIVE_LOG" >&2
  exit 1
fi

python3 - "$REPO_ROOT/scripts/atomic-publish-file.py" "$TEMP_DIR" <<'PY'
import contextlib
import errno
import importlib.util
import io
import os
import stat
import subprocess
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("atomic_publish_file", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
scratch = Path(sys.argv[2]) / "atomic-publish-race"
scratch.mkdir()

# Older in-process publisher fixtures use hand-written snapshots. Supply the
# target identity at invocation for those tests; the subprocess test below
# verifies that the real CLI reads snapshot identity sidecars.
real_read_snapshot_identity = module._read_snapshot_identity

def read_fixture_snapshot_identity(snapshot_path):
    if Path(module._snapshot_identity_path(snapshot_path)).exists():
        return real_read_snapshot_identity(snapshot_path)
    root, relative_target = module.sys.argv[2], module.sys.argv[3]
    info = os.stat(os.path.join(root, relative_target), follow_symlinks=False)
    return info.st_dev, info.st_ino

module._read_snapshot_identity = read_fixture_snapshot_identity

def stage_entries(root):
    return [
        entry
        for directory in root.glob(".crosscheck-staging-*")
        for entry in directory.glob(".crosscheck-stage-*")
    ]

ensure_root = scratch / "ensure-directory-root"
ensure_root.mkdir()
module.ensure_directory(str(ensure_root), ".codex")
if not (ensure_root / ".codex").is_dir():
    raise SystemExit("atomic publisher did not create the requested directory")
strict_real_root = scratch / "strict-root-real"
strict_real_root.mkdir()
strict_link_root = scratch / "strict-root-link"
strict_link_root.symlink_to(strict_real_root, target_is_directory=True)
strict_target = strict_real_root / "AGENTS.md"
strict_snapshot = scratch / "strict-root-snapshot"
strict_stage = scratch / "strict-root-stage"
strict_target.write_text("original global instructions\n")
strict_snapshot.write_text("original global instructions\n")
strict_stage.write_text("updated global instructions\n")
try:
    module.publish_file(
        str(strict_link_root), "AGENTS.md", str(strict_snapshot), str(strict_stage), strict_root=True
    )
except OSError:
    pass
else:
    raise SystemExit("atomic publisher followed a symlink used as a strict root")
if strict_target.read_text() != "original global instructions\n":
    raise SystemExit("atomic publisher modified a target through a strict-root symlink")

# The staged settings file may have the destination's readable mode only
# inside a private same-filesystem directory.
private_stage_root = scratch / "private-publisher-stage"
private_stage_root.mkdir(mode=0o755)
private_stage_target = private_stage_root / "settings.json"
private_stage_snapshot = scratch / "private-publisher-snapshot.json"
private_stage_source = scratch / "private-publisher-source.json"
private_stage_target.write_text('{"privateStage":"before"}\n')
private_stage_snapshot.write_text('{"privateStage":"before"}\n')
private_stage_source.write_text('{"privateStage":"after"}\n')
os.chmod(private_stage_root, 0o755)
os.chmod(private_stage_target, 0o644)
os.chmod(private_stage_snapshot, 0o644)
os.chmod(private_stage_source, 0o600)
if sys.platform == "darwin":
    subprocess.run(
        ["/bin/chmod", "+a", "everyone allow list,search,file_inherit,directory_inherit", str(private_stage_root)],
        check=True,
    )
real_exchange = module._rename_exchange
private_stage_observed = []

def inspect_private_publisher_stage(first_fd, first, second_fd, second):
    staging_directories = list(private_stage_root.glob(".crosscheck-staging-*"))
    if len(staging_directories) != 1:
        raise SystemExit("publisher did not create one private staging directory")
    staging_directory = staging_directories[0]
    entries = list(staging_directory.glob(".crosscheck-stage-*"))
    if len(entries) != 1:
        raise SystemExit("publisher staging directory did not contain one staged file")
    directory_mode = stat.S_IMODE(staging_directory.stat().st_mode)
    file_mode = stat.S_IMODE(entries[0].stat().st_mode)
    if directory_mode != 0o700 or file_mode != 0o644:
        raise SystemExit(
            f"publisher stage was exposed: directory={oct(directory_mode)}, file={oct(file_mode)}"
        )
    if sys.platform == "darwin":
        directory_acl = subprocess.run(
            ["/bin/ls", "-le", str(staging_directory)], capture_output=True, text=True, check=True
        ).stdout
        file_acl = subprocess.run(
            ["/bin/ls", "-le", str(entries[0])], capture_output=True, text=True, check=True
        ).stdout
        if "everyone" in directory_acl or "everyone" in file_acl:
            raise SystemExit("publisher staging directory or file retained an inherited everyone ACL")
    private_stage_observed.append((directory_mode, file_mode))
    return real_exchange(first_fd, first, second_fd, second)

module._rename_exchange = inspect_private_publisher_stage
try:
    module.publish_file(
        str(private_stage_root), "settings.json", str(private_stage_snapshot),
        str(private_stage_source), expected_mode=0o644,
    )
finally:
    module._rename_exchange = real_exchange
if not private_stage_observed:
    raise SystemExit("publisher did not exercise the private-stage check")
if list(private_stage_root.glob(".crosscheck-staging-*")):
    raise SystemExit("publisher left its private staging directory after success")

# Snapshot files and intermediate command recovery directories must not keep
# ACLs inherited from a permissive temporary or target parent on macOS.
acl_temp_root = scratch / "acl-inherited-temp"
acl_temp_root.mkdir()
acl_temp_target_root = scratch / "acl-inherited-target"
acl_temp_target_root.mkdir()
acl_temp_target = acl_temp_target_root / "settings.json"
acl_temp_target.write_text('{"acl":"private"}\n')
acl_temp_snapshot = acl_temp_root / "settings-snapshot"
acl_temp_snapshot.write_text("")
acl_recovery_parent = scratch / "acl-inherited-recovery-parent"
acl_recovery_parent.mkdir()
if sys.platform == "darwin":
    everyone_acl = "everyone allow list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit"
    subprocess.run(["/bin/chmod", "+a", everyone_acl, str(acl_temp_root)], check=True)
    subprocess.run(["/bin/chmod", "+a", everyone_acl, str(acl_recovery_parent)], check=True)
acl_private_directory = acl_temp_root / "bootstrap-temp"
acl_private_directory.mkdir(mode=0o755)
os.chmod(acl_private_directory, 0o755)
subprocess.run([sys.executable, sys.argv[1], "private-directory", str(acl_private_directory)], check=True)
if stat.S_IMODE(acl_private_directory.stat().st_mode) != 0o700:
    raise SystemExit("private temporary directory did not receive mode 0700")
if sys.platform == "darwin":
    private_directory_acl = subprocess.run(
        ["/bin/ls", "-le", str(acl_private_directory)], capture_output=True, text=True, check=True
    ).stdout
    if "everyone" in private_directory_acl:
        raise SystemExit("private temporary directory retained an inherited everyone ACL")
acl_stage = acl_temp_root / "settings-stage"
acl_stage_fd = os.open(acl_stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
os.close(acl_stage_fd)
subprocess.run([sys.executable, sys.argv[1], "private-file", str(acl_stage)], check=True)
acl_stage.write_text('{"staged":"private"}\n')
if sys.platform == "darwin":
    stage_acl = subprocess.run(["/bin/ls", "-le", str(acl_stage)], capture_output=True, text=True, check=True).stdout
    if "everyone" in stage_acl:
        raise SystemExit("private settings stage retained an inherited ACL")
if not module.snapshot_file(str(acl_temp_target_root), "settings.json", str(acl_temp_snapshot), private=True):
    raise SystemExit("atomic publisher could not create a snapshot in the ACL fixture")
if stat.S_IMODE(acl_temp_snapshot.stat().st_mode) != 0o600:
    raise SystemExit("private source snapshot did not remain mode 0600")
snapshot_metadata = module._read_snapshot_metadata(str(acl_temp_snapshot))
if snapshot_metadata.get("source_mode") != stat.S_IMODE(acl_temp_target.stat().st_mode):
    raise SystemExit("private source snapshot did not retain the original mode in its metadata")
if sys.platform == "darwin":
    for private_file in (acl_temp_snapshot, Path(module._snapshot_identity_path(str(acl_temp_snapshot)))):
        listing = subprocess.run(["/bin/ls", "-le", str(private_file)], capture_output=True, text=True, check=True).stdout
        if "everyone" in listing:
            raise SystemExit(f"private snapshot retained an inherited ACL: {private_file}")
    recovery_parent_fd = os.open(acl_recovery_parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    recovery_fd, recovery_name, _ = module._new_recovery_directory(recovery_parent_fd, str(acl_recovery_parent))
    try:
        recovery_listing = subprocess.run(
            ["/bin/ls", "-le", str(acl_recovery_parent / recovery_name)],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        if "everyone" in recovery_listing:
            raise SystemExit("command recovery directory retained an inherited ACL")
    finally:
        os.close(recovery_fd)
        os.rmdir(acl_recovery_parent / recovery_name)
        os.close(recovery_parent_fd)
    acl_publish_stage = acl_temp_root / "settings-publish-stage"
    acl_publish_stage.write_text('{"acl":"updated"}\n')
    acl_user = subprocess.run(["id", "-un"], check=True, capture_output=True, text=True).stdout.strip()
    subprocess.run(
        ["/bin/chmod", "+a", "everyone deny read", str(acl_temp_target)],
        check=True,
    )
    subprocess.run(
        ["/bin/chmod", "+a#", "0", f"user:{acl_user} allow read", str(acl_temp_target)],
        check=True,
    )
    module.publish_file(
        str(acl_temp_target_root), "settings.json", str(acl_temp_snapshot),
        str(acl_publish_stage), expected_mode=0o644,
    )
    published_acl = subprocess.run(
        ["/bin/ls", "-le", str(acl_temp_target)], capture_output=True, text=True, check=True
    ).stdout
    if "everyone deny read" not in published_acl or f"user:{acl_user} allow read" not in published_acl:
        raise SystemExit("atomic publisher did not preserve the source file ACL")

    late_acl_target = acl_temp_target_root / "late-settings.json"
    late_acl_target.write_text('{"lateAcl":"original"}\n')
    late_acl_snapshot = acl_temp_root / "late-settings-snapshot"
    late_acl_snapshot.write_text("")
    late_acl_stage = acl_temp_root / "late-settings-stage"
    late_acl_stage.write_text('{"lateAcl":"updated"}\n')
    subprocess.run(["/bin/chmod", "+a", "everyone deny read", str(late_acl_target)], check=True)
    subprocess.run(["/bin/chmod", "+a#", "0", f"user:{acl_user} allow read", str(late_acl_target)], check=True)
    if not module.snapshot_file(str(acl_temp_target_root), "late-settings.json", str(late_acl_snapshot), private=True):
        raise SystemExit("atomic publisher could not snapshot the late-ACL fixture")
    late_acl_identity = (late_acl_target.stat().st_dev, late_acl_target.stat().st_ino)
    real_verify_recovery = module._verify_stable_recovery_link
    verify_recovery_calls = [0]

    def add_late_source_acl(base_fd, base_path, recovery_fd, recovery_name, recovery_path, entry_name, entry_path, expected_inode):
        verify_recovery_calls[0] += 1
        if verify_recovery_calls[0] == 2:
            subprocess.run(["/bin/chmod", "+a#", "0", "everyone deny write", entry_path], check=True)
        return real_verify_recovery(
            base_fd, base_path, recovery_fd, recovery_name, recovery_path, entry_name, entry_path, expected_inode
        )

    module._verify_stable_recovery_link = add_late_source_acl
    try:
        try:
            module.publish_file(
                str(acl_temp_target_root), "late-settings.json", str(late_acl_snapshot),
                str(late_acl_stage), expected_mode=0o644, expected_snapshot_mode=0o644,
            )
        except module.ConcurrentUpdate:
            pass
        else:
            raise SystemExit("publisher accepted an ACL change during final recovery-link verification")
    finally:
        module._verify_stable_recovery_link = real_verify_recovery
    if (late_acl_target.stat().st_dev, late_acl_target.stat().st_ino) != late_acl_identity:
        raise SystemExit("late ACL rollback did not restore the original settings inode")
    late_published_acl = subprocess.run(
        ["/bin/ls", "-le", str(late_acl_target)], capture_output=True, text=True, check=True
    ).stdout
    if "everyone deny read" not in late_published_acl or "everyone deny write" not in late_published_acl:
        raise SystemExit("late ACL rollback did not restore the latest ACL on the live settings file")
    module.cleanup_snapshot(str(late_acl_snapshot))
module.cleanup_snapshot(str(acl_temp_snapshot))

# Linux replacements must carry the pinned POSIX access ACL to the new inode,
# including entries that are not represented by the numeric mode alone.
if sys.platform.startswith("linux"):
    linux_acl_source = acl_temp_target_root / "linux-acl-source"
    linux_acl_source.write_text("source with a named-user ACL\n")
    linux_acl_identity = (linux_acl_source.stat().st_dev, linux_acl_source.stat().st_ino)
    linux_acl_value = bytes.fromhex("0200000001000600")
    actual_os_getxattr = module.os.getxattr
    actual_os_setxattr = module.os.setxattr
    actual_sys = module.sys
    copied_linux_acls = []

    def fake_linux_getxattr(file_descriptor, attribute):
        if attribute == "system.posix_acl_access" and os.fstat(file_descriptor).st_ino == linux_acl_identity[1]:
            return linux_acl_value
        raise OSError(errno.ENODATA, "no POSIX ACL")

    def capture_linux_setxattr(file_descriptor, attribute, value):
        copied_linux_acls.append((attribute, value))

    module.sys = type("LinuxPlatform", (), {"platform": "linux"})()
    module.os.getxattr = fake_linux_getxattr
    module.os.setxattr = capture_linux_setxattr
    try:
        linux_acl_stage = acl_temp_root / "linux-acl-stage"
        linux_acl_stage.touch(mode=0o600)
        linux_acl_stage_fd = os.open(linux_acl_stage, os.O_RDONLY)
        try:
            observed_linux_acl = module._copy_acl_from_path(
                str(linux_acl_source), linux_acl_stage_fd, linux_acl_identity
            )
        finally:
            os.close(linux_acl_stage_fd)
        expected_linux_acl = ("system.posix_acl_access=" + linux_acl_value.hex(),)
        if observed_linux_acl != (expected_linux_acl, linux_acl_source.stat().st_ctime_ns):
            raise SystemExit("Linux publisher did not retain the source POSIX ACL metadata")
        if copied_linux_acls != [("system.posix_acl_access", linux_acl_value)]:
            raise SystemExit("Linux publisher did not copy the source POSIX access ACL to its staged inode")
    finally:
        module.sys = actual_sys
        module.os.getxattr = actual_os_getxattr
        module.os.setxattr = actual_os_setxattr

    # Linux default ACLs are inherited by newly created stage directories and
    # files. Clearing them must prevent a named-user ACL from widening a
    # mode-only settings replacement after fchmod.
    import struct

    linux_acl_publish_root = scratch / "linux-acl-publish-root"
    linux_acl_publish_root.mkdir()
    linux_acl_publish_target = linux_acl_publish_root / "settings.json"
    linux_acl_publish_target.write_text('{"setting":"original"}\n')
    linux_acl_publish_target.chmod(0o640)
    linux_acl_default = struct.pack("<I", 2) + b"".join(
        struct.pack("<HHI", tag, permissions, user_id)
        for tag, permissions, user_id in (
            (0x01, 0x07, 0xFFFFFFFF),
            (0x02, 0x04, 65534),
            (0x04, 0x00, 0xFFFFFFFF),
            (0x10, 0x04, 0xFFFFFFFF),
            (0x20, 0x00, 0xFFFFFFFF),
        )
    )
    try:
        os.setxattr(linux_acl_publish_root, "system.posix_acl_default", linux_acl_default)
    except OSError as error:
        if error.errno not in (errno.ENOTSUP, errno.EOPNOTSUPP):
            raise
    else:
        linux_acl_parent_fd = os.open(
            linux_acl_publish_root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        )
        try:
            stage_fd, stage_name, stage_path = module._new_private_stage_directory(
                linux_acl_parent_fd,
                str(linux_acl_publish_root),
                linux_acl_publish_target.stat().st_dev,
            )
            try:
                for attribute in ("system.posix_acl_access", "system.posix_acl_default"):
                    try:
                        os.getxattr(stage_fd, attribute)
                    except OSError as error:
                        if error.errno != getattr(errno, "ENODATA", errno.ENOENT):
                            raise
                    else:
                        raise SystemExit(f"private Linux stage directory retained inherited {attribute}")
                if stat.S_IMODE(os.fstat(stage_fd).st_mode) != 0o700:
                    raise SystemExit("private Linux stage directory lost its 0700 mode")
            finally:
                os.close(stage_fd)
                os.rmdir(stage_name, dir_fd=linux_acl_parent_fd)
        finally:
            os.close(linux_acl_parent_fd)
        linux_acl_publish_snapshot = scratch / "linux-acl-publish-snapshot.json"
        linux_acl_publish_stage = scratch / "linux-acl-publish-stage.json"
        linux_acl_publish_stage.write_text('{"setting":"updated"}\n')
        if not module.snapshot_file(
            str(linux_acl_publish_root), "settings.json", str(linux_acl_publish_snapshot)
        ):
            raise SystemExit("could not snapshot mode-only settings before the Linux ACL publish test")
        module.publish_file(
            str(linux_acl_publish_root), "settings.json",
            str(linux_acl_publish_snapshot), str(linux_acl_publish_stage),
        )
        try:
            os.getxattr(linux_acl_publish_target, "system.posix_acl_access")
        except OSError as error:
            if error.errno != getattr(errno, "ENODATA", errno.ENOENT):
                raise
        else:
            raise SystemExit("Linux settings publish retained an inherited named-user access ACL")
        if stat.S_IMODE(linux_acl_publish_target.stat().st_mode) != 0o640:
            raise SystemExit("Linux settings publish changed the mode-only target permissions")

# A command migration uses the commands directory as the recovery boundary so
# a normal home directory remains writable as the private recovery location.
command_boundary_home = scratch / "command-recovery-boundary-home"
command_boundary_home_real = command_boundary_home.resolve()
command_boundary_dir = command_boundary_home / ".claude/commands"
command_boundary_dir.mkdir(parents=True)
command_boundary_target = command_boundary_dir / "managed.md"
command_boundary_target.write_text("managed command\n")
command_boundary_snapshot = scratch / "command-recovery-boundary-snapshot"
command_boundary_snapshot.write_text("")
real_expanduser = module.os.path.expanduser
real_open_private_recovery = module._open_private_recovery_directory
recovery_candidates = []

def fixture_home(_path):
    return str(command_boundary_home_real)

def only_home_recovery(candidate, target_device):
    recovery_candidates.append(candidate)
    if candidate != str(command_boundary_home_real):
        raise PermissionError("simulated non-writable system recovery ancestor")
    return real_open_private_recovery(candidate, target_device)

module.os.path.expanduser = fixture_home
module._open_private_recovery_directory = only_home_recovery
try:
    if not module.snapshot_file(
        str(command_boundary_home),
        ".claude/commands/managed.md",
        str(command_boundary_snapshot),
        recovery_boundary=str(command_boundary_dir),
    ):
        raise SystemExit("Claude command snapshot failed despite its safe home recovery boundary")
finally:
    module.os.path.expanduser = real_expanduser
    module._open_private_recovery_directory = real_open_private_recovery
if not recovery_candidates or recovery_candidates[0] != str(command_boundary_home_real):
    raise SystemExit("Claude command snapshot did not use the home recovery location")
command_boundary_backup = Path(str(module._read_snapshot_metadata(str(command_boundary_snapshot))["recovery_path"]))
if command_boundary_backup.parent != command_boundary_home_real / ".crosscheck-recovery":
    raise SystemExit("Claude command snapshot recovery escaped its private home location")
module.cleanup_snapshot(str(command_boundary_snapshot))

# Compatibility commands use the command directory as their recovery
# boundary, so an unwritable ancestor of HOME is never selected as recovery.
compat_home_parent = scratch / "compat-home-parent"
compat_home = compat_home_parent / "home"
compat_command_dir = compat_home / ".codex/commands"
compat_command_dir.mkdir(parents=True)
compat_command = compat_command_dir / "managed.md"
compat_command.write_text("published command\n")
compat_repo = scratch / "compat-managed-repo"
compat_skill_dir = compat_repo / "skill-sources"
compat_skill_dir.mkdir(parents=True)
compat_source = compat_skill_dir / "managed.md"
compat_source.write_text("published command\n")
git_env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1"}
subprocess.run(["git", "-C", str(compat_repo), "init", "-q"], check=True, env=git_env)
subprocess.run(["git", "-C", str(compat_repo), "add", "skill-sources/managed.md"], check=True, env=git_env)
subprocess.run(
    ["git", "-C", str(compat_repo), "-c", "user.name=CrossCheck test", "-c",
     "user.email=crosscheck-test@example.invalid", "commit", "-qm", "published compatibility command"],
    check=True,
    env=git_env,
)
revision = subprocess.run(
    ["git", "-C", str(compat_repo), "rev-parse", "HEAD"],
    check=True, capture_output=True, text=True, env=git_env,
).stdout.strip()
subprocess.run(
    ["git", "-C", str(compat_repo), "update-ref", "refs/remotes/origin/main", revision],
    check=True, env=git_env,
)
compat_source.write_text("updated compatibility command\n")
previous_home = os.environ.get("HOME")
os.environ["HOME"] = str(compat_home)
compat_home_parent.chmod(0o555)
try:
    status = module.sync_managed_compat_command(
        str(compat_home), ".codex/commands/managed.md", str(compat_source),
        str(compat_repo), "skill-sources/managed.md",
    )
finally:
    compat_home_parent.chmod(0o755)
    if previous_home is None:
        os.environ.pop("HOME", None)
    else:
        os.environ["HOME"] = previous_home
if status != "updated" or not compat_command.is_symlink():
    raise SystemExit("compatibility command bootstrap failed with an unwritable HOME ancestor")
if not list((compat_home / ".crosscheck-recovery").glob("snapshot-*.bak")):
    raise SystemExit("compatibility command recovery did not stay under HOME")

# The narrower recovery boundary must not weaken no-follow traversal from HOME.
command_symlink_home = scratch / "command-symlink-home"
command_symlink_outside = scratch / "command-symlink-outside"
command_symlink_outside.mkdir()
(command_symlink_outside / "managed.md").write_text("outside command\n")
command_symlink_home.mkdir()
(command_symlink_home / ".claude").symlink_to(command_symlink_outside, target_is_directory=True)
try:
    module.snapshot_file(
        str(command_symlink_home),
        ".claude/managed.md",
        str(scratch / "command-symlink-snapshot"),
        recovery_boundary=str(command_symlink_outside),
    )
except OSError:
    pass
else:
    raise SystemExit("Claude command snapshot followed a symlink from HOME")
if (command_symlink_outside / "managed.md").read_text() != "outside command\n":
    raise SystemExit("Claude command snapshot modified its symlink destination")

# The CLI must reject a byte-identical replacement made after the snapshot.
# Its inode identity is part of the snapshot contract, not just the contents.
snapshot_identity_root = scratch / "snapshot-identity-race"
snapshot_identity_root.mkdir()
snapshot_identity_target = snapshot_identity_root / "settings.json"
snapshot_identity_target.write_text('{"identity":"same bytes"}\n')
snapshot_identity_open = snapshot_identity_target.open("r+")
snapshot_identity_copy = scratch / "snapshot-identity-copy"
snapshot_identity_stage = scratch / "snapshot-identity-stage"
snapshot_identity_copy.write_text("")
snapshot_identity_stage.write_text('{"identity":"updated"}\n')
if not module.snapshot_file(
    str(snapshot_identity_root), "settings.json", str(snapshot_identity_copy), private=True
):
    raise SystemExit("atomic publisher could not snapshot the identity-race fixture")
original_identity = module._read_snapshot_identity(str(snapshot_identity_copy))
replacement = snapshot_identity_root / "replacement.json"
replacement.write_text('{"identity":"same bytes"}\n')
replacement.replace(snapshot_identity_target)
result = subprocess.run(
    [
        sys.executable,
        sys.argv[1],
        "publish",
        str(snapshot_identity_root),
        "settings.json",
        str(snapshot_identity_copy),
        str(snapshot_identity_stage),
        oct(stat.S_IMODE(snapshot_identity_target.stat().st_mode))[2:],
    ],
    capture_output=True,
    text=True,
)
if result.returncode != 3 or "file identity changed since snapshot" not in result.stderr:
    raise SystemExit(f"publisher accepted a byte-identical replacement after snapshot: {result.stderr}")
if snapshot_identity_target.read_text() != '{"identity":"same bytes"}\n':
    raise SystemExit("publisher changed the target after detecting a snapshot identity race")
recovery_line = next(
    (line for line in result.stderr.splitlines() if line.startswith("preserved concurrent file at ")),
    None,
)
if recovery_line is None:
    raise SystemExit("publisher did not report its snapshot-time inode recovery link")
snapshot_identity_open.seek(0)
snapshot_identity_open.truncate()
snapshot_identity_open.write('{"identity":"late save"}\n')
snapshot_identity_open.flush()
if Path(recovery_line.removeprefix("preserved concurrent file at ")).read_text() != '{"identity":"late save"}\n':
    raise SystemExit("publisher did not retain the snapshotted inode for a late save")
snapshot_identity_open.close()

# The command-link publisher must enforce the snapshot inode, not only its
# bytes, when a same-content command replaces the original after snapshot.
command_identity_home = scratch / "command-identity-race-home"
command_identity_dir = command_identity_home / ".claude/commands"
command_identity_dir.mkdir(parents=True)
command_identity_target = command_identity_dir / "managed.md"
command_identity_target.write_text("same command bytes\n")
command_identity_open = command_identity_target.open("r+")
command_identity_snapshot = scratch / "command-identity-snapshot"
command_identity_snapshot.write_text("")
command_identity_source = scratch / "command-identity-source.md"
command_identity_source.write_text("managed command source\n")
if not module.snapshot_file(
    str(command_identity_home),
    ".claude/commands/managed.md",
    str(command_identity_snapshot),
    recovery_boundary=str(command_identity_dir),
):
    raise SystemExit("atomic publisher could not snapshot the Claude command identity fixture")
command_replacement = command_identity_dir / "replacement.md"
command_replacement.write_text("same command bytes\n")
command_replacement.replace(command_identity_target)
command_link_result = subprocess.run(
    [
        sys.executable,
        sys.argv[1],
        "symlink",
        str(command_identity_home),
        ".claude/commands/managed.md",
        "snapshot",
        str(command_identity_snapshot),
        str(command_identity_source),
    ],
    capture_output=True,
    text=True,
)
if command_link_result.returncode != 3 or "inode changed since snapshot" not in command_link_result.stderr:
    raise SystemExit(f"Claude command publisher accepted a byte-identical replacement: {command_link_result.stderr}")
if command_identity_target.is_symlink() or command_identity_target.read_text() != "same command bytes\n":
    raise SystemExit("Claude command publisher changed the byte-identical replacement")
command_recovery_line = next(
    (line for line in command_link_result.stderr.splitlines() if line.startswith("preserved concurrent file at ")),
    None,
)
if command_recovery_line is None:
    raise SystemExit("Claude command publisher did not report its snapshot-time recovery link")
command_identity_open.seek(0)
command_identity_open.truncate()
command_identity_open.write("late save through original command inode\n")
command_identity_open.flush()
command_identity_open.close()
if Path(command_recovery_line.removeprefix("preserved concurrent file at ")).read_text() != "late save through original command inode\n":
    raise SystemExit("Claude command migration lost a late save to the snapshotted inode")

cleanup_snapshot_root = scratch / "unused-snapshot-cleanup"
cleanup_snapshot_root.mkdir()
cleanup_snapshot_target = cleanup_snapshot_root / "settings.json"
cleanup_snapshot_target.write_text('{"cleanup":"unchanged"}\n')
cleanup_snapshot_open = cleanup_snapshot_target.open("r+")
cleanup_snapshot_copy = scratch / "unused-snapshot-copy"
cleanup_snapshot_copy.write_text("")
if not module.snapshot_file(str(cleanup_snapshot_root), "settings.json", str(cleanup_snapshot_copy)):
    raise SystemExit("atomic publisher could not create an unused-snapshot fixture")
cleanup_metadata = module._read_snapshot_metadata(str(cleanup_snapshot_copy))
cleanup_backup = Path(str(cleanup_metadata["recovery_path"]))
if not cleanup_backup.exists():
    raise SystemExit("snapshot did not pin its target inode in recovery storage")
if module.cleanup_snapshot(str(cleanup_snapshot_copy)) != str(cleanup_backup):
    raise SystemExit("unused snapshot cleanup did not report its retained recovery link")
replacement_settings = cleanup_snapshot_root / "replacement.json"
replacement_settings.write_text('{"cleanup":"unchanged"}\n')
replacement_settings.replace(cleanup_snapshot_target)
cleanup_snapshot_open.seek(0)
cleanup_snapshot_open.truncate()
cleanup_snapshot_open.write('{"cleanup":"late save"}\n')
cleanup_snapshot_open.flush()
cleanup_snapshot_open.close()
if not cleanup_backup.exists() or cleanup_backup.read_text() != '{"cleanup":"late save"}\n':
    raise SystemExit("unused snapshot cleanup discarded the only recovery link for a late save")

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

# A concurrent atomic replacement during the final live-state check must
# invalidate success and restore the concurrent writer's exact inode.
final_race_root = scratch / "final-live-state-race"
final_race_root.mkdir()
final_race_target = final_race_root / "settings.json"
final_race_snapshot = scratch / "final-live-state-snapshot.json"
final_race_source = scratch / "final-live-state-source.json"
final_race_concurrent = scratch / "final-live-state-concurrent.json"
final_race_original = '{"finalRace":"before"}\n'
final_race_updated = '{"finalRace":"published"}\n'
final_race_concurrent_text = '{"finalRace":"concurrent save"}\n'
final_race_target.write_text(final_race_original)
final_race_snapshot.write_text(final_race_original)
final_race_source.write_text(final_race_updated)
final_race_concurrent.write_text(final_race_concurrent_text)
final_race_root_identity = (final_race_root.stat().st_dev, final_race_root.stat().st_ino)
real_entry_state = module._entry_state_at
final_race_injected = []
final_race_identity = []
final_race_recovery = []
final_race_target_samples = [0]

def replace_live_file_before_final_check(directory_fd, name):
    directory_info = os.fstat(directory_fd)
    if (
        not final_race_injected
        and name == "settings.json"
        and (directory_info.st_dev, directory_info.st_ino) == final_race_root_identity
    ):
        final_race_target_samples[0] += 1
        if final_race_target_samples[0] == 2:
            os.replace(final_race_concurrent, final_race_target)
            info = final_race_target.stat()
            final_race_identity.append((info.st_dev, info.st_ino))
            final_race_injected.append(True)
    return real_entry_state(directory_fd, name)

module._entry_state_at = replace_live_file_before_final_check
try:
    try:
        module.publish_file(
            str(final_race_root), "settings.json", str(final_race_snapshot), str(final_race_source)
        )
    except module.ConcurrentUpdate as error:
        if not error.recovery_path or Path(error.recovery_path).read_text() != final_race_concurrent_text:
            raise SystemExit("publisher did not report the concurrent save after final-state validation")
        final_race_recovery.append(error.recovery_path)
    else:
        raise SystemExit("publisher reported success after its target changed during final-state validation")
finally:
    module._entry_state_at = real_entry_state
if not final_race_injected or final_race_target.read_text() != final_race_concurrent_text:
    raise SystemExit("publisher did not restore the concurrent save after final-state validation")
if (final_race_target.stat().st_dev, final_race_target.stat().st_ino) != final_race_identity[0]:
    raise SystemExit("publisher replaced the concurrent save with a same-content inode")
if (Path(final_race_recovery[0]).stat().st_dev, Path(final_race_recovery[0]).stat().st_ino) != final_race_identity[0]:
    raise SystemExit("publisher recovery path did not retain the exact concurrent-save inode")

# Replacing the stable backup with a same-content inode must fail closed before
# the displaced original can be unlinked during successful publication.
backup_tamper_root = scratch / "backup-tamper-root"
backup_tamper_root.mkdir()
backup_tamper_target = backup_tamper_root / "settings.json"
backup_tamper_snapshot = scratch / "backup-tamper-snapshot.json"
backup_tamper_stage = scratch / "backup-tamper-stage.json"
backup_tamper_target.write_text('{"setting":"original"}\n')
backup_tamper_snapshot.write_text('{"setting":"original"}\n')
backup_tamper_stage.write_text('{"setting":"updated"}\n')
backup_tamper_identity = (backup_tamper_target.stat().st_dev, backup_tamper_target.stat().st_ino)
backup_tamper_handle = backup_tamper_target.open("r+")
real_verify_stable_path = module._verify_stable_recovery_path
stable_path_checks = [0]

def replace_backup_after_directory_verification(base_fd, base_path, recovery_fd, recovery_name, recovery_path):
    result = real_verify_stable_path(base_fd, base_path, recovery_fd, recovery_name, recovery_path)
    stable_path_checks[0] += 1
    if stable_path_checks[0] == 3:
        backup = Path(recovery_path) / recovery_name
        backup_info = backup.stat()
        replacement = backup.with_name(backup.name + ".replacement")
        replacement.write_text('{"setting":"original"}\n')
        os.chmod(replacement, module.stat.S_IMODE(backup_info.st_mode))
        os.replace(replacement, backup)
    return result

module._verify_stable_recovery_path = replace_backup_after_directory_verification
try:
    module.publish_file(
        str(backup_tamper_root), "settings.json", str(backup_tamper_snapshot), str(backup_tamper_stage)
    )
except module.ConcurrentUpdate as error:
    if not error.recovery_path or Path(error.recovery_path).read_text() != '{"setting":"original"}\n':
        raise SystemExit("publisher failed to retain the displaced original after backup tampering")
else:
    raise SystemExit("publisher accepted a same-content replacement of the stable recovery inode")
finally:
    module._verify_stable_recovery_path = real_verify_stable_path
    backup_tamper_handle.close()
if backup_tamper_target.read_text() != '{"setting":"original"}\n':
    raise SystemExit("publisher did not roll back after detecting a replaced recovery inode")
if (backup_tamper_target.stat().st_dev, backup_tamper_target.stat().st_ino) != backup_tamper_identity:
    raise SystemExit("publisher lost the original settings inode after backup tampering")

# Signature-read failures after copying must remove the private staging entry.
for failed_signature_read in ("copied", "source"):
    copy_failure_root = scratch / f"copy-signature-failure-{failed_signature_read}"
    copy_failure_root.mkdir()
    copy_failure_source = scratch / f"copy-signature-source-{failed_signature_read}.json"
    copy_failure_source.write_text('{"setting":"new"}\n')
    real_read_signature_at = module._read_signature_at
    real_read_signature = module._read_signature

    if failed_signature_read == "copied":
        def fail_copied_signature(directory_fd, name):
            if name.startswith(".crosscheck-stage-"):
                raise OSError(errno.EIO, "injected copied-file signature read failure")
            return real_read_signature_at(directory_fd, name)
        module._read_signature_at = fail_copied_signature
    else:
        def fail_source_signature(path):
            if path == str(copy_failure_source):
                raise OSError(errno.EIO, "injected source signature read failure")
            return real_read_signature(path)
        module._read_signature = fail_source_signature
    try:
        try:
            module.publish_file(
                str(copy_failure_root), "settings.json", None, str(copy_failure_source)
            )
        except OSError:
            pass
        else:
            raise SystemExit(f"publisher accepted a failed {failed_signature_read} signature read")
    finally:
        module._read_signature_at = real_read_signature_at
        module._read_signature = real_read_signature
    if list(stage_entries(copy_failure_root)):
        raise SystemExit(f"publisher left a staging file after a {failed_signature_read} signature read error")
    if list(copy_failure_root.glob(".crosscheck-staging-*")):
        raise SystemExit(f"publisher left a staging directory after a {failed_signature_read} signature read error")
    if (copy_failure_root / "settings.json").exists():
        raise SystemExit(f"publisher published a file after a {failed_signature_read} signature read error")

# A moved and recreated target parent must not make detached rollback look safe.
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
        settings_dir.mkdir()
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = rename_parent_after_publish
try:
    module.publish_file(str(scratch), ".claude/settings.json", str(snapshot), str(staged))
except module.RestorationFailed as error:
    if not error.recovery_path or Path(error.recovery_path).read_text() != '{"setting":"original again"}\n':
        raise SystemExit("atomic publisher did not report stable recovery after the parent moved")
else:
    raise SystemExit("atomic publisher reported a safe rollback through a detached parent")
finally:
    module._verify_parent_path = real_verify
if (scratch / "settings-dir-moved-during-publish/settings.json").read_text() != '{"setting":"original again"}\n':
    raise SystemExit("atomic publisher failed to restore the previous settings after a target parent rename")
if settings_dir.joinpath("settings.json").exists():
    raise SystemExit("atomic publisher restored settings only in the detached parent")
if not list(stage_entries(scratch / "settings-dir-moved-during-publish")):
    raise SystemExit("atomic publisher cleaned the stage after failing live-parent verification")

# Moving the target parent during final recovery validation must not report a
# successful publication or discard the displaced settings inode.
late_move_root = scratch / "late-move-root"
late_move_home = scratch / "late-move-home"
late_move_home.mkdir()
late_move_root.mkdir()
late_move_target = late_move_root / "settings.json"
late_move_snapshot = scratch / "late-move-snapshot.json"
late_move_stage = scratch / "late-move-stage.json"
late_move_target.write_text('{"lateMove":"original"}\n')
late_move_snapshot.write_text('{"lateMove":"original"}\n')
late_move_stage.write_text('{"lateMove":"updated"}\n')
real_verify = module._verify_parent_path
verify_calls = [0]

def rename_parent_during_final_publish_check(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 3:
        late_move_root.rename(late_move_root.with_name("late-move-root-detached"))
        late_move_root.mkdir()
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = rename_parent_during_final_publish_check
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(late_move_home)
try:
    module.publish_file(str(late_move_root), "settings.json", str(late_move_snapshot), str(late_move_stage))
except module.RestorationFailed as error:
    if not error.recovery_path or Path(error.recovery_path).read_text() != '{"lateMove":"original"}\n':
        raise SystemExit("late target-parent move did not retain a stable original settings backup")
else:
    raise SystemExit("publisher reported success after its target parent moved during final validation")
finally:
    os.environ["HOME"] = previous_home
    module._verify_parent_path = real_verify
late_move_detached = late_move_root.with_name("late-move-root-detached")
if (late_move_root / "settings.json").exists():
    raise SystemExit("publisher restored settings only in the detached target parent")
if not list(stage_entries(late_move_detached)):
    raise SystemExit("publisher discarded the staged inode after a late target-parent move")

# A same-content recovery replacement during the final parent check must not
# allow cleanup of the original settings inode in the stage name.
final_recovery_home = scratch / "final-recovery-home"
final_recovery_root = scratch / "final-recovery-root"
final_recovery_home.mkdir()
final_recovery_root.mkdir()
final_recovery_target = final_recovery_root / "settings.json"
final_recovery_snapshot = scratch / "final-recovery-snapshot.json"
final_recovery_stage = scratch / "final-recovery-stage.json"
final_recovery_text = '{"finalRecovery":"original"}\n'
final_recovery_target.write_text(final_recovery_text)
final_recovery_snapshot.write_text(final_recovery_text)
final_recovery_stage.write_text('{"finalRecovery":"updated"}\n')
final_recovery_identity = (final_recovery_target.stat().st_dev, final_recovery_target.stat().st_ino)
real_verify = module._verify_parent_path
verify_calls = [0]

def replace_backup_during_final_publish_parent_check(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 4:
        backup_dir = final_recovery_home / ".crosscheck-recovery"
        backup = next(path for path in backup_dir.glob("settings-*.bak") if path.read_text() == final_recovery_text)
        replacement = backup.with_name(backup.name + ".replacement")
        mode = stat.S_IMODE(backup.stat().st_mode)
        replacement.write_text(final_recovery_text)
        replacement.chmod(mode)
        os.replace(replacement, backup)
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = replace_backup_during_final_publish_parent_check
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(final_recovery_home)
try:
    try:
        module.publish_file(
            str(final_recovery_root), "settings.json", str(final_recovery_snapshot), str(final_recovery_stage)
        )
    except module.RestorationFailed:
        pass
    else:
        raise SystemExit("publisher accepted a recovery inode replaced during its final parent check")
finally:
    os.environ["HOME"] = previous_home
    module._verify_parent_path = real_verify
final_recovery_staged = list(stage_entries(final_recovery_root))
if not any(
    (path.stat().st_dev, path.stat().st_ino) == final_recovery_identity and path.read_text() == final_recovery_text
    for path in final_recovery_staged
):
    raise SystemExit("publisher removed the only original settings inode after a recovery-link replacement")

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

def force_cross_volume(root_path, parent_path, target_device, recovery_boundary=None):
    return real_open_recovery(root_path, parent_path, -1, recovery_boundary)

module._open_stable_recovery_directory = force_cross_volume
try:
    module.publish_file(
        str(cross_volume_target.parent),
        "settings.json",
        str(cross_volume_snapshot),
        str(cross_volume_stage),
    )
except OSError as error:
    if error.errno != errno.EXDEV or "refusing to update" not in str(error):
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
if list(stage_entries(race_target_dir)):
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
verify_calls_after_publish = [0]

def fail_after_publishing(root_fd, root_path, relative_target, parent_fd):
    if published_identity[0] is not None:
        verify_calls_after_publish[0] += 1
        if verify_calls_after_publish[0] == 1:
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
rollback_failure_snapshot.write_text("")
if not module.snapshot_file(str(rollback_failure_dir), "settings.json", str(rollback_failure_snapshot)):
    raise SystemExit("could not create rollback-failure snapshot")
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

# Link ownership and the expected raw value must come from one sample. Replacing
# a managed link with a custom link before readlink must preserve the custom path.
noop_sync_target.unlink()
noop_sync_target.symlink_to(noop_sync_root_skill)
custom_sync_target = scratch / "custom-managed-command.md"
custom_sync_target.write_text("user-owned command\n")
custom_readlink_shim = readlink_shim
custom_readlink_shim.write_text(
    "#!/bin/sh\n"
    'if [ "$1" = "$RACE_TARGET" ]; then\n'
    '  ln -s "$RACE_NEW_LINK" "$RACE_TARGET.next"\n'
    '  mv -f "$RACE_TARGET.next" "$RACE_TARGET"\n'
    'fi\n'
    'exec "$REAL_READLINK" "$@"\n'
)
custom_readlink_shim.chmod(0o755)
custom_sync_env = sync_env.copy()
custom_sync_env.update(
    PATH=f"{readlink_shims}:{sync_env['PATH']}",
    RACE_NEW_LINK=str(custom_sync_target),
)
custom_sync_result = subprocess.run(
    ["bash", str(Path(sys.argv[1]).parents[1] / "claude/scripts/sync-managed-claude-skills.sh"),
     str(noop_sync_root), str(noop_sync_home)],
    check=False,
    text=True,
    capture_output=True,
    env=custom_sync_env,
)
if custom_sync_result.returncode != 0:
    raise SystemExit(
        f"Claude sync custom-link race fixture failed: {custom_sync_result.stderr}\n{custom_sync_result.stdout}"
    )
if "Claude command links added or refreshed: 0; preserved 1" not in custom_sync_result.stdout:
    raise SystemExit(
        "Claude sync rewrote a concurrent custom command link: "
        f"stdout={custom_sync_result.stdout!r}; stderr={custom_sync_result.stderr!r}"
    )
if os.readlink(noop_sync_target) != str(custom_sync_target):
    raise SystemExit("Claude sync replaced a concurrent custom command link")

# A concurrent atomic save after rollback has isolated its own symlink must
# remain at the live path while the displaced command stays recoverable.
symlink_rollback_race_home = scratch / "symlink-rollback-race-home"
symlink_rollback_race_target = symlink_rollback_race_home / ".claude/commands/managed.md"
symlink_rollback_race_target.parent.mkdir(parents=True)
symlink_rollback_race_target.write_text("original managed command\n")
symlink_rollback_race_snapshot = scratch / "symlink-rollback-race-snapshot.md"
symlink_rollback_race_snapshot.write_text("original managed command\n")
symlink_rollback_race_source = scratch / "symlink-rollback-race-source.md"
symlink_rollback_race_source.write_text("replacement managed command\n")
real_verify = module._verify_parent_path
real_exchange = module._rename_exchange
exchange_calls = []
race_injected = []
verification_failed = []

def fail_after_install_with_late_save(root_fd, root_path, relative_target, parent_fd):
    if symlink_rollback_race_target.is_symlink() and not verification_failed:
        verification_failed.append(True)
        raise module.ConcurrentUpdate("injected post-install verification failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

def save_during_atomic_rollback_exchange(first_fd, first, second_fd, second):
    if not os.path.lexists(symlink_rollback_race_target):
        raise SystemExit("managed command path was missing before an atomic exchange")
    exchange_calls.append((first, second))
    if len(exchange_calls) == 2 and not race_injected:
        user_save = symlink_rollback_race_target.with_name("user-save.md")
        user_save.write_text("concurrent user save\n")
        os.replace(user_save, symlink_rollback_race_target)
        race_injected.append(True)
    result = real_exchange(first_fd, first, second_fd, second)
    if not os.path.lexists(symlink_rollback_race_target):
        raise SystemExit("managed command path was missing after an atomic exchange")
    return result

module._verify_parent_path = fail_after_install_with_late_save
module._rename_exchange = save_during_atomic_rollback_exchange
try:
    try:
        module.sync_symlink(
            str(symlink_rollback_race_home), ".claude/commands/managed.md", "snapshot",
            str(symlink_rollback_race_snapshot), "/repo/claude/skill-sources/managed.md",
        )
    except module.RestorationFailed as error:
        if not error.recovery_path or Path(error.recovery_path).read_text() != "original managed command\n":
            raise SystemExit("rollback did not retain the displaced command after a concurrent save")
    else:
        raise SystemExit("rollback reported success after a concurrent save replaced its new link")
finally:
    module._verify_parent_path = real_verify
    module._rename_exchange = real_exchange
if not race_injected or symlink_rollback_race_target.read_text() != "concurrent user save\n":
    raise SystemExit("symlink rollback deleted a concurrent atomic save")

# If syncing an atomic rollback exchange errors, keep the original command
# live and return a fatal status with recovery data intact.
symlink_rollback_home = scratch / "symlink-rollback-home"
symlink_rollback_home.joinpath(".claude/commands").mkdir(parents=True)
symlink_rollback_target = symlink_rollback_home / ".claude/commands/managed.md"
symlink_rollback_snapshot = scratch / "symlink-rollback-snapshot.md"
symlink_rollback_source = scratch / "symlink-rollback-source.md"
symlink_rollback_target.write_text("old command\n")
symlink_rollback_snapshot.write_text("")
if not module.snapshot_file(
    str(symlink_rollback_home),
    ".claude/commands/managed.md",
    str(symlink_rollback_snapshot),
    recovery_boundary=str(symlink_rollback_target.parent),
):
    raise SystemExit("could not create managed-command rollback snapshot")
symlink_rollback_source.write_text("new command\n")
real_verify = module._verify_parent_path
real_fsync = module.os.fsync
verify_calls = [0]
rollback_exchange_done = []
real_exchange = module._rename_exchange
exchange_calls = [0]

def fail_after_install(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 1:
        raise module.ConcurrentUpdate("injected post-link verification failure")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

def mark_rollback_exchange(first_fd, first, second_fd, second):
    if not os.path.lexists(symlink_rollback_target):
        raise SystemExit("managed command path was missing before rollback exchange")
    exchange_calls[0] += 1
    result = real_exchange(first_fd, first, second_fd, second)
    if not os.path.lexists(symlink_rollback_target):
        raise SystemExit("managed command path was missing after rollback exchange")
    if exchange_calls[0] == 2:
        rollback_exchange_done.append(True)
    return result

def fail_rollback_sync(file_descriptor):
    if rollback_exchange_done and not getattr(fail_rollback_sync, "failed", False):
        fail_rollback_sync.failed = True
        raise OSError(5, "injected rollback directory fsync failure")
    return real_fsync(file_descriptor)

module._verify_parent_path = fail_after_install
module._rename_exchange = mark_rollback_exchange
module.os.fsync = fail_rollback_sync
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
    module._rename_exchange = real_exchange
    module.os.fsync = real_fsync
if not symlink_rollback_target.exists() or symlink_rollback_target.is_symlink() or symlink_rollback_target.read_text() != "old command\n":
    raise SystemExit("Claude symlink rollback left the live command missing or changed")

# A concurrent symlink replacement plus parent move must not be restored only
# into the detached directory and reported as a harmless no-op.
detached_symlink_home = scratch / "detached-symlink-home"
detached_symlink_dir = detached_symlink_home / ".claude/commands"
detached_symlink_dir.mkdir(parents=True)
detached_symlink_target = detached_symlink_dir / "managed.md"
detached_symlink_target.symlink_to("/expected/command.md")
detached_symlink_source = scratch / "detached-symlink-source.md"
detached_symlink_source.write_text("new command\n")
real_new_recovery_directory = module._new_recovery_directory

def replace_and_move_symlink_parent(parent_fd, parent_path):
    result = real_new_recovery_directory(parent_fd, parent_path)
    replacement = detached_symlink_target.with_name("managed.replacement")
    replacement.symlink_to("/concurrent/command.md")
    os.replace(replacement, detached_symlink_target)
    detached_symlink_dir.rename(detached_symlink_dir.with_name("commands-moved"))
    detached_symlink_dir.mkdir()
    return result

module._new_recovery_directory = replace_and_move_symlink_parent
try:
    module.sync_symlink(
        str(detached_symlink_home), ".claude/commands/managed.md", "link",
        "/expected/command.md", str(detached_symlink_source),
    )
except module.RestorationFailed:
    pass
else:
    raise SystemExit("detached symlink rollback was not reported as fatal")
finally:
    module._new_recovery_directory = real_new_recovery_directory
if detached_symlink_target.exists() or detached_symlink_target.is_symlink():
    raise SystemExit("detached symlink fixture unexpectedly restored into the live parent")
if os.readlink(detached_symlink_dir.with_name("commands-moved") / "managed.md") != "/concurrent/command.md":
    raise SystemExit("detached symlink fixture lost the concurrent replacement")

# If the command directory moves after symlink creation, do not report a safe
# rollback through the detached directory descriptor as status 3.
moved_commands_home = scratch / "moved-commands-home"
moved_commands_dir = moved_commands_home / ".claude/commands"
moved_commands_dir.mkdir(parents=True)
moved_commands_target = moved_commands_dir / "managed.md"
moved_commands_snapshot = scratch / "moved-commands-snapshot.md"
moved_commands_source = scratch / "moved-commands-source.md"
moved_commands_target.write_text("old command\n")
moved_commands_snapshot.write_text("")
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(moved_commands_home)
if not module.snapshot_file(
    str(moved_commands_home),
    ".claude/commands/managed.md",
    str(moved_commands_snapshot),
    recovery_boundary=str(moved_commands_dir),
):
    raise SystemExit("could not create moved-command rollback snapshot")
os.environ["HOME"] = previous_home
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
stable_command_backups = list((moved_commands_home / ".crosscheck-recovery").glob("snapshot-*.bak"))
if not any(path.read_text() == "old command\n" for path in stable_command_backups):
    raise SystemExit("moved Claude command did not retain its stable recovery copy")
if moved_commands_target.exists() or moved_commands_target.is_symlink():
    raise SystemExit("test fixture unexpectedly restored through the detached command directory")

# If a command file is replaced with identical bytes before its parent moves,
# stop before exchange and keep the concurrent replacement in the moved parent.
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
        raise SystemExit("moved parent did not report the original command recovery backup")
    if Path(error.recovery_path).read_text() != "old command\n":
        raise SystemExit("moved parent reported an invalid original command backup")
else:
    raise SystemExit("moved command parent did not report incomplete restoration")
finally:
    module._new_recovery_directory = real_new_recovery_directory
    module._verify_parent_path = real_verify
    os.environ["HOME"] = previous_home
moved_replacement_entries = list(replaced_commands_home.rglob(".crosscheck-publish-*/original"))
if moved_replacement_entries:
    raise SystemExit("publisher exchanged a command after its parent moved")
detached_replacement = replaced_commands_dir.with_name("commands-moved") / "managed.md"
if (detached_replacement.stat().st_dev, detached_replacement.stat().st_ino) != displaced_command_identity[0]:
    raise SystemExit("moved command directory lost the concurrent replacement")
if (old_command_identity == displaced_command_identity[0]):
    raise SystemExit("test did not create a distinct byte-identical replacement inode")

# If an operation fails immediately after displacement, publish a stable backup
# of the inode actually moved before reporting any recovery path.
fsync_race_home = scratch / "fsync-race-home"
fsync_race_dir = fsync_race_home / ".claude/commands"
fsync_race_dir.mkdir(parents=True)
fsync_race_target = fsync_race_dir / "managed.md"
fsync_race_snapshot = scratch / "fsync-race-snapshot.md"
fsync_race_source = scratch / "fsync-race-source.md"
fsync_race_target.write_text("old command\n")
fsync_race_snapshot.write_text("old command\n")
fsync_race_source.write_text("new command\n")
fsync_race_replacement_identity = [None]
real_new_recovery_directory = module._new_recovery_directory

def replace_fsync_race_command(parent_fd, parent_path):
    result = real_new_recovery_directory(parent_fd, parent_path)
    replacement = fsync_race_target.with_name("managed.replacement")
    replacement.write_text("old command\n")
    os.replace(replacement, fsync_race_target)
    replacement_stat = fsync_race_target.stat()
    fsync_race_replacement_identity[0] = (replacement_stat.st_dev, replacement_stat.st_ino)
    return result

real_fsync_directory = module._fsync_directory
displacement_happened = [False]
real_exchange = module._rename_exchange
exchange_calls = [0]
fail_sync_once = []

def fail_fsync_race_restore(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    if exchange_calls[0] == 2:
        raise OSError(errno.EIO, "injected restore failure after displacement")
    result = real_exchange(first_fd, first, second_fd, second)
    if exchange_calls[0] == 1:
        displacement_happened[0] = True
    return result

def fail_fsync_after_displacement(directory_fd):
    if displacement_happened[0] and not fail_sync_once:
        fail_sync_once.append(True)
        raise OSError(errno.EIO, "injected parent sync failure after displacement")
    return real_fsync_directory(directory_fd)

module._new_recovery_directory = replace_fsync_race_command
module._rename_exchange = fail_fsync_race_restore
module._fsync_directory = fail_fsync_after_displacement
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(fsync_race_home)
try:
    module.sync_symlink(
        str(fsync_race_home), ".claude/commands/managed.md", "snapshot",
        str(fsync_race_snapshot), str(fsync_race_source),
    )
except module.RestorationFailed as error:
    if not error.recovery_path or not Path(error.recovery_path).is_file():
        raise SystemExit("post-displacement failure did not report a stable command backup")
    backup_stat = Path(error.recovery_path).stat()
    if (backup_stat.st_dev, backup_stat.st_ino) != fsync_race_replacement_identity[0]:
        raise SystemExit("post-displacement failure reported a backup of the pre-replacement inode")
else:
    raise SystemExit("post-displacement fsync failure was not reported as a restoration failure")
finally:
    module._new_recovery_directory = real_new_recovery_directory
    module._rename_exchange = real_exchange
    module._fsync_directory = real_fsync_directory
    os.environ["HOME"] = previous_home

# A symlink created after an absent-path check is a preserved no-op.
absent_race_home = scratch / "absent-link-race-home"
absent_race_home.joinpath(".claude/commands").mkdir(parents=True)
absent_race_target = absent_race_home / ".claude/commands/managed.md"
absent_race_source = scratch / "absent-link-race-source.md"
absent_race_source.write_text("new command\n")
real_rename_noreplace = module._rename_noreplace

def create_concurrent_desired_link(source_fd, source, destination_fd, destination):
    if source.startswith("new-link-") and destination == "managed.md":
        os.symlink(absent_race_source, absent_race_target)
        raise FileExistsError(errno.EEXIST, "injected concurrent symlink creation", destination)
    return real_rename_noreplace(source_fd, source, destination_fd, destination)

module._rename_noreplace = create_concurrent_desired_link
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
    module._rename_noreplace = real_rename_noreplace
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

# If the stable recovery directory moves after rollback links are synced, keep
# the staged entry and report fatal restoration instead of a stale backup path.
rollback_recovery_home = scratch / "rollback-recovery-home"
rollback_recovery_root = scratch / "rollback-recovery-root"
rollback_recovery_home.mkdir()
rollback_recovery_root.mkdir()
rollback_recovery_target = rollback_recovery_root / "settings.json"
rollback_recovery_snapshot = scratch / "rollback-recovery-snapshot.json"
rollback_recovery_stage = scratch / "rollback-recovery-stage.json"
rollback_recovery_target.write_text('{"setting":"original"}\n')
rollback_recovery_snapshot.write_text("")
rollback_recovery_stage.write_text('{"setting":"updated"}\n')
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(rollback_recovery_home)
try:
    if not module.snapshot_file(
        str(rollback_recovery_root), "settings.json", str(rollback_recovery_snapshot)
    ):
        raise SystemExit("could not create rollback-recovery snapshot")
finally:
    os.environ["HOME"] = previous_home
real_exchange = module._rename_exchange
exchange_calls = [0]

def move_recovery_before_rollback_exchange(first_fd, first, second_fd, second):
    exchange_calls[0] += 1
    if exchange_calls[0] == 2:
        stable_dir = rollback_recovery_home / ".crosscheck-recovery"
        stable_dir.rename(rollback_recovery_home / ".crosscheck-recovery-moved")
    return real_exchange(first_fd, first, second_fd, second)

real_verify = module._verify_parent_path
verify_calls = [0]

def fail_after_first_publish_exchange(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        raise module.ConcurrentUpdate("injected update failure before rollback")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._rename_exchange = move_recovery_before_rollback_exchange
module._verify_parent_path = fail_after_first_publish_exchange
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(rollback_recovery_home)
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "publish", str(rollback_recovery_root), "settings.json",
    str(rollback_recovery_snapshot), str(rollback_recovery_stage),
]
try:
    if module.main() != 5:
        raise SystemExit("moved rollback recovery directory did not return fatal status 5")
finally:
    module.sys.argv = original_argv
    module._rename_exchange = real_exchange
    module._verify_parent_path = real_verify
    os.environ["HOME"] = previous_home
if rollback_recovery_target.read_text() != '{"setting":"original"}\n':
    raise SystemExit("moved rollback recovery fixture did not restore the original settings")
if not list(stage_entries(rollback_recovery_root)):
    raise SystemExit("moved rollback recovery directory allowed cleanup of the staged inode")

# A target parent moved during final rollback recovery validation must keep the
# stage and stable backups and return fatal restoration status.
late_rollback_home = scratch / "late-rollback-home"
late_rollback_root = scratch / "late-rollback-root"
late_rollback_home.mkdir()
late_rollback_root.mkdir()
late_rollback_target = late_rollback_root / "settings.json"
late_rollback_snapshot = scratch / "late-rollback-snapshot.json"
late_rollback_stage = scratch / "late-rollback-stage.json"
late_rollback_target.write_text('{"lateRollback":"original"}\n')
late_rollback_snapshot.write_text("")
late_rollback_stage.write_text('{"lateRollback":"updated"}\n')
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(late_rollback_home)
try:
    if not module.snapshot_file(str(late_rollback_root), "settings.json", str(late_rollback_snapshot)):
        raise SystemExit("could not create late-rollback snapshot")
finally:
    os.environ["HOME"] = previous_home
real_verify = module._verify_parent_path
verify_calls = [0]

def fail_before_late_rollback(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        raise module.ConcurrentUpdate("injected failure that starts rollback")
    return real_verify(root_fd, root_path, relative_target, parent_fd)

real_verify_link = module._verify_stable_recovery_link
recovery_verify_calls = [0]

def move_parent_during_rollback_recovery(*args, **kwargs):
    result = real_verify_link(*args, **kwargs)
    recovery_verify_calls[0] += 1
    if recovery_verify_calls[0] == 1:
        late_rollback_root.rename(late_rollback_root.with_name("late-rollback-root-detached"))
        late_rollback_root.mkdir()
    return result

module._verify_parent_path = fail_before_late_rollback
module._verify_stable_recovery_link = move_parent_during_rollback_recovery
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(late_rollback_home)
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "publish", str(late_rollback_root), "settings.json",
    str(late_rollback_snapshot), str(late_rollback_stage),
]
try:
    if module.main() != 5:
        raise SystemExit("late target-parent move during rollback did not return fatal status 5")
finally:
    module.sys.argv = original_argv
    module._verify_parent_path = real_verify
    module._verify_stable_recovery_link = real_verify_link
    os.environ["HOME"] = previous_home
late_rollback_detached = late_rollback_root.with_name("late-rollback-root-detached")
if (late_rollback_root / "settings.json").exists():
    raise SystemExit("rollback reported a live settings file in the recreated parent")
if not list(stage_entries(late_rollback_detached)):
    raise SystemExit("rollback discarded its stage after the parent moved during recovery checks")
if not any(
    backup.read_text() == '{"lateRollback":"original"}\n'
    for backup in (late_rollback_home / ".crosscheck-recovery").glob("settings-*.bak")
):
    raise SystemExit("rollback did not keep a stable original settings backup after the parent moved")

# A failed cleanup of the displaced file must report the exact retained inode.
unlink_error_home = scratch / "unlink-error-home"
unlink_error_root = scratch / "unlink-error-root"
unlink_error_home.mkdir()
unlink_error_root.mkdir()
unlink_error_target = unlink_error_root / "settings.json"
unlink_error_snapshot = scratch / "unlink-error-snapshot.json"
unlink_error_stage = scratch / "unlink-error-stage.json"
unlink_error_target.write_text('{"unlinkError":"original"}\n')
unlink_error_snapshot.write_text("")
unlink_error_stage.write_text('{"unlinkError":"updated"}\n')
unlink_error_original_identity = (unlink_error_target.stat().st_dev, unlink_error_target.stat().st_ino)
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(unlink_error_home)
try:
    if not module.snapshot_file(str(unlink_error_root), "settings.json", str(unlink_error_snapshot)):
        raise SystemExit("could not create unlink-error snapshot")
finally:
    os.environ["HOME"] = previous_home
real_unlink = module.os.unlink

def fail_publisher_stage_unlink(path, *args, **kwargs):
    if isinstance(path, str) and path.startswith(".crosscheck-stage-"):
        raise OSError(errno.EIO, "injected staged settings cleanup failure")
    return real_unlink(path, *args, **kwargs)

module.os.unlink = fail_publisher_stage_unlink
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(unlink_error_home)
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "publish", str(unlink_error_root), "settings.json",
    str(unlink_error_snapshot), str(unlink_error_stage),
]
try:
    diagnostic = io.StringIO()
    with contextlib.redirect_stderr(diagnostic):
        result = module.main()
    if result != 5:
        raise SystemExit("publisher ignored a failed staged settings cleanup")
finally:
    module.sys.argv = original_argv
    module.os.unlink = real_unlink
    os.environ["HOME"] = previous_home
unlink_error_line = next(
    (line for line in diagnostic.getvalue().splitlines() if line.startswith("recovery data remains at ")),
    None,
)
if unlink_error_line is None:
    raise SystemExit("publisher omitted the staged settings recovery path after cleanup failure")
unlink_error_recovery = Path(unlink_error_line.removeprefix("recovery data remains at "))
unlink_error_identity = (unlink_error_recovery.stat().st_dev, unlink_error_recovery.stat().st_ino)
if unlink_error_identity != unlink_error_original_identity:
    raise SystemExit("publisher reported the wrong settings inode after staged cleanup failure")
if not any(
    (path.stat().st_dev, path.stat().st_ino) == unlink_error_identity
    for path in stage_entries(unlink_error_root)
):
    raise SystemExit("publisher recovery path does not identify the retained staging inode")

# Replacing a published-inode backup during the rollback parent check must be
# fatal and retain the staged inode for recovery.
backup_rollback_home = scratch / "backup-rollback-home"
backup_rollback_root = scratch / "backup-rollback-root"
backup_rollback_home.mkdir()
backup_rollback_root.mkdir()
backup_rollback_target = backup_rollback_root / "settings.json"
backup_rollback_snapshot = scratch / "backup-rollback-snapshot.json"
backup_rollback_stage = scratch / "backup-rollback-stage.json"
backup_rollback_original = '{"backupRollback":"original"}\n'
backup_rollback_updated = '{"backupRollback":"updated"}\n'
backup_rollback_target.write_text(backup_rollback_original)
backup_rollback_snapshot.write_text("")
backup_rollback_stage.write_text(backup_rollback_updated)
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(backup_rollback_home)
try:
    if not module.snapshot_file(str(backup_rollback_root), "settings.json", str(backup_rollback_snapshot)):
        raise SystemExit("could not create backup-rollback snapshot")
finally:
    os.environ["HOME"] = previous_home
real_verify = module._verify_parent_path
verify_calls = [0]

def replace_backup_during_rollback_parent_check(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        raise module.ConcurrentUpdate("injected failure that starts rollback")
    if verify_calls[0] == 4:
        backup_dir = backup_rollback_home / ".crosscheck-recovery"
        backup = next(path for path in backup_dir.glob("settings-*.bak") if path.read_text() == backup_rollback_updated)
        replacement = backup.with_name(backup.name + ".replacement")
        mode = stat.S_IMODE(backup.stat().st_mode)
        replacement.write_text(backup_rollback_updated)
        replacement.chmod(mode)
        os.replace(replacement, backup)
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = replace_backup_during_rollback_parent_check
previous_home = os.environ["HOME"]
os.environ["HOME"] = str(backup_rollback_home)
original_argv = module.sys.argv
module.sys.argv = [
    "atomic-publish-file.py", "publish", str(backup_rollback_root), "settings.json",
    str(backup_rollback_snapshot), str(backup_rollback_stage),
]
try:
    diagnostic = io.StringIO()
    with contextlib.redirect_stderr(diagnostic):
        result = module.main()
    if result != 5:
        raise SystemExit("rollback accepted a replaced published-inode recovery link")
finally:
    module.sys.argv = original_argv
    module._verify_parent_path = real_verify
    os.environ["HOME"] = previous_home
if backup_rollback_target.read_text() != backup_rollback_original:
    raise SystemExit("rollback changed the live original settings after recovery-link replacement")
if not any(path.read_text() == backup_rollback_updated for path in stage_entries(backup_rollback_root)):
    raise SystemExit("rollback removed the only staged published inode after recovery-link replacement")
recovery_line = next(
    (line for line in diagnostic.getvalue().splitlines() if line.startswith("recovery data remains at ")),
    None,
)
if recovery_line is None:
    raise SystemExit("rollback did not report where staged published settings remain")
reported_recovery = Path(recovery_line.removeprefix("recovery data remains at "))
if reported_recovery.read_text() != backup_rollback_updated:
    raise SystemExit(f"rollback reported the wrong recovery data path: {reported_recovery}")
reported_identity = (reported_recovery.stat().st_dev, reported_recovery.stat().st_ino)
if not any(
    (path.stat().st_dev, path.stat().st_ino) == reported_identity
    for path in stage_entries(backup_rollback_root)
):
    raise SystemExit("rollback reported matching bytes from the wrong staged inode")

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

def swap_skill_directory(source_path, directory_fd, mode_override=None):
    moved_dir = skill_dir.with_name("example-moved")
    skill_dir.rename(moved_dir)
    skill_dir.symlink_to(outside, target_is_directory=True)
    return real_copy(source_path, directory_fd, mode_override)

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

# Every newly created ancestor must have its containing directory synced before
# publication can report success.
ancestor_sync_root = scratch / "ancestor-sync-root"
ancestor_sync_root.mkdir()
ancestor_sync_stage = scratch / "ancestor-sync-stage.md"
ancestor_sync_stage.write_text("nested skill\n")
ancestor_sync_skills = ancestor_sync_root / "skills"
ancestor_sync_new = ancestor_sync_skills / "new"
ancestor_sync_target = ancestor_sync_new / "SKILL.md"
ancestor_sync_root_identity = (ancestor_sync_root.stat().st_dev, ancestor_sync_root.stat().st_ino)
ancestor_root_synced_before_child = [False]
ancestor_parent_synced_before_file = [False]
real_fsync_directory = module._fsync_directory

def track_ancestor_directory_sync(directory_fd):
    info = os.fstat(directory_fd)
    identity = (info.st_dev, info.st_ino)
    if identity == ancestor_sync_root_identity and ancestor_sync_skills.exists() and not ancestor_sync_new.exists():
        ancestor_root_synced_before_child[0] = True
    if ancestor_sync_skills.exists():
        skills_stat = ancestor_sync_skills.stat()
        if (
            identity == (skills_stat.st_dev, skills_stat.st_ino)
            and ancestor_sync_new.exists()
            and not ancestor_sync_target.exists()
        ):
            ancestor_parent_synced_before_file[0] = True
    return real_fsync_directory(directory_fd)

module._fsync_directory = track_ancestor_directory_sync
try:
    module.publish_file(
        str(ancestor_sync_root), "skills/new/SKILL.md", None, str(ancestor_sync_stage)
    )
finally:
    module._fsync_directory = real_fsync_directory
if not ancestor_root_synced_before_child[0]:
    raise SystemExit("publisher did not sync the root after creating the first path component")
if not ancestor_parent_synced_before_file[0]:
    raise SystemExit("publisher did not sync the intermediate directory after creating its child")
if ancestor_sync_target.read_text() != "nested skill\n":
    raise SystemExit("nested first-time publication did not leave the requested file")

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

# Replacing the stable backup with a same-content inode during final migration
# sync must fail closed and keep a link to the displaced file's real inode.
replacement_home = scratch / "replacement-command-home"
replacement_command = replacement_home / ".claude/commands/managed.md"
replacement_command.parent.mkdir(parents=True)
replacement_command.write_text("original managed command\n")
replacement_snapshot = scratch / "replacement-command-snapshot.md"
replacement_snapshot.write_text("original managed command\n")
replacement_fd = replacement_command.open("r+")
original_identity = (replacement_command.stat().st_dev, replacement_command.stat().st_ino)
real_sync_recovery = module._sync_stable_recovery_entry
sync_calls = [0]

def replace_stable_backup_after_final_sync(
    base_fd, base_path, recovery_fd, recovery_name, recovery_dir, entry_name
):
    result = real_sync_recovery(
        base_fd, base_path, recovery_fd, recovery_name, recovery_dir, entry_name
    )
    sync_calls[0] += 1
    if sync_calls[0] == 2:
        backup = Path(recovery_dir) / entry_name
        replacement = backup.with_name(backup.name + ".replacement")
        mode = stat.S_IMODE(backup.stat().st_mode)
        replacement.write_text(backup.read_text())
        replacement.chmod(mode)
        os.replace(replacement, backup)
    return result

module._sync_stable_recovery_entry = replace_stable_backup_after_final_sync
try:
    try:
        module.sync_symlink(
            str(replacement_home), ".claude/commands/managed.md", "snapshot",
            str(replacement_snapshot), "/repo/claude/skill-sources/managed.md",
        )
    except OSError:
        pass
    else:
        raise SystemExit("Claude command migration accepted a replaced stable recovery inode")
finally:
    module._sync_stable_recovery_entry = real_sync_recovery
replacement_fd.seek(0)
replacement_fd.truncate()
replacement_fd.write("late write through original descriptor\n")
replacement_fd.flush()
replacement_fd.close()
replacement_backups = list((Path(os.environ["HOME"]) / ".crosscheck-recovery").glob("settings-*.bak"))
if not any(
    (backup.stat().st_dev, backup.stat().st_ino) == original_identity
    and backup.read_text() == "late write through original descriptor\n"
    for backup in replacement_backups
):
    raise SystemExit("Claude command migration discarded the only link to the original inode")
if replacement_command.is_symlink() or replacement_command.read_text() != "late write through original descriptor\n":
    raise SystemExit("Claude command migration did not restore the original inode after failed verification")

# Replacing the command backup during the final parent check must leave the
# original inode recoverable through either the restored command or backup.
parent_check_home = scratch / "parent-check-command-home"
parent_check_command = parent_check_home / ".claude/commands/managed.md"
parent_check_command.parent.mkdir(parents=True)
parent_check_text = "parent-check original command\n"
parent_check_command.write_text(parent_check_text)
parent_check_snapshot = scratch / "parent-check-command-snapshot.md"
parent_check_snapshot.write_text(parent_check_text)
parent_check_fd = parent_check_command.open("r+")
parent_check_identity = (parent_check_command.stat().st_dev, parent_check_command.stat().st_ino)
real_verify = module._verify_parent_path
verify_calls = [0]
real_sync_recovery = module._sync_stable_recovery_entry
parent_check_backup = [None]

def capture_parent_check_backup(base_fd, base_path, recovery_fd, recovery_name, recovery_dir, entry_name):
    result = real_sync_recovery(
        base_fd, base_path, recovery_fd, recovery_name, recovery_dir, entry_name
    )
    parent_check_backup[0] = Path(recovery_dir) / entry_name
    return result

def replace_command_backup_during_parent_check(root_fd, root_path, relative_target, parent_fd):
    verify_calls[0] += 1
    if verify_calls[0] == 2:
        backup = parent_check_backup[0]
        if backup is None or backup.read_text() != parent_check_text:
            raise SystemExit("Claude command migration did not stage its stable recovery link")
        replacement = backup.with_name(backup.name + ".replacement")
        mode = stat.S_IMODE(backup.stat().st_mode)
        replacement.write_text(parent_check_text)
        replacement.chmod(mode)
        os.replace(replacement, backup)
    return real_verify(root_fd, root_path, relative_target, parent_fd)

module._verify_parent_path = replace_command_backup_during_parent_check
module._sync_stable_recovery_entry = capture_parent_check_backup
previous_home = os.environ["HOME"]
try:
    try:
        module.sync_symlink(
            str(parent_check_home), ".claude/commands/managed.md", "snapshot",
            str(parent_check_snapshot), "/repo/claude/skill-sources/managed.md",
        )
    except module.RestorationFailed:
        pass
    else:
        raise SystemExit("Claude command migration accepted a replaced backup during its final parent check")
finally:
    os.environ["HOME"] = previous_home
    module._verify_parent_path = real_verify
    module._sync_stable_recovery_entry = real_sync_recovery
parent_check_fd.seek(0)
parent_check_fd.truncate()
parent_check_fd.write("late write after parent check\n")
parent_check_fd.flush()
parent_check_fd.close()
parent_check_backups = list((Path(previous_home) / ".crosscheck-recovery").glob("settings-*.bak"))
recovery_link_has_original = any(
    (backup.stat().st_dev, backup.stat().st_ino) == parent_check_identity
    and backup.read_text() == "late write after parent check\n"
    for backup in parent_check_backups
)
live_command_has_original = (
    not parent_check_command.is_symlink()
    and (parent_check_command.stat().st_dev, parent_check_command.stat().st_ino) == parent_check_identity
)
if not recovery_link_has_original and not live_command_has_original:
    raise SystemExit("Claude migration lost the original inode after backup replacement during parent check")
if parent_check_command.is_symlink() or parent_check_command.read_text() != "late write after parent check\n":
    raise SystemExit("Claude migration failed to restore the original command after backup replacement")

race_dir = scratch / "command-race-home"
race_command = race_dir / ".claude/commands/managed.md"
race_command.parent.mkdir(parents=True)
race_snapshot = scratch / "command-race-snapshot.md"
race_command.write_text("published command\n")
race_snapshot.write_text("published command\n")
real_exchange = module._rename_exchange
race_edit_injected = []

def edit_command_after_exchange(first_fd, first, second_fd, second):
    result = real_exchange(first_fd, first, second_fd, second)
    if first == "managed.md" and second == "original" and not race_edit_injected:
        (race_command.parent / next(race_command.parent.glob(".crosscheck-publish-*")) / "original").write_text("concurrent user edit\n")
        race_edit_injected.append(True)
    return result

module._rename_exchange = edit_command_after_exchange
try:
    module.sync_symlink(
        str(race_dir), ".claude/commands/managed.md", "snapshot", str(race_snapshot), "/repo/claude/skill-sources/managed.md"
    )
finally:
    module._rename_exchange = real_exchange
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
CRITICAL_SETTINGS_INODE="$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(f"{s.st_dev}:{s.st_ino}")' "$CRITICAL_HOME/.claude/actual.json")"
CRITICAL_BACKUP_COUNT="$(find "$HOME/.crosscheck-recovery" -maxdepth 1 -name 'settings-*.bak' -type f 2>/dev/null | wc -l | tr -d ' ')"
python3 - "$CRITICAL_HOME/.claude/actual.json" <<'PY'
import json
import sys
from pathlib import Path

settings = Path(sys.argv[1])
settings.write_text(json.dumps(json.loads(settings.read_text()), separators=(",", ":")) + "\n")
PY
for SETTINGS_SYNC in "$REPO_ROOT/scripts/sync-critical-settings.sh" \
  "$REPO_ROOT/claude/scripts/sync-critical-settings.sh" \
  "$REPO_ROOT/codex/scripts/sync-critical-settings.sh"; do
  sync_run=0
  while [ "$sync_run" -lt 3 ]; do
    if ! TMPDIR="$TEMP_DIR" "$SETTINGS_SYNC" "$CRITICAL_HOME/.claude/settings.json" --include-ask | grep -Fq 'already current'; then
      echo "$SETTINGS_SYNC did not report an unchanged critical settings no-op" >&2
      exit 1
    fi
    sync_run=$((sync_run + 1))
  done
done
if [ "$CRITICAL_SETTINGS_INODE" != "$(python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(f"{s.st_dev}:{s.st_ino}")' "$CRITICAL_HOME/.claude/actual.json")" ] \
  || [ "$CRITICAL_BACKUP_COUNT" != "$(find "$HOME/.crosscheck-recovery" -maxdepth 1 -name 'settings-*.bak' -type f 2>/dev/null | wc -l | tr -d ' ')" ]; then
  echo "unchanged critical settings sync replaced the settings inode or added recovery backups" >&2
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
