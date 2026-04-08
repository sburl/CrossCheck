#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_SCRIPTS_DIR="$ROOT_DIR/scripts"
CODEX_SCRIPTS_DIR="$ROOT_DIR/codex/scripts"
CLAUDE_SCRIPTS_DIR="$ROOT_DIR/claude/scripts"

# Script names expected only in Claude mirror (not yet in root/codex)
CLAUDE_ONLY=(
  "claude-approve-commit.sh"
  "claude-commit-review.sh"
  "install-claude-hooks.sh"
)

has_item() {
  local needle="$1"
  shift
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

# Check if a mirror file is a valid exec proxy that delegates to the canonical script.
# A proxy is a 2-line script: shebang + exec pointing to ../../scripts/<same-name>.
is_exec_proxy() {
  local file="$1"
  [ -f "$file" ] || return 1
  local line_count
  line_count=$(wc -l < "$file" | tr -d ' ')
  # Allow 2-3 lines (trailing newline variance)
  [ "$line_count" -le 3 ] || return 1
  grep -q 'exec.*\.\./\.\./scripts.*"\$@"' "$file" 2>/dev/null
}

# Collect files
ROOT_FILES=()
mapfile -t ROOT_FILES < <(find "$ROOT_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f | sort)
ROOT_FILES=("${ROOT_FILES[@]##*/}")

CODEX_FILES=()
mapfile -t CODEX_FILES < <(find "$CODEX_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f | sort)
CODEX_FILES=("${CODEX_FILES[@]##*/}")

CLAUDE_FILES=()
mapfile -t CLAUDE_FILES < <(find "$CLAUDE_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f | sort)
CLAUDE_FILES=("${CLAUDE_FILES[@]##*/}")

printf 'Root scripts:   %d\n' "${#ROOT_FILES[@]}"
printf 'Codex scripts:  %d\n' "${#CODEX_FILES[@]}"
printf 'Claude scripts: %d\n\n' "${#CLAUDE_FILES[@]}"

missing_codemirror=0
missing_claudemirror=0
extra_codemirror=0
exec_mode_mismatch=0
proxy_count=0
copy_count=0
delta_count=0

# Check 1: every root script should exist in codex mirror; warn if missing from claude mirror.
for file in "${ROOT_FILES[@]}"; do
  ROOT_FILE="$ROOT_SCRIPTS_DIR/$file"
  CODEX_FILE="$CODEX_SCRIPTS_DIR/$file"
  CLAUDE_FILE="$CLAUDE_SCRIPTS_DIR/$file"

  if [ -x "$ROOT_FILE" ] && [ ! -x "$CODEX_FILE" ]; then
    echo "❌ Codex mirror exec mismatch: scripts/$file (missing executable bit)"
    exec_mode_mismatch=$((exec_mode_mismatch + 1))
  elif [ ! -x "$ROOT_FILE" ] && [ -x "$CODEX_FILE" ]; then
    echo "❌ Codex mirror exec mismatch: scripts/$file (extra executable bit)"
    exec_mode_mismatch=$((exec_mode_mismatch + 1))
  fi
  if [ -x "$ROOT_FILE" ] && [ -f "$CLAUDE_FILE" ] && [ ! -x "$CLAUDE_FILE" ]; then
    echo "⚠️  Claude mirror exec mismatch: scripts/$file (missing executable bit)"
  elif [ ! -x "$ROOT_FILE" ] && [ -f "$CLAUDE_FILE" ] && [ -x "$CLAUDE_FILE" ]; then
    echo "⚠️  Claude mirror exec mismatch: scripts/$file (extra executable bit)"
  fi

  if [ ! -f "$CODEX_SCRIPTS_DIR/$file" ]; then
    echo "❌ Missing in codex mirror: scripts/$file"
    missing_codemirror=$((missing_codemirror + 1))
  fi

  if [ ! -f "$CLAUDE_SCRIPTS_DIR/$file" ]; then
    if ! has_item "$file" "${CLAUDE_ONLY[@]}"; then
      echo "⚠️  Missing in claude mirror: scripts/$file"
      missing_claudemirror=$((missing_claudemirror + 1))
    fi
  fi
done

# Check 2: codex extras (anything not in root)
for file in "${CODEX_FILES[@]}"; do
  if ! has_item "$file" "${ROOT_FILES[@]}"; then
    echo "❌ Extra in codex mirror (not in root): scripts/$file"
    extra_codemirror=$((extra_codemirror + 1))
  fi
done

# Check 3: claude extras (allow CLAUDE_ONLY)
for file in "${CLAUDE_FILES[@]}"; do
  if has_item "$file" "${ROOT_FILES[@]}"; then
    continue
  fi

  if ! has_item "$file" "${CLAUDE_ONLY[@]}"; then
    echo "⚠️  Unlisted claude-only script: scripts/$file"
  fi
done

# Check 4: mirror content — verify mirrors are exec proxies, exact copies, or intentional deltas
for file in "${ROOT_FILES[@]}"; do
  for mirror_dir in "$CODEX_SCRIPTS_DIR" "$CLAUDE_SCRIPTS_DIR"; do
    mirror_file="$mirror_dir/$file"
    [ -f "$mirror_file" ] || continue

    if is_exec_proxy "$mirror_file"; then
      proxy_count=$((proxy_count + 1))
    elif cmp -s "$ROOT_SCRIPTS_DIR/$file" "$mirror_file"; then
      copy_count=$((copy_count + 1))
    else
      delta_count=$((delta_count + 1))
    fi
  done
done

printf '\nMirror breakdown: %d proxy, %d exact copy, %d intentional delta\n' \
  "$proxy_count" "$copy_count" "$delta_count"

if [ "$copy_count" -gt 0 ]; then
  echo "⚠️  $copy_count mirror(s) are full copies — consider converting to exec proxies"
fi

if [ "$missing_codemirror" -gt 0 ] || [ "$extra_codemirror" -gt 0 ] || [ "$exec_mode_mismatch" -gt 0 ]; then
  echo ""
  echo "❌ Codex script mirror check failed"
  exit 1
fi

if [ "$missing_claudemirror" -gt 0 ]; then
  echo ""
  echo "⚠️  Claude mirror missing one or more root scripts (warning only)"
fi

echo ""
echo "✅ Script mirror audit passed with non-blocking warnings handled"
