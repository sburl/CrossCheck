#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"

# Build sorted name lists (exclude INSTALL.md meta-doc).
ROOT_LIST=$(find "$ROOT_DIR/skill-sources" -maxdepth 1 -name '*.md' ! -name 'INSTALL.md' -exec basename {} \; 2>/dev/null | sort)
CLAUDE_LIST=$(find "$ROOT_DIR/claude/skill-sources" -maxdepth 1 -name '*.md' ! -name 'INSTALL.md' -exec basename {} \; 2>/dev/null | sort)
CODEX_LIST=$(find "$ROOT_DIR/codex/skill-sources" -maxdepth 1 -name '*.md' ! -name 'INSTALL.md' -exec basename {} \; 2>/dev/null | sort)
CODEX_SKILLS_LIST=$(find "$ROOT_DIR/codex/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort)

# Derive counts from the lists (handles empty dirs correctly).
ROOT_COUNT=$(echo "$ROOT_LIST" | grep -c . || true)
CLAUDE_COUNT=$(echo "$CLAUDE_LIST" | grep -c . || true)
CODEX_COUNT=$(echo "$CODEX_LIST" | grep -c . || true)
CODEX_SKILLS_COUNT=$(echo "$CODEX_SKILLS_LIST" | grep -c . || true)

echo "Root skill-sources: $ROOT_COUNT"
echo "Claude skill-sources: $CLAUDE_COUNT"
echo "Codex skill-sources: $CODEX_COUNT"
echo "Codex skills dirs: $CODEX_SKILLS_COUNT"

FAIL=0

# Compare file names (not just counts) between root and Claude.
if ! diff -q <(echo "$ROOT_LIST") <(echo "$CLAUDE_LIST") >/dev/null 2>&1; then
  echo "❌ FAIL: Root and Claude skill-sources differ:"
  diff <(echo "$ROOT_LIST") <(echo "$CLAUDE_LIST") || true
  FAIL=1
fi

# Compare file names between root and Codex.
if ! diff -q <(echo "$ROOT_LIST") <(echo "$CODEX_LIST") >/dev/null 2>&1; then
  echo "❌ FAIL: Root and Codex skill-sources differ:"
  diff <(echo "$ROOT_LIST") <(echo "$CODEX_LIST") || true
  FAIL=1
fi

# Compare skill names between root .md files and Codex skill directories.
ROOT_NAMES=$(echo "$ROOT_LIST" | sed 's/\.md$//')
if ! diff -q <(echo "$ROOT_NAMES") <(echo "$CODEX_SKILLS_LIST") >/dev/null 2>&1; then
  echo "❌ FAIL: Root skill-sources and Codex skills dirs differ:"
  diff <(echo "$ROOT_NAMES") <(echo "$CODEX_SKILLS_LIST") || true
  FAIL=1
fi

# A named Codex skill is not a complete mirror without its entrypoint.
while IFS= read -r skill_name; do
  [ -n "$skill_name" ] || continue
  if [ ! -f "$ROOT_DIR/codex/skills/$skill_name/SKILL.md" ] || [ -L "$ROOT_DIR/codex/skills/$skill_name/SKILL.md" ]; then
    echo "❌ FAIL: Missing required Codex skill entrypoint: codex/skills/$skill_name/SKILL.md"
    FAIL=1
  fi
done <<< "$CODEX_SKILLS_LIST"

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "Mirror directories are out of sync. When adding skills,"
  echo "update all three: skill-sources/, claude/skill-sources/, codex/skill-sources/"
  echo "and create codex/skills/<name>/SKILL.md"
  exit 1
fi

echo "✅ All mirror directories match ($ROOT_COUNT skills)"
