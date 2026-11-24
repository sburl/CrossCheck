#!/bin/bash
# CrossCheck Bootstrap - One command to set up everything
# Usage:
#   Multi-project: cd CrossCheck && ./codex/scripts/bootstrap-crosscheck.sh

set -e

CODEX_AGENTS_TEMP_DIR=""
SETTINGS_STAGE=""
cleanup_bootstrap_stages() {
    [ -z "$CODEX_AGENTS_TEMP_DIR" ] || rm -rf "$CODEX_AGENTS_TEMP_DIR"
    [ -z "$SETTINGS_STAGE" ] || rm -f "$SETTINGS_STAGE"
}
trap cleanup_bootstrap_stages EXIT

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
    PROJECTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    echo "📍 Multi-project mode detected"
    echo "   Codex config: $CROSSCHECK_DIR"
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

# Resolve the Codex-native files for either the multi-project or ~/.crosscheck layout.
if [ -f "$CROSSCHECK_DIR/CODEX.md" ]; then
    CODEX_SOURCE_DIR="$CROSSCHECK_DIR"
else
    CODEX_SOURCE_DIR="$CROSSCHECK_DIR/codex"
fi
if [ -f "$CROSSCHECK_DIR/VERSION" ]; then
    CROSSCHECK_ROOT_DIR="$CROSSCHECK_DIR"
else
    CROSSCHECK_ROOT_DIR="$(cd "$CROSSCHECK_DIR/.." && pwd)"
fi

# 2. Install a managed pointer in Codex's discovered global instruction file.
echo "📝 Step 2: Register the global Codex workflow..."
CODEX_AGENTS_FILE="$HOME/.codex/AGENTS.md"
CODEX_AGENTS_DIR="$HOME/.codex"
mkdir -p "$CODEX_AGENTS_DIR"
CODEX_AGENTS_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/crosscheck-codex-agents.XXXXXX")"
CODEX_AGENTS_SNAPSHOT="$CODEX_AGENTS_TEMP_DIR/snapshot"
CODEX_AGENTS_STAGE="$CODEX_AGENTS_TEMP_DIR/stage"
: > "$CODEX_AGENTS_SNAPSHOT"
: > "$CODEX_AGENTS_STAGE"
if python3 "$CROSSCHECK_ROOT_DIR/scripts/atomic-publish-file.py" snapshot \
    "$CODEX_AGENTS_DIR" "AGENTS.md" "$CODEX_AGENTS_SNAPSHOT"; then
    CODEX_AGENTS_EXPECTED="$CODEX_AGENTS_SNAPSHOT"
else
    SNAPSHOT_STATUS=$?
    if [ "$SNAPSHOT_STATUS" -ne 4 ]; then
        echo "❌ Could not safely read $CODEX_AGENTS_FILE" >&2
        exit 1
    fi
    CODEX_AGENTS_EXPECTED="--absent"
fi
python3 - "$CODEX_AGENTS_EXPECTED" "$CODEX_AGENTS_SNAPSHOT" "$CODEX_AGENTS_STAGE" "$CODEX_SOURCE_DIR/CODEX.md" <<'PY'
from pathlib import Path
import os
import stat
import sys

expected_snapshot = sys.argv[1]
snapshot_file = Path(sys.argv[2])
stage_file = Path(sys.argv[3])
workflow = Path(sys.argv[4]).expanduser().resolve()
start = "<!-- BEGIN CrossCheck managed workflow -->"
end = "<!-- END CrossCheck managed workflow -->"
block = f"{start}\nRead and follow the CrossCheck Codex workflow at {workflow}.\n{end}"
text = snapshot_file.read_text() if expected_snapshot != "--absent" else ""
has_start = start in text
has_end = end in text
if has_start != has_end or text.count(start) > 1 or text.count(end) > 1:
    raise SystemExit(f"Malformed CrossCheck workflow markers in {Path.home() / '.codex/AGENTS.md'}")
if has_start:
    before, remainder = text.split(start, 1)
    _, after = remainder.split(end, 1)
    updated = before.rstrip() + "\n\n" + block + after
