#!/bin/bash
# fix-git-author.sh — Rewrite commit author info for commits not matching your identity.
#
# Usage:
#   ./fix-git-author.sh                    # Dry run — shows what would change
#   ./fix-git-author.sh --apply            # Actually rewrites history
#   ./fix-git-author.sh --apply --push     # Rewrite + force push
#
# This uses git filter-repo (preferred) or git filter-branch (fallback).
# WARNING: Rewrites history. Only use on repos where you are the sole contributor
# or have coordinated with collaborators.

set -euo pipefail

# Your correct identity — change these to match your GitHub account
CORRECT_NAME="Spencer Burleigh"
CORRECT_EMAIL="spence.burleigh@gmail.com"

APPLY=false
PUSH=false

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        --push) PUSH=true ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

echo "=== Git Author Fix ==="
echo "Correct identity: $CORRECT_NAME <$CORRECT_EMAIL>"
echo ""

# Show commits with wrong author
echo "Commits with non-matching author:"
git log --all --format='%H %ae %an — %s' | while read -r hash email name rest; do
    if [ "$email" != "$CORRECT_EMAIL" ]; then
        echo "  $hash $email $name $rest"
    fi
done

WRONG_COUNT=$(git log --all --format='%ae' | grep -cv "$CORRECT_EMAIL" || true)
echo ""
echo "Found $WRONG_COUNT commits with non-matching author."

if [ "$WRONG_COUNT" -eq 0 ]; then
    echo "Nothing to fix."
    exit 0
fi

if [ "$APPLY" = false ]; then
    echo ""
    echo "Dry run complete. Run with --apply to rewrite history."
    exit 0
fi

echo ""
echo "Rewriting history..."

# Prefer git filter-repo if available
if command -v git-filter-repo &>/dev/null; then
    git filter-repo --force \
        --name-callback "return b'$CORRECT_NAME'" \
        --email-callback "return b'$CORRECT_EMAIL'"
else
    # Fallback to filter-branch
    git filter-branch --force --env-filter "
        export GIT_AUTHOR_NAME='$CORRECT_NAME'
        export GIT_AUTHOR_EMAIL='$CORRECT_EMAIL'
        export GIT_COMMITTER_NAME='$CORRECT_NAME'
        export GIT_COMMITTER_EMAIL='$CORRECT_EMAIL'
    " --tag-name-filter cat -- --all
fi

echo "Done. History rewritten."

if [ "$PUSH" = true ]; then
    echo ""
    echo "Force pushing all branches..."
    git push --force --all
    git push --force --tags
    echo "Pushed."
else
    echo ""
    echo "Run 'git push --force --all' to push the rewritten history."
fi
