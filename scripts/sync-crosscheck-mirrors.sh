#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sync-crosscheck-mirrors.sh [options]

Options:
  --target <path>   Add an explicit mirror target path (can be repeated)
  --verify           Verify mirrored artifacts instead of syncing
  --help             Show this help

Environment:
  CROSSCHECK_MIRROR_PATHS  Extra mirror paths (newline/space-separated)
  CROSSCHECK_INCLUDE_NOTACTIVE When set to 1, also sync NotActive installs
EOF
}

VERIFY_ONLY=0
TARGETS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      TARGETS+=("${2:-}")
      shift 2
      ;;
    --verify)
      VERIFY_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_TARGETS=(
  "$HOME/.crosscheck"
  "$HOME/.claude/CrossCheck"
  "$HOME/.cache/CrossCheck"
)

if [ "${CROSSCHECK_INCLUDE_NOTACTIVE:-0}" = "1" ]; then
  if [ -d "$HOME/Documents/Developer/NotActive" ]; then
    while IFS= read -r notactive_target; do
      [ -z "$notactive_target" ] && continue
      DEFAULT_TARGETS+=("$notactive_target")
    done < <(
      find "$HOME/Documents/Developer/NotActive" -type d -name CrossCheck 2>/dev/null || true
    )
  fi
fi

for p in ${CROSSCHECK_MIRROR_PATHS:-}; do
  TARGETS+=("$p")
done

if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=("${DEFAULT_TARGETS[@]}")
fi

ROOT_FILES=(
  "scripts/request-pr-reviewer.sh"
  "scripts/sync-crosscheck-mirrors.sh"
  "claude/scripts/sync-crosscheck-mirrors.sh"
  "codex/scripts/sync-crosscheck-mirrors.sh"
  "claude/scripts/request-pr-reviewer.sh"
  "codex/scripts/request-pr-reviewer.sh"
  "skill-sources/submit-pr.md"
  "claude/skill-sources/submit-pr.md"
  "codex/skill-sources/submit-pr.md"
  "codex/skills/submit-pr/SKILL.md"
)

for target in "${TARGETS[@]}"; do
  if [ -z "$target" ]; then
    continue
  fi

  if [ ! -d "$target" ]; then
    echo "⚠️  Skip missing target: $target"
    continue
  fi

  if [ "$VERIFY_ONLY" = "1" ]; then
    echo "🔎 Verifying: $target"
    for rel in "${ROOT_FILES[@]}"; do
      source_file="$ROOT_DIR/$rel"
      mirror_file="$target/$rel"
      if [ ! -f "$mirror_file" ]; then
        echo "   ❌ Missing mirror file: $mirror_file"
        continue
      fi
      if cmp -s "$source_file" "$mirror_file"; then
        echo "   ✅ Match: $rel"
      else
        echo "   ⚠️  Drift: $rel"
      fi
    done
    continue
  fi

  echo "🔁 Syncing: $target"
  mkdir -p "$target/scripts" "$target/claude/scripts" "$target/codex/scripts" \
           "$target/skill-sources" "$target/claude/skill-sources" "$target/codex/skill-sources"

  for rel in "${ROOT_FILES[@]}"; do
    mkdir -p "$(dirname "$target/$rel")"
    cp "$ROOT_DIR/$rel" "$target/$rel"
  done

  chmod +x \
    "$target/scripts/sync-crosscheck-mirrors.sh" \
    "$target/claude/scripts/sync-crosscheck-mirrors.sh" \
    "$target/codex/scripts/sync-crosscheck-mirrors.sh" \
    "$target/scripts/request-pr-reviewer.sh" \
    "$target/claude/scripts/request-pr-reviewer.sh" \
    "$target/codex/scripts/request-pr-reviewer.sh"

  echo "   ✅ Synced $target"
done
