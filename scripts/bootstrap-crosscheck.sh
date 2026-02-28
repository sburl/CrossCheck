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

if [ -n "$SCRIPT_DIR" ] && { [ -f "$SCRIPT_DIR/codex/CODEX.md" ] || [ -f "$SCRIPT_DIR/CLAUDE.md" ]; }; then
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

# Migrate from old ~/.claude/CrossCheck location (prevents duplicate skills)
OLD_LOCATION="$HOME/.claude/CrossCheck"
if [ "$INSTALL_MODE" = "traditional" ] && [ -e "$OLD_LOCATION" ]; then
    echo "⚠️  Found old installation at ~/.claude/CrossCheck"
    echo "   This location causes duplicate skills (Claude Code scans ~/.claude/)"
    if [ -L "$OLD_LOCATION" ]; then
        echo "   Removing symlink..."
        unlink "$OLD_LOCATION"
        echo "   ✅ Symlink removed"
    elif [ -d "$OLD_LOCATION" ] && [ ! -d "$CROSSCHECK_DIR" ]; then
        echo "   Moving to ~/.crosscheck/..."
        mv "$OLD_LOCATION" "$CROSSCHECK_DIR"
        echo "   ✅ Moved to ~/.crosscheck/"
    elif [ -d "$OLD_LOCATION" ] && [ -d "$CROSSCHECK_DIR" ]; then
        echo "   ℹ️  Both locations exist. Please remove ~/.claude/CrossCheck manually:"
        echo "      rm -rf ~/.claude/CrossCheck"
    fi
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
    echo "📝 Step 2: Sync CLAUDE.md to global location..."

    # Symlink global CLAUDE.md to CrossCheck source — updates instantly on git pull.
    # Personal overrides belong in CLAUDE.local.md (never touched by CrossCheck).
    [ -e "$PROJECTS_DIR/CLAUDE.md" ] || [ -L "$PROJECTS_DIR/CLAUDE.md" ] && rm "$PROJECTS_DIR/CLAUDE.md"
    ln -sf "$CROSSCHECK_DIR/CLAUDE.md" "$PROJECTS_DIR/CLAUDE.md"
    echo "   ✅ Symlinked CLAUDE.md → CrossCheck/CLAUDE.md"
    echo "   💡 Updates instantly on git pull in CrossCheck"
    echo "   💡 Personal overrides → CLAUDE.local.md"
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

    # Sync critical deny rules even when settings exist
    echo "   Checking critical deny rules..."
    CRITICAL_DENY_RULES=(
        'Bash(gh*--admin*)'
        'Bash(*--admin*)'
        'Bash(gh api*rulesets*)'
        'Bash(gh api*branches/*/protection*)'
        'Bash(*graphql*BranchProtection*)'
        'Bash(*graphql*Ruleset*)'
    )

    DENY_UPDATED=0
    DENY_FAILED=0
    for rule in "${CRITICAL_DENY_RULES[@]}"; do
        if ! jq -e --arg r "$rule" '.permissions.deny | index($r)' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
            if jq --arg r "$rule" '.permissions.deny += [$r]' "$HOME/.claude/settings.json" > "$HOME/.claude/settings.json.tmp" \
                && mv "$HOME/.claude/settings.json.tmp" "$HOME/.claude/settings.json"; then
                echo "   + Added critical deny rule: $rule"
                DENY_UPDATED=$((DENY_UPDATED + 1))
            else
                echo "   ⚠️  Failed to add deny rule: $rule (jq or write error)"
                DENY_FAILED=$((DENY_FAILED + 1))
            fi
        fi
    done

    if [ "$DENY_FAILED" -gt 0 ]; then
        echo "   ⚠️  $DENY_FAILED deny rule(s) failed to sync — check settings.json is valid JSON"
    elif [ "$DENY_UPDATED" -eq 0 ]; then
        echo "   ✅ All critical deny rules present"
    else
        echo "   ✅ Added $DENY_UPDATED critical security rule(s)"
    fi
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

