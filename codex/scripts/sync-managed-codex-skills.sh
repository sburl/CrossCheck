#!/usr/bin/env bash
set -euo pipefail

CROSSCHECK_ROOT="$(cd "${1:?usage: sync-managed-codex-skills.sh CROSSCHECK_ROOT HOME}" && pwd -P)"
TARGET_HOME="$(cd "${2:?usage: sync-managed-codex-skills.sh CROSSCHECK_ROOT HOME}" && pwd -P)"
if [ -d "$CROSSCHECK_ROOT/codex/skills" ]; then
  SOURCE_ROOT="$CROSSCHECK_ROOT/codex/skills"
  SOURCE_PREFIX="codex/skills"
else
  SOURCE_ROOT="$CROSSCHECK_ROOT/skills"
  SOURCE_PREFIX="skills"
fi

SKILLS_ROOT="$TARGET_HOME/.codex/skills"
SKIP_FILE="$TARGET_HOME/.crosscheck/skip-skills"
PUBLISH_HELPER="$CROSSCHECK_ROOT/scripts/atomic-publish-file.py"
UPDATED=0
PRESERVED=0
CURRENT_SNAPSHOT=""
CURRENT_STAGE=""
trap 'rm -f "$CURRENT_SNAPSHOT" "$CURRENT_STAGE"' EXIT

is_known_shipped_file() {
  local file_snapshot="$1" source_path="$2" revision
  git -C "$CROSSCHECK_ROOT" rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1 || return 1
  while IFS= read -r revision; do
    if git -C "$CROSSCHECK_ROOT" show "$revision:$source_path" 2>/dev/null | cmp -s - "$file_snapshot"; then
      return 0
    fi
  done < <(git -C "$CROSSCHECK_ROOT" rev-list refs/remotes/origin/main -- "$source_path" 2>/dev/null)
  return 1
}

has_symlink_ancestor() {
  local current="$1" root="$2"
  while [ "$current" != "$root" ]; do
    [ ! -L "$current" ] || return 0
    current="$(dirname "$current")"
  done
  return 1
}

if [ -L "$TARGET_HOME/.codex" ] || [ -L "$SKILLS_ROOT" ]; then
  echo "Preserving linked Codex skills directory; managed skill refresh skipped"
  exit 0
fi

for skill_dir in "$SOURCE_ROOT"/*; do
  [ -d "$skill_dir" ] && [ ! -L "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name="$(basename "$skill_dir")"
  if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
    continue
  fi
  target_dir="$SKILLS_ROOT/$skill_name"
  if [ -L "$target_dir" ] || { [ -e "$target_dir" ] && [ ! -d "$target_dir" ]; }; then
    echo "Preserving linked or non-directory Codex skill: $skill_name"
    PRESERVED=$((PRESERVED + 1))
    continue
  fi
  skill_changed=0
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$skill_dir"/}"
    target_file="$target_dir/$relative_path"
    target_relative=".codex/skills/$skill_name/$relative_path"
    target_parent="$(dirname "$target_file")"
    if has_symlink_ancestor "$target_parent" "$target_dir" || [ -L "$target_file" ] || { [ -e "$target_file" ] && [ ! -f "$target_file" ]; }; then
      echo "Preserving linked or non-regular Codex skill path: $skill_name/$relative_path"
      PRESERVED=$((PRESERVED + 1))
      continue
    fi

    expected_snapshot="--absent"
    CURRENT_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/crosscheck-snapshot.XXXXXX")"
    if python3 "$PUBLISH_HELPER" snapshot "$TARGET_HOME" "$target_relative" "$CURRENT_SNAPSHOT"; then
      if cmp -s "$source_file" "$CURRENT_SNAPSHOT"; then
        rm -f "$CURRENT_SNAPSHOT"
        CURRENT_SNAPSHOT=""
        continue
      fi
      source_path="$SOURCE_PREFIX/$skill_name/$relative_path"
      if ! is_known_shipped_file "$CURRENT_SNAPSHOT" "$source_path"; then
        echo "Preserving customized Codex skill file: $skill_name/$relative_path"
        PRESERVED=$((PRESERVED + 1))
        rm -f "$CURRENT_SNAPSHOT"
        CURRENT_SNAPSHOT=""
        continue
      fi
      expected_snapshot="$CURRENT_SNAPSHOT"
    else
      snapshot_status=$?
      rm -f "$CURRENT_SNAPSHOT"
      CURRENT_SNAPSHOT=""
      if [ "$snapshot_status" -ne 4 ]; then
        echo "Preserving linked, unsafe, or changed Codex skill path: $skill_name/$relative_path"
        PRESERVED=$((PRESERVED + 1))
        continue
      fi
    fi

    CURRENT_STAGE="$(mktemp "${TMPDIR:-/tmp}/crosscheck-stage.XXXXXX")"
    cp -p "$source_file" "$CURRENT_STAGE"
    if python3 "$PUBLISH_HELPER" publish "$TARGET_HOME" "$target_relative" "$expected_snapshot" "$CURRENT_STAGE"; then
      skill_changed=1
    else
      PRESERVED=$((PRESERVED + 1))
    fi
    rm -f "$CURRENT_SNAPSHOT" "$CURRENT_STAGE"
    CURRENT_SNAPSHOT=""
    CURRENT_STAGE=""
  done < <(find "$skill_dir" -type f -print0)
  if [ "$skill_changed" -eq 1 ]; then
    UPDATED=$((UPDATED + 1))
  fi
done

echo "Refreshed $UPDATED Codex-native skill(s); preserved $PRESERVED customized, linked, or concurrent path(s)"
