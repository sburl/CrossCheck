#!/usr/bin/env bash
set -euo pipefail

CROSSCHECK_ROOT="$(cd "${1:?usage: sync-managed-codex-skills.sh CROSSCHECK_ROOT HOME}" && pwd)"
TARGET_HOME="$(cd "${2:?usage: sync-managed-codex-skills.sh CROSSCHECK_ROOT HOME}" && pwd)"
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

mkdir -p "$SKILLS_ROOT"
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
  mkdir -p "$target_dir"
  skill_changed=0
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$skill_dir"/}"
    target_file="$target_dir/$relative_path"
    target_parent="$(dirname "$target_file")"
    if has_symlink_ancestor "$target_parent" "$target_dir" || [ -L "$target_file" ] || { [ -e "$target_file" ] && [ ! -f "$target_file" ]; }; then
      echo "Preserving linked or non-regular Codex skill path: $skill_name/$relative_path"
      PRESERVED=$((PRESERVED + 1))
      continue
    fi

    expected_snapshot="--absent"
    if [ -f "$target_file" ]; then
      if cmp -s "$source_file" "$target_file"; then
        continue
      fi
      CURRENT_SNAPSHOT="$(mktemp "${target_file}.snapshot.XXXXXX")"
      cp -p "$target_file" "$CURRENT_SNAPSHOT"
      if ! cmp -s "$target_file" "$CURRENT_SNAPSHOT"; then
        echo "Preserving Codex skill changed during inspection: $skill_name/$relative_path"
        PRESERVED=$((PRESERVED + 1))
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
    fi

    mkdir -p "$target_parent"
    CURRENT_STAGE="$(mktemp "${target_file}.stage.XXXXXX")"
    cp -p "$source_file" "$CURRENT_STAGE"
    if python3 "$PUBLISH_HELPER" "$target_file" "$expected_snapshot" "$CURRENT_STAGE"; then
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
