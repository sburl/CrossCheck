#!/usr/bin/env bash
set -euo pipefail

CROSSCHECK_DIR="$(cd "${1:?usage: sync-managed-claude-skills.sh CROSSCHECK_DIR [HOME_DIR]}" && pwd -P)"
HOME_DIR="$(cd "${2:-$HOME}" && pwd -P)"
COUNT_ONLY=0
if [ "${3:-}" = "--count-only" ]; then
  COUNT_ONLY=1
elif [ "$#" -gt 2 ]; then
  echo "usage: sync-managed-claude-skills.sh CROSSCHECK_DIR [HOME_DIR] [--count-only]" >&2
  exit 2
fi
CLAUDE_SKILL_DIR="$CROSSCHECK_DIR/claude/skill-sources"
ROOT_SKILL_DIR="$CROSSCHECK_DIR/skill-sources"
TARGET_DIR="$HOME_DIR/.claude/commands"
SKIP_FILE="$HOME_DIR/.crosscheck/skip-skills"
PUBLISH_HELPER="$CROSSCHECK_DIR/scripts/atomic-publish-file.py"
CURRENT_SNAPSHOT=""
trap 'rm -f "$CURRENT_SNAPSHOT"' EXIT

if [ ! -d "$CLAUDE_SKILL_DIR" ]; then
  echo "Claude skill sources not found: $CLAUDE_SKILL_DIR" >&2
  exit 1
fi

is_known_shipped_copy() {
  local target="$1" skill_name="$2" source_path revision

  # Only versions published on main count as CrossCheck-owned. Local branches
  # can contain an unpublished file that happens to match a user command.
  if ! git -C "$CROSSCHECK_DIR" rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1; then
    return 1
  fi
  for source_path in "claude/skill-sources/$skill_name.md" "skill-sources/$skill_name.md"; do
    while IFS= read -r revision; do
      if git -C "$CROSSCHECK_DIR" show "$revision:$source_path" 2>/dev/null | cmp -s - "$target"; then
        return 0
      fi
    done < <(git -C "$CROSSCHECK_DIR" rev-list refs/remotes/origin/main -- "$source_path" 2>/dev/null)
  done
  return 1
}

UPDATED=0
PRESERVED=0

for skill_file in "$CLAUDE_SKILL_DIR/"*.md; do
  [ -f "$skill_file" ] || continue
  skill_name="$(basename "$skill_file" .md)"
  [ "$skill_name" = "INSTALL" ] && continue
  if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
    continue
  fi

  target="$TARGET_DIR/$skill_name.md"
  target_relative=".claude/commands/$skill_name.md"
  expected_claude="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$CLAUDE_SKILL_DIR/$skill_name.md")"
  expected_root="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$ROOT_SKILL_DIR/$skill_name.md")"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    if python3 "$PUBLISH_HELPER" symlink "$HOME_DIR" "$target_relative" absent - "$skill_file"; then
      UPDATED=$((UPDATED + 1))
    else
      PRESERVED=$((PRESERVED + 1))
    fi
  elif [ -L "$target" ]; then
    target_source="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$target")"
    if [ "$target_source" = "$expected_claude" ] || [ "$target_source" = "$expected_root" ]; then
      if [ "$target_source" != "$expected_claude" ]; then
        target_link="$(readlink "$target")"
        if python3 "$PUBLISH_HELPER" symlink "$HOME_DIR" "$target_relative" link "$target_link" "$skill_file"; then
          UPDATED=$((UPDATED + 1))
        else
          PRESERVED=$((PRESERVED + 1))
        fi
      fi
    fi
  elif [ -f "$target" ]; then
    CURRENT_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/crosscheck-command-snapshot.XXXXXX")"
    if python3 "$PUBLISH_HELPER" snapshot "$HOME_DIR" "$target_relative" "$CURRENT_SNAPSHOT"; then
      if is_known_shipped_copy "$CURRENT_SNAPSHOT" "$skill_name"; then
        if python3 "$PUBLISH_HELPER" symlink "$HOME_DIR" "$target_relative" snapshot "$CURRENT_SNAPSHOT" "$skill_file"; then
          UPDATED=$((UPDATED + 1))
        else
          PRESERVED=$((PRESERVED + 1))
        fi
      else
        PRESERVED=$((PRESERVED + 1))
      fi
    else
      PRESERVED=$((PRESERVED + 1))
    fi
    rm -f "$CURRENT_SNAPSHOT"
    CURRENT_SNAPSHOT=""
  else
    PRESERVED=$((PRESERVED + 1))
  fi
done

SUMMARY="Claude command links added or refreshed: $UPDATED; preserved $PRESERVED customized, linked, or concurrent path(s)"
if [ "$COUNT_ONLY" -eq 1 ]; then
  printf '%s\n' "$UPDATED"
  printf '%s\n' "$SUMMARY" >&2
else
  printf '%s\n' "$SUMMARY"
fi
