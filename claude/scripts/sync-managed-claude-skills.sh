#!/usr/bin/env bash
set -euo pipefail

CROSSCHECK_DIR="${1:?usage: sync-managed-claude-skills.sh CROSSCHECK_DIR [HOME_DIR]}"
HOME_DIR="${2:-$HOME}"
CLAUDE_SKILL_DIR="$CROSSCHECK_DIR/claude/skill-sources"
ROOT_SKILL_DIR="$CROSSCHECK_DIR/skill-sources"
TARGET_DIR="$HOME_DIR/.claude/commands"
SKIP_FILE="$HOME_DIR/.crosscheck/skip-skills"

if [ ! -d "$CLAUDE_SKILL_DIR" ]; then
  echo "Claude skill sources not found: $CLAUDE_SKILL_DIR" >&2
  exit 1
fi

is_known_shipped_copy() {
  local target="$1" skill_name="$2" source_path revision

  if cmp -s "$target" "$CLAUDE_SKILL_DIR/$skill_name.md" || cmp -s "$target" "$ROOT_SKILL_DIR/$skill_name.md"; then
    return 0
  fi

  # Copies made by older bootstrap versions can be migrated only when their
  # exact bytes match a version tracked in this checkout's Git history.
  if ! git -C "$CROSSCHECK_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  for source_path in "claude/skill-sources/$skill_name.md" "skill-sources/$skill_name.md"; do
    while IFS= read -r revision; do
      if git -C "$CROSSCHECK_DIR" show "$revision:$source_path" 2>/dev/null | cmp -s - "$target"; then
        return 0
      fi
    done < <(git -C "$CROSSCHECK_DIR" rev-list --all -- "$source_path" 2>/dev/null)
  done
  return 1
}

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
  expected_claude="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$CLAUDE_SKILL_DIR/$skill_name.md")"
  expected_root="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$ROOT_SKILL_DIR/$skill_name.md")"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    ln -s "$skill_file" "$target"
    UPDATED=$((UPDATED + 1))
  elif [ -L "$target" ]; then
    target_source="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")"
    if [ "$target_source" = "$expected_claude" ] || [ "$target_source" = "$expected_root" ]; then
      if [ "$target_source" != "$expected_claude" ]; then
        ln -sfn "$skill_file" "$target"
        UPDATED=$((UPDATED + 1))
      fi
    fi
  elif [ -f "$target" ] && is_known_shipped_copy "$target" "$skill_name"; then
    rm "$target"
    ln -s "$skill_file" "$target"
    UPDATED=$((UPDATED + 1))
  fi
done

echo "Claude command links added or refreshed: $UPDATED"
