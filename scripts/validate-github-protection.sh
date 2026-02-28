#!/bin/bash
# Validate GitHub repository rulesets match CrossCheck requirements

set -e

echo "🔍 Validating GitHub repository rulesets for main..."
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

# Get all rulesets
RULESETS=$(gh api "repos/$OWNER/$REPO/rulesets" 2>&1) || true

# Check for API errors before parsing JSON
if echo "$RULESETS" | grep -qi "error connecting to"; then
    echo "❌ FAIL: Could not connect to GitHub API"
    echo "   $RULESETS"
    echo ""
    echo "   Check your internet connection or https://githubstatus.com"
    exit 1
fi

if echo "$RULESETS" | grep -qi "HTTP 401\|HTTP 403\|authentication"; then
    echo "❌ FAIL: GitHub API authentication failed"
    echo "   Run: gh auth login"
    exit 1
fi

if echo "$RULESETS" | grep -q "HTTP 404"; then
    echo "❌ FAIL: No repository rulesets found"
    echo ""
    echo "To fix, configure rulesets at: https://github.com/$OWNER/$REPO/settings/rules"
    exit 1
fi

# Validate JSON before parsing
if ! echo "$RULESETS" | jq empty 2>/dev/null; then
    echo "❌ FAIL: Invalid JSON response from GitHub API"
    echo "   Response: $RULESETS"
    exit 1
fi

# Find the protect-main ruleset
RULESET_ID=$(echo "$RULESETS" | jq -r '.[] | select(.name == "protect-main") | .id' 2>/dev/null || echo "")

if [ -z "$RULESET_ID" ] || [ "$RULESET_ID" = "null" ]; then
    echo "❌ FAIL: No 'protect-main' ruleset found"
    echo ""
    echo "Found rulesets:"
    RULESET_LIST=$(echo "$RULESETS" | jq -r '.[]? | "  - \(.name) (id: \(.id))"' 2>/dev/null || true)
    if [ -n "$RULESET_LIST" ]; then
        echo "$RULESET_LIST"
    else
        echo "  (none)"
    fi
    echo ""
    echo "To fix, create a 'protect-main' ruleset at: https://github.com/$OWNER/$REPO/settings/rules"
    exit 1
fi

# Get detailed ruleset configuration
RULESET=$(gh api "repos/$OWNER/$REPO/rulesets/$RULESET_ID" 2>&1) || true

# Check for API errors
if ! echo "$RULESET" | jq empty 2>/dev/null; then
    echo "❌ FAIL: Could not fetch ruleset details"
    echo "   Response: $RULESET"
    exit 1
fi

echo "✅ Found ruleset: protect-main (id: $RULESET_ID)"
echo ""

# Check each required setting
ISSUES=0

# Check: Ruleset is enabled
ENFORCEMENT=$(echo "$RULESET" | jq -r '.enforcement')
if [ "$ENFORCEMENT" = "active" ]; then
    echo "✅ Ruleset is active"
elif [ "$ENFORCEMENT" = "evaluate" ]; then
    echo "⚠️  WARNING: Ruleset in evaluation mode (not enforcing)"
    ISSUES=$((ISSUES + 1))
else
    echo "❌ FAIL: Ruleset is disabled"
    ISSUES=$((ISSUES + 1))
fi

# Check: Targets default branch
TARGET=$(echo "$RULESET" | jq -r '.target // empty')
INCLUDES_DEFAULT=$(echo "$RULESET" | jq -r '.conditions.ref_name.include[]? | select(. == "~DEFAULT_BRANCH")' 2>/dev/null || echo "")
if [ "$TARGET" = "branch" ] && [ -n "$INCLUDES_DEFAULT" ]; then
    echo "✅ Targets default branch (main)"
else
    echo "❌ FAIL: Does not target default branch"
    ISSUES=$((ISSUES + 1))
fi

# Extract rules
RULES=$(echo "$RULESET" | jq -r '.rules // []')

# Check: Branch deletion blocked
if echo "$RULES" | jq -e '.[]? | select(.type == "deletion")' >/dev/null 2>&1; then
    echo "✅ Branch deletion blocked"
else
    echo "❌ FAIL: Branch deletion not blocked"
    ISSUES=$((ISSUES + 1))
fi

# Check: Force push blocked (non_fast_forward rule)
if echo "$RULES" | jq -e '.[]? | select(.type == "non_fast_forward")' >/dev/null 2>&1; then
    echo "✅ Force push blocked (non-fast-forward required)"
else
    echo "❌ FAIL: Force push not blocked"
    ISSUES=$((ISSUES + 1))
fi

# Check: Linear history required
if echo "$RULES" | jq -e '.[]? | select(.type == "required_linear_history")' >/dev/null 2>&1; then
    echo "✅ Linear history required"
else
    echo "❌ FAIL: Linear history not required"
    ISSUES=$((ISSUES + 1))
fi

