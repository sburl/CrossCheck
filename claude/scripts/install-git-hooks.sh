#!/bin/bash
# Install all CrossCheck git hooks (deterministic workflow automation)

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

echo "🎣 Installing CrossCheck git hooks..."
echo ""

# Verify CrossCheck source exists (for both global and local modes)
if [ ! -d "$CROSSCHECK_DIR/git-hooks" ]; then
    echo "❌ Error: CrossCheck hooks not found at $CROSSCHECK_DIR/git-hooks"
    echo "   Run: git clone https://github.com/sburl/CrossCheck.git ~/.crosscheck"
    exit 1
fi

# Determine installation type
if [ "$INSTALL_MODE" = "global" ]; then
    echo "📦 Global installation (all repos)..."
    echo ""
    echo "⚠️  WARNING: Global git hooks require git 2.9+ and core.hooksPath"
    echo "   This will affect ALL repositories on your system."
    echo ""
    if ! confirm "Continue with global installation? (y/N) "; then
        echo "Cancelled."
        exit 0
    fi

    # Create global hooks directory
    HOOKS_DIR="$HOME/.claude/git-hooks"
    mkdir -p "$HOOKS_DIR"

    # Copy hooks
    CROSSCHECK_HOOKS="$CROSSCHECK_DIR/git-hooks"
    for hook in pre-commit commit-msg post-commit post-checkout pre-push post-merge; do
        if [ -f "$CROSSCHECK_HOOKS/$hook" ]; then
            # Remove symlink first if it exists (prevent overwriting target)
            if [ -L "$HOOKS_DIR/$hook" ]; then
                rm "$HOOKS_DIR/$hook"
            fi
            cp "$CROSSCHECK_HOOKS/$hook" "$HOOKS_DIR/$hook"
            chmod +x "$HOOKS_DIR/$hook"
            echo "  ✅ Installed $hook"
        fi
    done

    # Configure git to use global hooks
    git config --global core.hooksPath "$HOOKS_DIR"

    echo ""
    echo "✅ Global git hooks installed!"
    echo "   Hooks directory: $HOOKS_DIR"
    echo "   Configured via: git config --global core.hooksPath"
    echo ""
    echo "To disable globally: git config --global --unset core.hooksPath"
    echo "Note: --no-verify is blocked by permissions (policy enforcement)"

elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "📦 Installing for current repo only..."
    echo ""

    # Use git-common-dir for hooks (works for worktrees where hooks execute from common dir)
    # Force common hooks to avoid writing to global core.hooksPath
    HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
    CROSSCHECK_HOOKS="$CROSSCHECK_DIR/git-hooks"

    # Create hooks directory if it doesn't exist (needed for worktrees)
    mkdir -p "$HOOKS_DIR"

    # Warn if core.hooksPath is set (repo-only hooks won't run)
    if git config core.hooksPath >/dev/null 2>&1; then
        echo "⚠️  WARNING: core.hooksPath is set to $(git config core.hooksPath)"
        echo "   Repo-only hooks in $HOOKS_DIR will be IGNORED"
        echo "   Installed hooks will NOT run unless you:"
        echo "   1. Unset core.hooksPath: git config --unset core.hooksPath"
        echo "   2. OR install globally: $0 --global"
        echo ""
        # With --yes, fail hard rather than silently installing hooks that won't run
        if [ "$YES" = true ]; then
            echo "❌ Aborting: --yes cannot override core.hooksPath conflict (hooks would be ignored)"
            exit 1
        fi
        if ! confirm "Continue anyway? (y/N) "; then
            echo "Cancelled."
            exit 0
        fi
    fi

    # Check for existing hooks and offer to backup
    existing_hooks=""
    for hook in pre-commit commit-msg post-commit post-checkout pre-push post-merge; do
        if [ -f "$HOOKS_DIR/$hook" ] && [ ! -L "$HOOKS_DIR/$hook" ]; then
            existing_hooks="$existing_hooks $hook"
        fi
    done

    if [ -n "$existing_hooks" ]; then
        echo "⚠️  Existing hooks found:$existing_hooks"
        if confirm "Backup existing hooks? (Y/n) " "Y"; then
            # Compute timestamp once to avoid race condition
            backup_dir="$HOOKS_DIR/backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            # shellcheck disable=SC2086  # intentional word splitting on hook list
            for hook in $existing_hooks; do
                cp "$HOOKS_DIR/$hook" "$backup_dir/$hook"
            done
            echo "  ✅ Backed up to $backup_dir/"
        fi
    fi

    # Install hooks
    for hook in pre-commit commit-msg post-commit post-checkout pre-push post-merge; do
        if [ -f "$CROSSCHECK_HOOKS/$hook" ]; then
            # Remove symlink first if it exists (prevent overwriting target)
            if [ -L "$HOOKS_DIR/$hook" ]; then
                rm "$HOOKS_DIR/$hook"
            fi
            cp "$CROSSCHECK_HOOKS/$hook" "$HOOKS_DIR/$hook"
            chmod +x "$HOOKS_DIR/$hook"
            echo "  ✅ Installed $hook"
        fi
    done

    echo ""
    echo "✅ Git hooks installed for $(basename "$(pwd)")!"
    echo "   Hooks directory: $HOOKS_DIR"
    echo ""
    echo "To disable a hook: chmod -x $HOOKS_DIR/<hook-name>"
    echo "Note: --no-verify is blocked by permissions (policy enforcement)"
    echo "To remove: rm $HOOKS_DIR/{pre-commit,commit-msg,post-commit,post-checkout,pre-push,post-merge}"

else
    echo "❌ Error: Not in a git repository and --global flag not provided"
    echo ""
    echo "Usage:"
    echo "  # Install in current repo:"
    echo "  ~/.crosscheck/scripts/install-git-hooks.sh"
    echo ""
    echo "  # Install globally for all repos:"
    echo "  ~/.crosscheck/scripts/install-git-hooks.sh --global"
    exit 1
fi

echo ""
echo "📖 Documentation: ~/.crosscheck/README.md"
echo "🔍 What was installed:"
echo "  • pre-commit: Quality gates (timestamps, secrets, debug code)"
echo "  • commit-msg: Conventional commits enforcement"
echo "  • post-commit: Checkpointing, assessment counter, Claude review"
echo "  • post-checkout: Background process cleanup, environment reset"
echo "  • pre-push: Final verification (timestamps, markers, conflicts)"
echo "  • post-merge: Branch cleanup, CI verification"
echo ""
echo "Impact:"
echo "  • Permission blocks → 0 (branch cleanup automated)"
echo "  • Background failures → 0 (post-checkout cleanup)"
echo "  • Timestamp lag → 0 (pre-commit enforcement)"
echo "  • Manual pre-PR steps → automated (pre-push verification)"
