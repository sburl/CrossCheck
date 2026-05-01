#!/bin/bash
# CrossCheck Bootstrap - One command to set up everything
# Usage:
#   Method 1 (Multi-project): cd CrossCheck && ./scripts/bootstrap-crosscheck.sh
#   Method 2 (Traditional): curl -fsSL https://raw.githubusercontent.com/sburl/CrossCheck/main/scripts/bootstrap-crosscheck.sh | bash

set -e

echo "🚀 CrossCheck Bootstrap"
echo "=================="
echo ""

# Prompt helper: default yes, robust against newline carry-over
prompt_yes_default() {
    local prompt="$1"
    local answer
    while true; do
        read -r -p "$prompt" answer < /dev/tty
        if [ -z "$answer" ]; then
            return 0
        fi
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "   Please answer y or n." ;;
        esac
    done
}

# Detect installation context
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/CODEX.md" ]; then
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

# Migrate from legacy Claude-era ~/.claude/CrossCheck location
OLD_LOCATION="$HOME/.claude/CrossCheck"
if [ "$INSTALL_MODE" = "traditional" ] && [ -e "$OLD_LOCATION" ]; then
    echo "⚠️  Found old installation at ~/.claude/CrossCheck"
    echo "   This is a legacy Claude location; moving to ~/.crosscheck for Codex workflow"
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

# 2. Copy full CODEX.md to global location (multi-project mode only)
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "📝 Step 2: Copy CODEX.md to global location..."

    # Copy full CODEX.md to projects folder
    if [ ! -f "$PROJECTS_DIR/CODEX.md" ]; then
        cp "$CROSSCHECK_DIR/CODEX.md" "$PROJECTS_DIR/CODEX.md"
        echo "   ✅ Copied CODEX.md to $PROJECTS_DIR/CODEX.md"
        echo "   📖 Full workflow available globally"
        echo "   📚 Supporting docs in CrossCheck/ (QUICK-REFERENCE.md, rules/, skills/)"
    else
        echo "   ℹ️  Global CODEX.md already exists"
        echo "   💡 To update: cp $CROSSCHECK_DIR/CODEX.md $PROJECTS_DIR/CODEX.md"
    fi
    echo ""
fi

# 3. Copy settings template if needed
echo "📝 Step 3: Configure settings..."
if [ ! -f "$HOME/.codex/settings.json" ]; then
    echo "   Creating ~/.codex/settings.json from template..."
    mkdir -p "$HOME/.codex"  # Ensure directory exists
    cp "$CROSSCHECK_DIR/settings.template.json" "$HOME/.codex/settings.json"
    echo "   ⚠️  TODO: Edit ~/.codex/settings.json to customize for your stack"
    echo "      Remove Spencer's commands (codex*, dailybrief*) and add yours"
else
    echo "   ✅ Settings already exist at ~/.codex/settings.json"

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
        if ! jq -e --arg r "$rule" '.permissions.deny | index($r)' "$HOME/.codex/settings.json" >/dev/null 2>&1; then
            if jq --arg r "$rule" '.permissions.deny += [$r]' "$HOME/.codex/settings.json" > "$HOME/.codex/settings.json.tmp" \
                && mv "$HOME/.codex/settings.json.tmp" "$HOME/.codex/settings.json"; then
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

if prompt_yes_default "   Install git hooks globally (all repos)? (Y/n) "; then
    "$CROSSCHECK_DIR/scripts/install-git-hooks.sh" --global
else
    echo "   Skipped global git hooks (you can install per-repo later)"
fi

if prompt_yes_default "   Install Codex review hooks globally? (Y/n) "; then
    "$CROSSCHECK_DIR/scripts/install-codex-hooks.sh" --global
else
    echo "   Skipped Codex review hooks"
fi

# 5. Install skills (Codex format)
echo "📝 Step 5: Install skills..."
mkdir -p "$HOME/.codex/skills"
# Load skip list (one skill name per line, e.g. "ai-usage")
SKIP_FILE="$HOME/.crosscheck/skip-skills"
if [ -f "$SKIP_FILE" ]; then
    # Strip comments and blank lines for display
    SKIP_DISPLAY=$(sed 's/#.*//' "$SKIP_FILE" | xargs)
    [ -n "$SKIP_DISPLAY" ] && echo "   Skipping (per ~/.crosscheck/skip-skills): $SKIP_DISPLAY"
fi
# Copy skill folders from skills/<name>/SKILL.md
for skill_dir in "$CROSSCHECK_DIR/skills/"*; do
    [ -d "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name="$(basename "$skill_dir")"
    if [ -f "$SKIP_FILE" ] && grep -qx "$skill_name" "$SKIP_FILE" 2>/dev/null; then
        continue
    fi
    mkdir -p "$HOME/.codex/skills/$skill_name"
    cp -R "$skill_dir/." "$HOME/.codex/skills/$skill_name/"
done
skill_count=$(find "$HOME/.codex/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
echo "   ✅ Installed $skill_count skills to ~/.codex/skills/"
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
    if prompt_yes_default "   Install TokenPrint (AI usage dashboard)? (Y/n) "; then
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

# 7. Install agents (optional)
echo "📝 Step 7: Install agents..."
if [ -d "$CROSSCHECK_DIR/agents" ]; then
    mkdir -p "$HOME/.codex/agents"
    if cp -r "$CROSSCHECK_DIR/agents/"* "$HOME/.codex/agents/" 2>/dev/null; then
        agent_count=$(ls "$HOME/.codex/agents/" 2>/dev/null | wc -l | tr -d ' ')
        echo "   ✅ Installed $agent_count agents to ~/.codex/agents/"
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
    echo "   • Global CODEX.md at $PROJECTS_DIR/CODEX.md"
else
    echo "   • CrossCheck workflow at ~/.crosscheck/"
fi
echo "   • Global settings at ~/.codex/settings.json"
echo "   • Skills at ~/.codex/skills/"
echo "   • Git hooks for quality gates (if accepted)"
echo "   • Codex review hooks (if accepted)"
if [ -d "$TOKENPRINT_DIR" ] && [ -f "$TOKENPRINT_DIR/tokenprint.py" ]; then
    echo "   • TokenPrint dashboard at $TOKENPRINT_DIR"
fi
echo ""
echo "🎯 Next steps:"
echo ""
echo "   1. Start Codex in any repo:"
echo "      cd ~/your-project"
echo "      codex"
echo ""
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   2. Codex will automatically load CODEX.md workflow"
    echo "      from $PROJECTS_DIR/CODEX.md (full workflow)"
    echo "      Supporting docs: $CROSSCHECK_DIR/QUICK-REFERENCE.md, docs/rules/"
else
    echo "   2. Codex will automatically load CODEX.md workflow"
    echo "      from ~/.crosscheck/"
fi
echo ""
echo "   3. Set up a repo for autonomous work:"
echo "      codex '/setup-automation'"
echo "      This creates: garbage/, do-work/, user-content/"
echo ""
echo "   4. Optional customization:"
echo "      • Edit: ~/.codex/settings.json (customize for your stack)"
echo "      • Copy: CODEX.local.md.template → CODEX.local.md (personal prefs)"
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
