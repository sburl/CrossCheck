#!/bin/bash
# Automatically configure GitHub repository ruleset for CrossCheck workflow
# Uses the rulesets API (newer, more flexible than classic branch protection)

set -e

echo "🔒 Setting up GitHub repository ruleset for main..."
echo ""

# Get repository owner and name from git remote
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REPO_URL" ]; then
    echo "❌ FAIL: Could not determine repository from git remote"
    echo "   Run this script from within a git repository"
    exit 1
fi

# Extract owner/repo from URL (supports both HTTPS and SSH)
OWNER_REPO=$(echo "$REPO_URL" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' | sed 's/\.git$//')
OWNER=$(echo "$OWNER_REPO" | cut -d/ -f1)
REPO=$(echo "$OWNER_REPO" | cut -d/ -f2)

# Validate required tools
for tool in gh jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Required tool not found: $tool"
        [ "$tool" = "gh" ] && echo "   Install from: https://cli.github.com"
        [ "$tool" = "jq" ] && echo "   Install from: https://jqlang.github.io/jq/"
        exit 1
    fi
done

echo "Repository: $OWNER/$REPO"
echo ""

# Confirm with user
read -p "This will create/update the 'protect-main' ruleset. Continue? (y/N) " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# Check if protect-main ruleset already exists
EXISTING_RULESETS=$(gh api "repos/$OWNER/$REPO/rulesets" 2>/dev/null || echo "[]")
EXISTING_ID=$(echo "$EXISTING_RULESETS" | jq -r '.[]? | select(.name == "protect-main") | .id' 2>/dev/null || echo "")

# Read ruleset from the checked-in JSON file (single source of truth)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RULESET_FILE="$REPO_ROOT/.github/rulesets/protect-main.json"

if [ ! -f "$RULESET_FILE" ]; then
    echo "ERROR: Ruleset file not found: $RULESET_FILE"
    exit 1
fi

RULESET_PAYLOAD=$(cat "$RULESET_FILE")

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
    echo "📝 Updating existing 'protect-main' ruleset (id: $EXISTING_ID)..."
    echo ""
    echo "$RULESET_PAYLOAD" | gh api \
      --method PUT \
      "repos/$OWNER/$REPO/rulesets/$EXISTING_ID" \
      --input - > /dev/null
else
    echo "📝 Creating 'protect-main' ruleset..."
    echo ""
    echo "$RULESET_PAYLOAD" | gh api \
      --method POST \
      "repos/$OWNER/$REPO/rulesets" \
      --input - > /dev/null
fi

echo "✅ Repository ruleset configured!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Ruleset 'protect-main' applied to default branch:"
echo "  ✅ Pull request required (1 approval)"
echo "  ✅ Dismiss stale reviews on new commits"
echo "  ✅ Code owner reviews required"
echo "  ✅ Require approval of most recent push"
echo "  ✅ Conversation resolution required"
echo "  ✅ Squash-only merge enforced"
echo "  ✅ Linear history required"
echo "  ✅ Force push blocked (non-fast-forward)"
echo "  ✅ Branch deletion blocked"
echo "  ✅ No bypass actors (enforced for all)"
echo ""
echo "🔍 Verify settings:"
echo "   $SCRIPT_DIR/validate-github-protection.sh"
echo ""
echo "🌐 Or view on GitHub:"
echo "   https://github.com/$OWNER/$REPO/settings/rules"
echo ""
