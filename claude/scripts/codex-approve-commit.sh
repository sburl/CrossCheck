#!/bin/bash
# Helper script: Prepare commit for Codex approval
# Usage: ./codex-approve-commit.sh

echo "🔍 Preparing commit summary for Codex review..."
echo ""

# Get current branch
branch=$(git branch --show-current)

# Get staged changes summary
staged_files=$(git diff --cached --name-only | head -10)
file_count=$(git diff --cached --name-only | wc -l | tr -d ' ')

# Get diff stats
diff_stats=$(git diff --cached --stat)

# Create review prompt
prompt="Quick commit review before pushing to $branch

Staged files ($file_count total, showing first 10):
$staged_files

Changes:
$diff_stats

Please review for:
1. Code quality and correctness
2. Security issues (OWASP Top 10)
3. Test coverage adequacy
4. Breaking changes not documented

If approved, respond with 'APPROVED' and I'll commit with 'Codex Approved' in the message.
If changes needed, specify what to fix."

# Save to temp file (no .txt suffix — macOS mktemp only randomizes trailing X's)
temp_file=$(mktemp "${TMPDIR:-/tmp}/codex-review-XXXXXXXX")
echo "$prompt" > "$temp_file"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Codex Review Prompt (copied to clipboard):"
echo ""
echo "$prompt"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Paste this prompt to Codex (via Claude Code terminal)"
echo "  2. Wait for Codex approval"
echo "  3. If approved, commit with:"
echo ""
echo "     git commit -m \"feat: your description"
echo ""
echo "     Codex Approved\""
echo ""
echo "Prompt saved to: $temp_file"
echo ""

# Copy to clipboard if possible
if command -v pbcopy &> /dev/null; then
    echo "$prompt" | pbcopy
    echo "✅ Copied to clipboard (macOS)"
elif command -v xclip &> /dev/null; then
    echo "$prompt" | xclip -selection clipboard
    echo "✅ Copied to clipboard (Linux)"
elif command -v clip.exe &> /dev/null; then
    echo "$prompt" | clip.exe
    echo "✅ Copied to clipboard (Windows/WSL)"
else
    echo "ℹ️  Install pbcopy/xclip/clip.exe for auto-clipboard"
fi

echo ""