# 5. Install skills (commands) via symlinks
echo "📝 Step 5: Install skills..."
mkdir -p "$HOME/.claude/commands"
SKIP_FILE="$HOME/.crosscheck/skip-skills"
if [ -f "$SKIP_FILE" ]; then
    SKIP_DISPLAY=$(sed 's/#.*//' "$SKIP_FILE" | xargs)
    [ -n "$SKIP_DISPLAY" ] && echo "   Skipping (per ~/.crosscheck/skip-skills): $SKIP_DISPLAY"
fi
LINKED=0
for skill_file in "$CROSSCHECK_DIR/skill-sources/"*.md; do
    skill_name="$(basename "$skill_file" .md)"
    [ "$skill_name" = "INSTALL" ] && continue
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    for TARGET_DIR in "$HOME/.claude/commands" "$HOME/.codex/commands"; do
        [ -d "$TARGET_DIR" ] || continue
        target="$TARGET_DIR/$skill_name.md"
        [ -e "$target" ] || [ -L "$target" ] && rm "$target"
        ln -sf "$skill_file" "$target"
        LINKED=$((LINKED + 1))
    done
done
echo "   ✅ Linked $LINKED skill(s) via symlinks"
echo "   💡 Skills update instantly on git pull in CrossCheck — no re-run needed"
echo ""

# 6. Install TokenPrint (optional - for /ai-usage skill)
echo "📊 Step 6: Install TokenPrint (for /ai-usage dashboard)..."

if [ "$INSTALL_MODE" = "multi-project" ]; then
    TOKENPRINT_DIR="$PROJECTS_DIR/TokenPrint"
else
    TOKENPRINT_DIR="$HOME/.tokenprint"
fi

if [ -d "$TOKENPRINT_DIR" ] && [ -f "$TOKENPRINT_DIR/tokenprint.py" ]; then
    echo "   ✅ TokenPrint already installed at $TOKENPRINT_DIR"
else
    # Clean up partial clone (dir exists but no tokenprint.py)
    if [ -d "$TOKENPRINT_DIR" ] && [ ! -f "$TOKENPRINT_DIR/tokenprint.py" ]; then
        echo "   ⚠️  Found incomplete TokenPrint at $TOKENPRINT_DIR, removing..."
        rm -rf "$TOKENPRINT_DIR"
    fi
    read -p "   Install TokenPrint (AI usage dashboard)? (Y/n) " -n 1 -r < /dev/tty
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "   Cloning TokenPrint..."
        if git clone --branch main --single-branch https://github.com/sburl/TokenPrint.git "$TOKENPRINT_DIR"; then
            echo "   ✅ TokenPrint installed at $TOKENPRINT_DIR"
        else
            echo "   ⚠️  TokenPrint clone failed (network issue?). /ai-usage requires TokenPrint."
            echo "      Install later: git clone https://github.com/sburl/TokenPrint.git $TOKENPRINT_DIR"
        fi
    else
        echo "   Skipped TokenPrint (/ai-usage will prompt to install when used)"
    fi
fi
echo ""

# 7. Install agents via symlinks
echo "📝 Step 7: Install agents..."
if [ -d "$CROSSCHECK_DIR/agents" ]; then
    AGENT_LINKED=0
    for TARGET_DIR in "$HOME/.claude/agents" "$HOME/.codex/agents"; do
        mkdir -p "$TARGET_DIR" 2>/dev/null || continue
        for agent_path in "$CROSSCHECK_DIR/agents/"*; do
            [ -e "$agent_path" ] || continue
            agent_name="$(basename "$agent_path")"
            target="$TARGET_DIR/$agent_name"
            rm -rf "$target"
            ln -sf "$agent_path" "$target"
            AGENT_LINKED=$((AGENT_LINKED + 1))
        done
    done
    echo "   ✅ Linked $AGENT_LINKED agent(s) via symlinks"
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
echo "   • Skills symlinked at ~/.claude/commands/ (live from CrossCheck)"
echo "   • Git hooks for quality gates (if accepted)"
echo "   • Codex review hooks (if accepted)"
if [ -d "$TOKENPRINT_DIR" ] && [ -f "$TOKENPRINT_DIR/tokenprint.py" ]; then
    echo "   • TokenPrint dashboard at $TOKENPRINT_DIR"
fi
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
