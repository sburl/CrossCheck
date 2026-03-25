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

# Collect files
ROOT_FILES=()
while IFS= read -r file; do
  # Exclude self from mirror requirements
  if [ "$file" = "check-script-mirrors.sh" ]; then
    continue
  fi
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
