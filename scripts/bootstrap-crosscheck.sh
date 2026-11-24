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

if [ -n "$SCRIPT_DIR" ] && { [ -f "$SCRIPT_DIR/codex/CODEX.md" ] || [ -f "$SCRIPT_DIR/gemini/GEMINI.md" ] || [ -f "$SCRIPT_DIR/CLAUDE.md" ]; }; then
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

# 2. Sync core workflow files to global location (multi-project mode only)
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "📝 Step 2: Sync workflow files to global location..."

    # Symlink core workflows to CrossCheck source — updates instantly on git pull.
    # Personal overrides belong in *.local.md (never touched by CrossCheck).
    for file in "CLAUDE.md" "CODEX.md" "GEMINI.md"; do
        if [ -f "$CROSSCHECK_DIR/$file" ]; then
            [ -e "$PROJECTS_DIR/$file" ] || [ -L "$PROJECTS_DIR/$file" ] && rm "$PROJECTS_DIR/$file"
            ln -sf "$CROSSCHECK_DIR/$file" "$PROJECTS_DIR/$file"
            echo "   ✅ Symlinked $file → CrossCheck/$file"
        fi
    done
    echo "   💡 Updates instantly on git pull in CrossCheck"
    echo "   💡 Personal overrides → *.local.md"
    echo ""
fi

# 3. Copy settings template if needed
SUPPLY_CHAIN_INSTALLER="$CROSSCHECK_DIR/claude/scripts/install-supply-chain-hook.sh"
SUPPLY_CHAIN_HOOK="$CROSSCHECK_DIR/claude/scripts/preuse-supply-chain-gate.sh"
if [ ! -x "$SUPPLY_CHAIN_INSTALLER" ] || [ ! -x "$SUPPLY_CHAIN_HOOK" ]; then
    echo "❌ Claude supply-chain hook installer or gate is missing under $CROSSCHECK_DIR/claude/scripts" >&2
    exit 1
fi

echo "📝 Step 3: Configure settings..."
SETTINGS_FILE="$HOME/.claude/settings.json"
PENDING_SETTINGS_FILE=""
if [ -e "$SETTINGS_FILE" ] || [ -L "$SETTINGS_FILE" ]; then
    echo "   ✅ Settings already exist at ~/.claude/settings.json"
    SETTINGS_TO_INSTALL="$SETTINGS_FILE"
else
    echo "   Preparing settings.json from the template..."
    PENDING_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/crosscheck-claude-settings.XXXXXX")"
    python3 "$CROSSCHECK_DIR/scripts/atomic-publish-file.py" private-file "$PENDING_SETTINGS_FILE"
    cp "$CROSSCHECK_DIR/settings.template.json" "$PENDING_SETTINGS_FILE"
    SETTINGS_TO_INSTALL="$PENDING_SETTINGS_FILE"
fi
echo ""

# Atomically synchronize critical deny rules and install the native Claude Bash
# gate. A missing settings file is created only after its temporary copy has
# passed validation and received the complete update.
if ! "$SUPPLY_CHAIN_INSTALLER" "$SETTINGS_TO_INSTALL" "$SUPPLY_CHAIN_HOOK"; then
    [ -z "$PENDING_SETTINGS_FILE" ] || rm -f "$PENDING_SETTINGS_FILE"
    exit 1
fi
if [ -n "$PENDING_SETTINGS_FILE" ]; then
    PUBLISH_HELPER="$CROSSCHECK_DIR/scripts/atomic-publish-file.py"
    if python3 "$PUBLISH_HELPER" publish "$HOME" ".claude/settings.json" --absent "$PENDING_SETTINGS_FILE"; then
        rm -f "$PENDING_SETTINGS_FILE"
    else
        PUBLISH_STATUS=$?
        rm -f "$PENDING_SETTINGS_FILE"
        if [ "$PUBLISH_STATUS" -eq 3 ] && [ -f "$SETTINGS_FILE" ]; then
            echo "Settings appeared during setup; updating the existing file safely"
            "$SUPPLY_CHAIN_INSTALLER" "$SETTINGS_FILE" "$SUPPLY_CHAIN_HOOK"
        else
            echo "Could not safely publish prepared settings at $SETTINGS_FILE" >&2
            exit 1
        fi
    fi