else:
    updated = text.rstrip() + ("\n\n" if text.strip() else "") + block + "\n"
stage_file.write_text(updated)
if expected_snapshot != "--absent":
    mode = stat.S_IMODE(snapshot_file.stat().st_mode)
else:
    current_umask = os.umask(0)
    os.umask(current_umask)
    mode = 0o666 & ~current_umask
os.chmod(stage_file, mode)
PY
if ! python3 "$CROSSCHECK_ROOT_DIR/scripts/atomic-publish-file.py" publish \
    "$CODEX_AGENTS_DIR" "AGENTS.md" "$CODEX_AGENTS_EXPECTED" "$CODEX_AGENTS_STAGE"; then
    echo "❌ Could not safely register workflow in $CODEX_AGENTS_FILE" >&2
    exit 1
fi
echo "   ✅ Registered workflow in $CODEX_AGENTS_FILE"
echo "   📖 Workflow source: $CODEX_SOURCE_DIR/CODEX.md"
echo ""

# 3. Copy settings template if needed
echo "📝 Step 3: Configure settings..."
SETTINGS_FILE="$HOME/.codex/settings.json"
if [ -e "$SETTINGS_FILE" ] || [ -L "$SETTINGS_FILE" ]; then
    echo "   ✅ Settings already exist at ~/.codex/settings.json"
    "$CROSSCHECK_ROOT_DIR/scripts/sync-critical-settings.sh" "$SETTINGS_FILE"
else
    echo "   Creating ~/.codex/settings.json from template..."
    SETTINGS_STAGE="$(mktemp "${TMPDIR:-/tmp}/crosscheck-codex-settings.XXXXXX")"
    cp "$CROSSCHECK_ROOT_DIR/settings.template.json" "$SETTINGS_STAGE"
    if python3 "$CROSSCHECK_ROOT_DIR/scripts/atomic-publish-file.py" publish \
        "$HOME" ".codex/settings.json" --absent "$SETTINGS_STAGE"; then
        echo "   ⚠️  TODO: Edit ~/.codex/settings.json to customize for your stack"
        echo "      Remove Spencer's commands (codex*, dailybrief*) and add yours"
    else
        PUBLISH_STATUS=$?
        if [ "$PUBLISH_STATUS" -eq 3 ] && [ -f "$SETTINGS_FILE" ]; then
            echo "   Settings appeared during setup; updating the existing file safely"
            "$CROSSCHECK_ROOT_DIR/scripts/sync-critical-settings.sh" "$SETTINGS_FILE"
        else
            echo "   ❌ Could not safely create ~/.codex/settings.json" >&2
            exit 1
        fi
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
bash "$CROSSCHECK_ROOT_DIR/codex/scripts/sync-managed-codex-skills.sh" "$CROSSCHECK_ROOT_DIR" "$HOME"
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
if [ -d "$CODEX_SOURCE_DIR/agents" ]; then
    mkdir -p "$HOME/.codex/agents"
    if cp -r "$CODEX_SOURCE_DIR/agents/"* "$HOME/.codex/agents/" 2>/dev/null; then
        agent_count=$(ls "$HOME/.codex/agents/" 2>/dev/null | wc -l | tr -d ' ')
        echo "   ✅ Installed $agent_count agents to ~/.codex/agents/"
    else
        echo "   ⚠️  Failed to copy agents (check permissions)"
    fi
else
    echo "   ⚠️  No agents directory found in $CODEX_SOURCE_DIR"
fi

echo ""
echo "✅ CrossCheck Bootstrap Complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 What was installed:"
if [ "$INSTALL_MODE" = "multi-project" ]; then
    echo "   • CrossCheck workflow at $CROSSCHECK_DIR"
    echo "   • Global workflow pointer at $CODEX_AGENTS_FILE"
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
echo "   2. Codex will load the workflow through $CODEX_AGENTS_FILE"
echo "      Source: $CODEX_SOURCE_DIR/CODEX.md"
echo "      Supporting docs: $CROSSCHECK_ROOT_DIR/QUICK-REFERENCE.md, docs/rules/"
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
