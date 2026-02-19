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

# Rotate and append under a single lock to prevent concurrent writers from
# losing entries during mv-based rotation (writer opens old inode, rotation
# replaces file, writer appends to unlinked inode — entry lost).
LOCK_FILE="$LOG_FILE.lock"
LOG_ENTRY="$(cat <<ENTRY

=== Commit Review Needed: $(date +"%Y-%m-%d %H:%M:%S") ===
$PROMPT

To review: Copy above prompt and send to Codex via Claude Code terminal
Or run: tail -F ~/.claude/codex-commit-reviews.log
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENTRY
)"

# Acquire lock (noclobber = atomic create-or-fail), retry up to 5 times
acquired=false
for _try in 1 2 3 4 5; do
    if (set -o noclobber; echo $$ > "$LOCK_FILE") 2>/dev/null; then
        acquired=true
        break
    fi
    # Remove stale lock left by a crashed process (PID no longer running)
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "$LOCK_FILE"
        # Retry immediately after clearing stale lock
        if (set -o noclobber; echo $$ > "$LOCK_FILE") 2>/dev/null; then
            acquired=true
            break
        fi
    fi
    sleep 0.2
done

if [ "$acquired" = true ]; then
    trap 'rm -f "$LOCK_FILE"' EXIT
    # Rotate if needed
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 2000 ]; then
        tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    # Append while still holding the lock (same inode guaranteed)
    printf '%s\n' "$LOG_ENTRY" >> "$LOG_FILE"
    rm -f "$LOCK_FILE"
    trap - EXIT
else
    # Could not acquire lock after 5 retries — skip this entry to avoid racing
    # with an active rotator (unlocked append can write to stale inode)
    echo "⚠️  Codex review log busy, entry skipped (will appear in next commit)" >&2
fi

if [ "$acquired" = true ]; then
    echo "📝 Commit logged for Codex review: $LOG_FILE" >&2
fi

exit 0
