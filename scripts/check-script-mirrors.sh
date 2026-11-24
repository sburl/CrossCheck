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
  "install-supply-chain-hook.sh"
  "sync-managed-claude-skills.sh"
  "test-crosscheck-maintenance.sh"
)

# Codex's native skill updater is a Codex-only helper, not a mirror of a root script.
CODEX_ONLY=(
  "sync-managed-codex-skills.sh"
)

# Claude's supply-chain gate is required by its native PreToolUse hook.
CLAUDE_REQUIRED=(
  "preuse-supply-chain-gate.sh"
)

# Bootstrap needs the installer to keep the active checkout wired in.
CLAUDE_BOOTSTRAP_REQUIRED=(
  "install-supply-chain-hook.sh"
)

# Claude's PreToolUse hook consumes Claude-specific tool payloads. Do not
# require it in the Codex mirror, and reject it if it is copied there.
CODEX_EXCLUDED=(
  "preuse-supply-chain-gate.sh"
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

# Collect files
ROOT_FILES=()
while IFS= read -r file; do
  ROOT_FILES+=("$file")
done < <(find "$ROOT_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f -exec basename {} \; | sort)

CODEX_FILES=()
while IFS= read -r file; do
  CODEX_FILES+=("$file")
done < <(find "$CODEX_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f -exec basename {} \; | sort)

CLAUDE_FILES=()
while IFS= read -r file; do
  CLAUDE_FILES+=("$file")
done < <(find "$CLAUDE_SCRIPTS_DIR" -maxdepth 1 -name '*.sh' -type f -exec basename {} \; | sort)

printf 'Root scripts:   %d\n' "${#ROOT_FILES[@]}"
printf 'Codex scripts:  %d\n' "${#CODEX_FILES[@]}"
printf 'Claude scripts: %d\n\n' "${#CLAUDE_FILES[@]}"

missing_codemirror=0
missing_claudemirror=0
extra_codemirror=0
exec_mode_mismatch=0
missing_claude_required=0

# Check 1: every root script should exist in its target agent mirror.
for file in "${ROOT_FILES[@]}"; do
  ROOT_FILE="$ROOT_SCRIPTS_DIR/$file"
  CODEX_FILE="$CODEX_SCRIPTS_DIR/$file"
  CLAUDE_FILE="$CLAUDE_SCRIPTS_DIR/$file"

  if ! has_item "$file" "${CODEX_EXCLUDED[@]}"; then
    if [ -x "$ROOT_FILE" ] && [ ! -x "$CODEX_FILE" ]; then
      echo "❌ Codex mirror exec mismatch: scripts/$file (missing executable bit)"
      exec_mode_mismatch=$((exec_mode_mismatch + 1))
    elif [ ! -x "$ROOT_FILE" ] && [ -x "$CODEX_FILE" ]; then
      echo "❌ Codex mirror exec mismatch: scripts/$file (extra executable bit)"
      exec_mode_mismatch=$((exec_mode_mismatch + 1))
    fi

    if [ ! -f "$CODEX_FILE" ]; then
      echo "❌ Missing in codex mirror: scripts/$file"
      missing_codemirror=$((missing_codemirror + 1))
    fi
  fi

  if [ -x "$ROOT_FILE" ] && [ -f "$CLAUDE_FILE" ] && [ ! -x "$CLAUDE_FILE" ]; then
    echo "⚠️  Claude mirror exec mismatch: scripts/$file (missing executable bit)"
  elif [ ! -x "$ROOT_FILE" ] && [ -f "$CLAUDE_FILE" ] && [ -x "$CLAUDE_FILE" ]; then
    echo "⚠️  Claude mirror exec mismatch: scripts/$file (extra executable bit)"
  fi

  if [ ! -f "$CLAUDE_SCRIPTS_DIR/$file" ]; then
    if ! has_item "$file" "${CLAUDE_ONLY[@]}"; then
      echo "⚠️  Missing in claude mirror: scripts/$file"
      missing_claudemirror=$((missing_claudemirror + 1))
    fi
  fi
done

# Check 1b: security-sensitive Claude hooks must remain present in the mirror.
for file in "${CLAUDE_REQUIRED[@]}"; do
  if [ ! -f "$ROOT_SCRIPTS_DIR/$file" ] || [ ! -x "$ROOT_SCRIPTS_DIR/$file" ]; then
    echo "❌ Missing or non-executable required source: scripts/$file"
    missing_claude_required=$((missing_claude_required + 1))
  fi
  if [ ! -f "$CLAUDE_SCRIPTS_DIR/$file" ] || [ ! -x "$CLAUDE_SCRIPTS_DIR/$file" ]; then
    echo "❌ Missing or non-executable required Claude mirror: claude/scripts/$file"
    missing_claude_required=$((missing_claude_required + 1))
  fi
done

for file in "${CLAUDE_BOOTSTRAP_REQUIRED[@]}"; do
  if [ ! -f "$CLAUDE_SCRIPTS_DIR/$file" ] || [ ! -x "$CLAUDE_SCRIPTS_DIR/$file" ]; then
    echo "❌ Missing or non-executable required Claude bootstrap dependency: claude/scripts/$file"
    missing_claude_required=$((missing_claude_required + 1))
  fi
done

# Check 2: codex extras (anything not in root)
for file in "${CODEX_FILES[@]}"; do
  if has_item "$file" "${CODEX_EXCLUDED[@]}"; then
    echo "❌ Claude-only script present in Codex mirror: scripts/$file"
    extra_codemirror=$((extra_codemirror + 1))
  elif has_item "$file" "${CODEX_ONLY[@]}"; then
    continue
  elif ! has_item "$file" "${ROOT_FILES[@]}"; then
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

if [ "$missing_codemirror" -gt 0 ] || [ "$extra_codemirror" -gt 0 ] || [ "$exec_mode_mismatch" -gt 0 ] || [ "$missing_claude_required" -gt 0 ]; then
  echo ""
  echo "❌ Script mirror check failed"
  exit 1
fi

if [ "$missing_claudemirror" -gt 0 ]; then
  echo ""
  echo "⚠️  Claude mirror missing one or more root scripts (warning only)"
fi

echo ""
echo "✅ Script mirror audit passed with non-blocking warnings handled"
