#!/bin/bash
# Codex Post-Commit Review Hook
# Provides quick feedback after each commit

# Allow skipping via environment variable
if [ "$SKIP_CODEX_REVIEW" = "1" ]; then
    exit 0
fi

# Get commit info
COMMIT_HASH=$(git log -1 --pretty=%H)
COMMIT_MSG=$(git log -1 --pretty=%B)
COMMIT_SUBJECT=$(git log -1 --pretty=%s)
CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | head -10)
FILE_COUNT=$(git diff-tree --no-commit-id --name-only -r HEAD | wc -l | tr -d ' ')

# Skip if no files changed (e.g., merge commits)
if [ "$FILE_COUNT" -eq 0 ]; then
    exit 0
fi

# Only review feat/fix/refactor/test commits (as documented)
# Supports scoped commits: feat(ui):, fix(P2):, etc.
# Supports breaking changes: feat!:, feat(scope)!:, etc.
if ! echo "$COMMIT_SUBJECT" | grep -qE "^(feat|fix|refactor|test)(\(.*\))?!?:"; then
    exit 0
fi

# Create prompt for Codex
PROMPT="Quick commit review - this is a git post-commit hook so keep feedback brief.

Commit: $COMMIT_HASH
Message: $COMMIT_MSG

Changed files ($FILE_COUNT total, showing first 10):
$CHANGED_FILES

Quick checks:
1. Does commit match message?
2. Any obvious bugs or security issues?
3. Any breaking changes not mentioned in message?

Keep it brief - just flag critical issues. Respond with 'LGTM' if no issues found.

Severity: CRITICAL/HIGH only (skip medium/low for commit hooks)."

# Log review prompt for later (manual Codex review via Claude Code)
LOG_FILE="$HOME/.claude/codex-commit-reviews.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Rotate log if it exceeds 2000 lines (prevent unbounded growth)
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 2000 ]; then
    tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Write synchronously (avoids interleaved output from rapid commits)
{
    echo ""
    echo "=== Commit Review Needed: $(date +"%Y-%m-%d %H:%M:%S") ==="
    echo "$PROMPT"
    echo ""
    echo "To review: Copy above prompt and send to Codex via Claude Code terminal"
    echo "Or run: tail -f ~/.claude/codex-commit-reviews.log"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
} >> "$LOG_FILE"

echo "📝 Commit logged for Codex review: $LOG_FILE" >&2

exit 0
