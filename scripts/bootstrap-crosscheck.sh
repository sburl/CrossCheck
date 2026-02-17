#!/bin/bash
# CrossCheck Bootstrap - One command to set up everything
# Usage:
#   Method 1 (Multi-project): cd CrossCheck && ./scripts/bootstrap-crosscheck.sh
#   Method 2 (Traditional): curl -fsSL https://raw.githubusercontent.com/sburl/CrossCheck/main/scripts/bootstrap-crosscheck.sh | bash

set -e

echo "🚀 CrossCheck Bootstrap"
echo "=================="
echo ""

# Detect installation context
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/CLAUDE.md" ]; then
    # Running from cloned repo - multi-project mode
    INSTALL_MODE="multi-project"
    CROSSCHECK_DIR="$SCRIPT_DIR"
    PROJECTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    echo "📍 Multi-project mode detected"
    echo "   CrossCheck: $CROSSCHECK_DIR"
    echo "   Projects folder: $PROJECTS_DIR"
    echo ""
else
    # Running via curl or outside repo - traditional mode
    INSTALL_MODE="traditional"
    CROSSCHECK_DIR="$HOME/.crosscheck"
    echo "📍 Traditional mode (installing to ~/.crosscheck)"
    echo ""
fi

# 1. Clone/update CrossCheck repo (traditional mode only)
if [ "$INSTALL_MODE" = "traditional" ]; then
    echo "📦 Step 1: Install CrossCheck workflow..."
    if [ -d "$CROSSCHECK_DIR" ]; then
        echo "   Found existing installation, updating..."
        cd "$CROSSCHECK_DIR"
        git checkout main && git pull origin main
    else
        echo "   Cloning CrossCheck repository..."
        mkdir -p "$(dirname "$CROSSCHECK_DIR")"
        git clone https://github.com/sburl/CrossCheck.git "$CROSSCHECK_DIR"
    fi
    echo "   ✅ CrossCheck installed at ~/.crosscheck"
    echo ""
else
    echo "📦 Step 1: Using local CrossCheck repository"
    echo "   ✅ Already at $CROSSCHECK_DIR"
    echo ""
fi

# 2. Copy full CLAUDE.md to global location (multi-project mode only)
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "📝 Step 2: Copy CLAUDE.md to global location..."

    # Copy full CLAUDE.md to projects folder
    if [ ! -f "$PROJECTS_DIR/CLAUDE.md" ]; then
        cp "$CROSSCHECK_DIR/CLAUDE.md" "$PROJECTS_DIR/CLAUDE.md"
        echo "   ✅ Copied CLAUDE.md to $PROJECTS_DIR/CLAUDE.md"
        echo "   📖 Full workflow available globally"
        echo "   📚 Supporting docs in CrossCheck/ (QUICK-REFERENCE.md, rules/, skill-sources/)"
    else
        echo "   ℹ️  Global CLAUDE.md already exists"
        echo "   💡 To update: cp $CROSSCHECK_DIR/CLAUDE.md $PROJECTS_DIR/CLAUDE.md"
    fi
    echo ""
fi

# 3. Copy settings template if needed
echo "📝 Step 3: Configure settings..."
if [ ! -f "$HOME/.claude/settings.json" ]; then
    echo "   Creating ~/.claude/settings.json from template..."
    mkdir -p "$HOME/.claude"  # Ensure directory exists
    cp "$CROSSCHECK_DIR/settings.template.json" "$HOME/.claude/settings.json"
    echo "   ⚠️  TODO: Edit ~/.claude/settings.json to customize for your stack"
    echo "      Remove Spencer's commands (codex*, dailybrief*) and add yours"
else
    echo "   ✅ Settings already exist at ~/.claude/settings.json"
fi
echo ""

# 4. Install all hooks
echo "🎣 Step 4: Install automation hooks..."

read -p "   Install git hooks globally (all repos)? (Y/n) " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    "$CROSSCHECK_DIR/scripts/install-git-hooks.sh" --global
else
    echo "   Skipped global git hooks (you can install per-repo later)"
fi

read -p "   Install Codex review hooks globally? (Y/n) " -n 1 -r < /dev/tty
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    "$CROSSCHECK_DIR/scripts/install-codex-hooks.sh" --global
else
    echo "   Skipped Codex review hooks"
fi

# 5. Install skills (commands)
echo "📝 Step 5: Install skills..."
mkdir -p "$HOME/.claude/commands"
cp "$CROSSCHECK_DIR/skill-sources/"*.md "$HOME/.claude/commands/"
skill_count=$(ls "$HOME/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
echo "   ✅ Installed $skill_count skills to ~/.claude/commands/"
echo ""

# 6. Install agents (optional)
echo "📝 Step 6: Install agents..."
if [ -d "$CROSSCHECK_DIR/agents" ]; then
    mkdir -p "$HOME/.claude/agents"
    if cp -r "$CROSSCHECK_DIR/agents/"* "$HOME/.claude/agents/" 2>/dev/null; then
        agent_count=$(ls "$HOME/.claude/agents/" 2>/dev/null | wc -l | tr -d ' ')
        echo "   ✅ Installed $agent_count agents to ~/.claude/agents/"
    else
        echo "   ⚠️  Failed to copy agents (check permissions)"
    fi
else
    echo "   ⚠️  No agents directory found in $CROSSCHECK_DIR"
fi

echo ""
echo "✅ CrossCheck Bootstrap Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 What was installed:"
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   • CrossCheck workflow at $CROSSCHECK_DIR"
    echo "   • Global CLAUDE.md at $PROJECTS_DIR/CLAUDE.md"
else
    echo "   • CrossCheck workflow at ~/.crosscheck/"
fi
echo "   • Global settings at ~/.claude/settings.json"
echo "   • Skills at ~/.claude/commands/"
echo "   • Git hooks for quality gates (if accepted)"
echo "   • Codex review hooks (if accepted)"
echo ""
echo "🎯 Next steps:"
echo ""
echo "   1. Start Claude Code in any repo:"
echo "      cd ~/your-project"
echo "      claude"
echo ""
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   2. Claude will automatically load CLAUDE.md workflow"
    echo "      from $PROJECTS_DIR/CLAUDE.md (full workflow)"
    echo "      Supporting docs: $CROSSCHECK_DIR/QUICK-REFERENCE.md, docs/rules/"
else
    echo "   2. Claude will automatically load CLAUDE.md workflow"
    echo "      from ~/.crosscheck/"
fi
echo ""
echo "   3. Set up a repo for autonomous work:"
echo "      claude '/setup-automation'"
echo "      This creates: garbage/, do-work/, user-content/"
echo ""
echo "   4. Optional customization:"
echo "      • Edit: ~/.claude/settings.json (customize for your stack)"
echo "      • Copy: CLAUDE.local.md.template → CLAUDE.local.md (personal prefs)"
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "      • Docs: $CROSSCHECK_DIR/README.md"
else
    echo "      • Docs: ~/.crosscheck/README.md"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚀 Ready to code with CrossCheck!"
echo ""
