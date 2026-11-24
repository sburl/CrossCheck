#!/usr/bin/env bash
set -euo pipefail

CROSSCHECK_DIR="${CROSSCHECK_DIR:?set CROSSCHECK_DIR to the CrossCheck checkout}"
HOME_DIR="${1:-$HOME}"
CLAUDE_SKILL_DIR="$CROSSCHECK_DIR/claude/skill-sources"
ROOT_SKILL_DIR="$CROSSCHECK_DIR/skill-sources"
TARGET_DIR="$HOME_DIR/.claude/commands"
SKIP_FILE="$HOME_DIR/.crosscheck/skip-skills"
CLAUDE_SKILL_DIR_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$CLAUDE_SKILL_DIR")"
ROOT_SKILL_DIR_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$ROOT_SKILL_DIR")"

if [ ! -d "$CLAUDE_SKILL_DIR" ]; then
  echo "Claude skill sources not found: $CLAUDE_SKILL_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
UPDATED=0

for skill_file in "$CLAUDE_SKILL_DIR/"*.md; do
  [ -f "$skill_file" ] || continue
  skill_name="$(basename "$skill_file" .md)"
  [ "$skill_name" = "INSTALL" ] && continue
  if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
    continue
  fi

  target="$TARGET_DIR/$skill_name.md"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    ln -s "$skill_file" "$target"
    UPDATED=$((UPDATED + 1))
  elif [ -L "$target" ]; then
    target_source="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")"
    if [[ "$target_source" == "$CLAUDE_SKILL_DIR_REAL/"* || "$target_source" == "$ROOT_SKILL_DIR_REAL/"* ]]; then
      ln -sfn "$skill_file" "$target"
      UPDATED=$((UPDATED + 1))
    fi
  elif [ -f "$target" ] && { cmp -s "$target" "$skill_file" || cmp -s "$target" "$ROOT_SKILL_DIR/$skill_name.md"; }; then
    rm "$target"
    ln -s "$skill_file" "$target"
    UPDATED=$((UPDATED + 1))
  fi
done

echo "Claude command links added or refreshed: $UPDATED"
