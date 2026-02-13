#!/bin/bash
# CrossCheck Bootstrap - One command to set up everything
# Usage: curl -fsSL https://raw.githubusercontent.com/sburl/CrossCheck/main/scripts/bootstrap-crosscheck.sh | bash

set -e

echo "🚀 CrossCheck Bootstrap"
echo "=================="
echo ""

# 1. Clone/update CrossCheck repo
echo "📦 Step 1: Install CrossCheck workflow..."
if [ -d "$HOME/.claude/CrossCheck" ]; then
    echo "   Found existing installation, updating..."
    cd "$HOME/.claude/CrossCheck"
    git checkout main && git pull origin main
else
    echo "   Cloning CrossCheck repository..."
    mkdir -p "$HOME/.claude"
    git clone https://github.com/sburl/CrossCheck.git "$HOME/.claude/CrossCheck"
fi
echo "   ✅ CrossCheck installed at ~/.claude/CrossCheck"
echo ""

# 2. Copy settings template if needed
echo "📝 Step 2: Configure settings..."
if [ ! -f "$HOME/.claude/settings.json" ]; then
    echo "   Creating ~/.claude/settings.json from template..."
    cp "$HOME/.claude/CrossCheck/settings.template.json" "$HOME/.claude/settings.json"
    echo "   ⚠️  TODO: Edit ~/.claude/settings.json to customize for your stack"
    echo "      Remove Spencer's commands (codex*, dailybrief*) and add yours"
else
    echo "   ✅ Settings already exist at ~/.claude/settings.json"
fi
echo ""

# 3. Install all hooks
echo "🎣 Step 3: Install automation hooks..."

read -p "   Install git hooks globally (all repos)? (Y/n) " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    "$HOME/.claude/CrossCheck/scripts/install-git-hooks.sh" --global
else
    echo "   Skipped global git hooks (you can install per-repo later)"
fi

read -p "   Install Codex review hooks globally? (Y/n) " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    "$HOME/.claude/CrossCheck/scripts/install-codex-hooks.sh" --global
else
    echo "   Skipped Codex review hooks"
fi

echo ""
echo "✅ CrossCheck Bootstrap Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 What was installed:"
echo "   • CrossCheck workflow at ~/.claude/CrossCheck/"
echo "   • Global settings at ~/.claude/settings.json"
echo "   • Git hooks for quality gates (if accepted)"
echo "   • Codex review hooks (if accepted)"
echo ""
echo "🎯 Next steps:"
echo ""
echo "   1. Start Claude Code in any repo:"
echo "      cd ~/your-project"
echo "      claude"
echo ""
echo "   2. Claude will automatically load CLAUDE.md workflow"
echo "      from ~/.claude/CrossCheck/"
echo ""
echo "   3. Set up a repo for autonomous work:"
echo "      claude '/setup-automation'"
echo "      This creates: garbage/, do-work/, user-content/"
echo ""
echo "   4. Optional customization:"
echo "      • Edit: ~/.claude/settings.json (customize for your stack)"
echo "      • Copy: CLAUDE.local.md.template → CLAUDE.local.md (personal prefs)"
echo "      • Docs: ~/.claude/CrossCheck/README.md"
echo "      • Setup: ~/.claude/CrossCheck/README.md#detailed-setup"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Ready to code with CrossCheck!"
echo ""