# Check: Pull request rule with all parameters
PR_RULE=$(echo "$RULES" | jq '.[]? | select(.type == "pull_request")' 2>/dev/null || echo "null")
if [ -n "$PR_RULE" ] && [ "$PR_RULE" != "null" ]; then
    echo "✅ Pull request required"

    # Check approvals
    REQUIRED_APPROVALS=$(echo "$PR_RULE" | jq -r '.parameters.required_approving_review_count // 0')
    if [ "$REQUIRED_APPROVALS" -ge 1 ]; then
        echo "✅ Required approvals: $REQUIRED_APPROVALS"
    else
        echo "⚠️  WARNING: No approvals required"
        ISSUES=$((ISSUES + 1))
    fi

    # Check dismiss stale reviews
    DISMISS_STALE=$(echo "$PR_RULE" | jq -r '.parameters.dismiss_stale_reviews_on_push // false')
    if [ "$DISMISS_STALE" = "true" ]; then
        echo "✅ Dismiss stale reviews on push"
    else
        echo "⚠️  WARNING: Stale reviews not dismissed"
        ISSUES=$((ISSUES + 1))
    fi

    # Check code owner review
    CODE_OWNER=$(echo "$PR_RULE" | jq -r '.parameters.require_code_owner_review // false')
    if [ "$CODE_OWNER" = "true" ]; then
        echo "✅ Code owner review required"
    else
        echo "⚠️  WARNING: Code owner review not required"
        ISSUES=$((ISSUES + 1))
    fi

    # Check last push approval
    LAST_PUSH=$(echo "$PR_RULE" | jq -r '.parameters.require_last_push_approval // false')
    if [ "$LAST_PUSH" = "true" ]; then
        echo "✅ Last push approval required"
    else
        echo "⚠️  WARNING: Last push approval not required"
        ISSUES=$((ISSUES + 1))
    fi

    # Check conversation resolution
    CONVERSATION=$(echo "$PR_RULE" | jq -r '.parameters.required_review_thread_resolution // false')
    if [ "$CONVERSATION" = "true" ]; then
        echo "✅ Conversation resolution required"
    else
        echo "⚠️  WARNING: Conversation resolution not required"
        ISSUES=$((ISSUES + 1))
    fi

    # Check allowed merge methods (squash only)
    MERGE_METHODS=$(echo "$PR_RULE" | jq -r '.parameters.allowed_merge_methods[]? // empty' 2>/dev/null || echo "")
    MERGE_COUNT=$(echo "$MERGE_METHODS" | grep -c . || echo "0")
    if [ "$MERGE_METHODS" = "squash" ] && [ "$MERGE_COUNT" -eq 1 ]; then
        echo "✅ Squash-only merge enforced"
    else
        echo "⚠️  WARNING: Multiple merge methods allowed: $MERGE_METHODS"
        ISSUES=$((ISSUES + 1))
    fi
else
    echo "❌ FAIL: Pull request rule not found"
    ISSUES=$((ISSUES + 1))
fi

# Check: No bypass actors
BYPASS_ACTORS=$(echo "$RULESET" | jq -r '.bypass_actors | length')
if [ "$BYPASS_ACTORS" -eq 0 ]; then
    echo "✅ No bypass actors (rules enforced for all)"
else
    echo "⚠️  WARNING: $BYPASS_ACTORS bypass actor(s) configured"
    ISSUES=$((ISSUES + 1))
fi

# Check: Local settings have critical deny rules
echo ""
echo "📋 Checking local settings deny rules..."

CRITICAL_DENY_RULES=(
    'Bash(gh*--admin*)'
    'Bash(*--admin*)'
    'Bash(gh api*rulesets*)'
    'Bash(gh api*branches/*/protection*)'
    'Bash(*graphql*BranchProtection*)'
    'Bash(*graphql*Ruleset*)'
)

for SETTINGS_FILE in "$HOME/.claude/settings.json" "$HOME/.codex/settings.json"; do
    [ -f "$SETTINGS_FILE" ] || continue
    SETTINGS_NAME=$(basename "$(dirname "$SETTINGS_FILE")")/$(basename "$SETTINGS_FILE")

    for rule in "${CRITICAL_DENY_RULES[@]}"; do
        if jq -e --arg r "$rule" '.permissions.deny | index($r)' "$SETTINGS_FILE" >/dev/null 2>&1; then
            echo "✅ $SETTINGS_NAME denies: $rule"
        else
            echo "❌ FAIL: $SETTINGS_NAME missing deny rule: $rule"
            echo "   Run /update-crosscheck to sync critical deny rules"
            ISSUES=$((ISSUES + 1))
        fi
    done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ISSUES" -eq 0 ]; then
    echo "✅ All ruleset settings validated!"
    echo ""
    echo "Your main branch is properly protected according to CrossCheck standards."
    echo ""
    echo "Ruleset details:"
    echo "  Name: protect-main"
    echo "  ID: $RULESET_ID"
    echo "  Enforcement: $ENFORCEMENT"
    echo "  View: https://github.com/$OWNER/$REPO/rules/$RULESET_ID"
    exit 0
else
    echo "⚠️  Found $ISSUES issue(s) with repository rulesets"
    echo ""
    echo "To fix, update ruleset at: https://github.com/$OWNER/$REPO/rules/$RULESET_ID"
    exit 1
fi