fi
echo "   ✅ Claude supply-chain hook points to $SUPPLY_CHAIN_HOOK"
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
    for TARGET_DIR in "$HOME/.codex/commands" "$HOME/.gemini/agents"; do
        [ -d "$(dirname "$TARGET_DIR")" ] || mkdir -p "$(dirname "$TARGET_DIR")" 2>/dev/null
        [ -d "$TARGET_DIR" ] || mkdir -p "$TARGET_DIR" 2>/dev/null
        target="$TARGET_DIR/$skill_name.md"
        [ -e "$target" ] || [ -L "$target" ] && rm "$target"
        ln -sf "$skill_file" "$target"
        LINKED=$((LINKED + 1))
    done
done
echo "   ✅ Linked $LINKED skill(s) via symlinks"
echo "   💡 Skills update instantly on git pull in CrossCheck — no re-run needed"
echo ""

# Claude commands use the maintained Claude mirror and preserve user-owned files.
"$CROSSCHECK_DIR/claude/scripts/sync-managed-claude-skills.sh" "$CROSSCHECK_DIR" "$HOME"

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
    for TARGET_DIR in "$HOME/.claude/agents" "$HOME/.codex/agents" "$HOME/.gemini/agents"; do
        [ -d "$(dirname "$TARGET_DIR")" ] || mkdir -p "$(dirname "$TARGET_DIR")" 2>/dev/null
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

# 8. Setup Gemini telemetry
echo "📊 Step 8: Configure Gemini telemetry..."
if [ -f "$CROSSCHECK_DIR/scripts/setup-gemini-telemetry.sh" ]; then
    "$CROSSCHECK_DIR/scripts/setup-gemini-telemetry.sh"
else
    echo "   ⚠️  Gemini telemetry setup script not found"
fi

echo ""
echo "✅ CrossCheck Bootstrap Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 What was installed:"
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   • CrossCheck workflow at $CROSSCHECK_DIR"
    echo "   • Global CLAUDE.md, CODEX.md, and GEMINI.md at $PROJECTS_DIR/"
else
    echo "   • CrossCheck workflow at ~/.crosscheck/"
fi
echo "   • Global settings at ~/.claude/settings.json"
echo "   • Skills symlinked at ~/.claude/commands/ and ~/.gemini/agents/"
echo "   • Git hooks for quality gates (if accepted)"
echo "   • Codex review hooks (if accepted)"
if [ -d "$TOKENPRINT_DIR" ] && [ -f "$TOKENPRINT_DIR/tokenprint.py" ]; then
    echo "   • TokenPrint dashboard at $TOKENPRINT_DIR"
fi
echo ""
echo "🎯 Next steps:"
echo ""
echo "   1. Start Gemini CLI in any repo:"
echo "      cd ~/your-project"
echo "      gemini"
echo ""
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   2. Gemini will automatically load GEMINI.md workflow"
    echo "      from $PROJECTS_DIR/GEMINI.md (full workflow)"
    echo "      Supporting docs: $CROSSCHECK_DIR/QUICK-REFERENCE.md, docs/rules/"
else
    echo "   2. Gemini will automatically load GEMINI.md workflow"
    echo "      from ~/.crosscheck/"
fi
echo ""
echo "   3. Set up a repo for autonomous work:"
echo "      gemini '/setup-automation'"
echo "      This creates: garbage/, do-work/, user-content/"
echo ""
echo "   4. Optional customization:"
echo "      • Edit: ~/.gemini/settings.json (customize for your stack)"
echo "      • Copy: GEMINI.local.md.template → GEMINI.local.md (personal prefs)"
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
