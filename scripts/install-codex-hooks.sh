#!/bin/bash
# Simple one-command Codex hooks installer

set -e

# Derive CrossCheck directory from script location (env var overrides)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

# Parse flags
YES=false
INSTALL_MODE=""
for arg in "$@"; do
    case $arg in
        --yes|-y) YES=true ;;
        --global) INSTALL_MODE="global" ;;
    esac
done

# Helper: prompt user or auto-accept with --yes
confirm() {
    local prompt="$1" default="${2:-N}"
    if [ "$YES" = true ]; then return 0; fi
    read -p "$prompt" -n 1 -r < /dev/tty
    echo
    if [ "$default" = "Y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

echo "🔧 Installing Codex git hooks..."

# Verify CrossCheck source exists
if [ ! -d "$CROSSCHECK_DIR/git-hooks" ] || [ ! -d "$CROSSCHECK_DIR/scripts" ]; then
    echo "❌ Error: CrossCheck not found at $CROSSCHECK_DIR"
    echo "   Run: git clone https://github.com/sburl/CrossCheck.git ~/.claude/CrossCheck"
    exit 1
fi

# Determine installation type
if [ "$INSTALL_MODE" = "global" ]; then
    echo "📦 Installing globally for all repos..."

    # Create global hooks directory with post-commit.d subdirectory
    mkdir -p ~/.claude/git-hooks/post-commit.d

    # Install dispatcher hook if it doesn't exist or doesn't have .d/ support
    # (This is what actually runs scripts in post-commit.d/)
    if [ ! -f ~/.claude/git-hooks/post-commit ]; then
        echo "  📝 Installing post-commit dispatcher hook..."
        cp "$CROSSCHECK_DIR/git-hooks/post-commit" ~/.claude/git-hooks/post-commit
        chmod +x ~/.claude/git-hooks/post-commit
        echo "  ✅ Dispatcher installed (runs post-commit.d/ scripts)"
    elif ! grep -q "post-commit.d" ~/.claude/git-hooks/post-commit 2>/dev/null; then
        # Existing hook doesn't have dispatcher logic
        echo "  ⚠️  WARNING: Existing post-commit hook found without .d/ support"
        echo "     Your hook: ~/.claude/git-hooks/post-commit"
        echo "     Codex review won't run unless you manually integrate it."
        echo ""
        echo "  Options:"
        echo "    1. Backup and replace: mv ~/.claude/git-hooks/post-commit{,.backup}"
        echo "       then re-run this installer"
        echo "    2. Manually add to your hook (see README.md#detailed-setup)"
        echo ""
        if confirm "  Replace existing hook? (y/N) "; then
            mv ~/.claude/git-hooks/post-commit ~/.claude/git-hooks/post-commit.backup
            cp "$CROSSCHECK_DIR/git-hooks/post-commit" ~/.claude/git-hooks/post-commit
            chmod +x ~/.claude/git-hooks/post-commit
            echo "  ✅ Dispatcher installed (old hook backed up)"
        else
            echo "  ⚠️  Skipping dispatcher install - Codex review may not work"
            echo "     Manual integration required"
        fi
    else
        echo "  ℹ️  Dispatcher already exists: ~/.claude/git-hooks/post-commit"
    fi

    # Copy Codex review hook into post-commit.d/
    cp "$CROSSCHECK_DIR/scripts/codex-commit-review.sh" ~/.claude/git-hooks/post-commit.d/codex-review
    chmod +x ~/.claude/git-hooks/post-commit.d/codex-review

    # Set git to use global hooks (if not already set)
    if [ "$(git config --global core.hooksPath)" != "$HOME/.claude/git-hooks" ]; then
        git config --global core.hooksPath ~/.claude/git-hooks
    fi

    echo "✅ Installed globally! All repos will now use Codex hooks."
    echo "   Dispatcher: ~/.claude/git-hooks/post-commit"
    echo "   Codex hook: ~/.claude/git-hooks/post-commit.d/codex-review"
    echo "   To disable: rm ~/.claude/git-hooks/post-commit.d/codex-review"

elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "📦 Installing for current repo only..."

    # Use git-common-dir for worktree compatibility (same pattern as install-git-hooks.sh)
    HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
    mkdir -p "$HOOKS_DIR/post-commit.d"

    # Warn if core.hooksPath is set (repo-only hooks won't run)
    if git config core.hooksPath >/dev/null 2>&1; then
        echo "  ⚠️  WARNING: core.hooksPath is set to $(git config core.hooksPath)"
        echo "     Repo-only hooks in $HOOKS_DIR will be IGNORED by git"
        echo "     Installed hooks will NOT run unless you:"
        echo "     1. Unset core.hooksPath: git config --unset core.hooksPath"
        echo "     2. OR install globally: $0 --global"
        echo ""
        # With --yes, fail hard rather than silently installing hooks that won't run
        if [ "$YES" = true ]; then
            echo "  ❌ Aborting: --yes cannot override core.hooksPath conflict (hooks would be ignored)"
            exit 1
        fi
        if ! confirm "  Continue anyway? (y/N) "; then
            echo "  Cancelled."
            exit 0
        fi
    fi

    # Install dispatcher hook if it doesn't exist or doesn't have .d/ support
    # (This is what actually runs scripts in post-commit.d/)
    if [ ! -f "$HOOKS_DIR/post-commit" ]; then
        echo "  📝 Installing post-commit dispatcher hook..."
        cp "$CROSSCHECK_DIR/git-hooks/post-commit" "$HOOKS_DIR/post-commit"
        chmod +x "$HOOKS_DIR/post-commit"
        echo "  ✅ Dispatcher installed (runs post-commit.d/ scripts)"
    elif ! grep -q "post-commit.d" "$HOOKS_DIR/post-commit" 2>/dev/null; then
        # Existing hook doesn't have dispatcher logic
        echo "  ⚠️  WARNING: Existing post-commit hook found without .d/ support"
        echo "     Your hook: $HOOKS_DIR/post-commit"
        echo "     Codex review won't run unless you manually integrate it."
        echo ""
        echo "  Options:"
        echo "    1. Backup and replace: mv $HOOKS_DIR/post-commit $HOOKS_DIR/post-commit.backup"
        echo "       then re-run this installer"
        echo "    2. Manually add to your hook:"
        echo "       for script in $HOOKS_DIR/post-commit.d/*; do"
        echo "         [ -x \"\$script\" ] && \"\$script\" || true"
        echo "       done"
        echo ""
        if confirm "  Replace existing hook? (y/N) "; then
            mv "$HOOKS_DIR/post-commit" "$HOOKS_DIR/post-commit.backup"
            cp "$CROSSCHECK_DIR/git-hooks/post-commit" "$HOOKS_DIR/post-commit"
            chmod +x "$HOOKS_DIR/post-commit"
            echo "  ✅ Dispatcher installed (old hook backed up)"
        else
            echo "  ⚠️  Skipping dispatcher install - Codex review may not work"
            echo "     Manual integration required"
        fi
    else
        echo "  ℹ️  Dispatcher already exists: $HOOKS_DIR/post-commit"
    fi

    # Copy Codex review hook into post-commit.d/
    cp "$CROSSCHECK_DIR/scripts/codex-commit-review.sh" "$HOOKS_DIR/post-commit.d/codex-review"
    chmod +x "$HOOKS_DIR/post-commit.d/codex-review"

    echo "✅ Installed in $(basename "$(pwd)")!"
    echo "   Dispatcher: $HOOKS_DIR/post-commit"
    echo "   Codex hook: $HOOKS_DIR/post-commit.d/codex-review"
    echo "   To disable: rm $HOOKS_DIR/post-commit.d/codex-review"

else
    echo "❌ Error: Not in a git repository and --global flag not provided"
    echo ""
    echo "Usage:"
    echo "  # Install in current repo:"
    echo "  ~/.claude/CrossCheck/scripts/install-codex-hooks.sh"
    echo ""
    echo "  # Install globally for all repos:"
    echo "  ~/.claude/CrossCheck/scripts/install-codex-hooks.sh --global"
    exit 1
fi

echo ""
echo "📝 View Codex reviews: tail -f ~/.claude/codex-commit-reviews.log"
echo "🔇 Skip hook once: SKIP_CODEX_REVIEW=1 git commit -m \"message\""
