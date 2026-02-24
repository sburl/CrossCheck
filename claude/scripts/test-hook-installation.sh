#!/bin/bash
# Test script to verify hook installation scenarios work correctly
# Tests all combinations of install-git-hooks.sh and install-claude-hooks.sh

set -e

# Derive CrossCheck directory from script location (env var overrides)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

if [ ! -d "$CROSSCHECK_DIR/scripts" ]; then
    echo "❌ Error: CrossCheck scripts not found at $CROSSCHECK_DIR/scripts"
    exit 1
fi

INSTALL_GIT_HOOKS="$CROSSCHECK_DIR/scripts/install-git-hooks.sh"
INSTALL_CODEX_HOOKS="$CROSSCHECK_DIR/scripts/install-claude-hooks.sh"

echo "ℹ️  Testing with scripts from: $CROSSCHECK_DIR"
echo ""

echo "🧪 Hook Installation Test Suite"
echo "================================"
echo ""

# Claude log line-count checkpoint (avoids truncation + permission issues)
CODEX_LOG="$HOME/.claude/claude-commit-reviews.log"
codex_log_checkpoint() {
    if [ -f "$CODEX_LOG" ]; then
        wc -l < "$CODEX_LOG" | tr -d ' '
    else
        echo 0
    fi
}
codex_log_has_new_match() {
    local pattern="$1" since="$2"
    tail -n +"$((since + 1))" "$CODEX_LOG" 2>/dev/null | grep -q "$pattern"
}

# Isolate tests from user's global git config (core.hooksPath, aliases, etc.)
# GIT_CONFIG_GLOBAL=/dev/null prevents the global config from leaking into test repos,
# which would cause install-git-hooks.sh --yes to abort on core.hooksPath detection.
export GIT_CONFIG_GLOBAL=/dev/null

# Cleanup function
cleanup() {
    echo "  🧹 Cleaning up test directories..."
    rm -rf /tmp/hook-test-* 2>/dev/null || true
}
trap cleanup EXIT

# Poll for log match instead of fixed sleep (more robust on slow systems)
wait_for_log_match() {
    local pattern="$1" since="$2" max_attempts="${3:-10}"
    local _attempt
    for _attempt in $(seq 1 "$max_attempts"); do
        if codex_log_has_new_match "$pattern" "$since"; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Test 1: Claude hooks installer alone
test_codex_alone() {
    echo "📋 Test 1: install-claude-hooks.sh alone"
    echo "  Should install: dispatcher + claude-review"
    echo ""

    cleanup
    mkdir -p /tmp/hook-test-claude-alone
    cd /tmp/hook-test-claude-alone
    git init -q

    # Create initial commit (hooks need a commit history to work)
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q

    # Install Claude hooks only (--yes for headless)
    "$INSTALL_CODEX_HOOKS" --yes

    # Verify dispatcher exists
    if [ ! -f .git/hooks/post-commit ]; then
        echo "  ❌ FAIL: Dispatcher not installed"
        return 1
    fi
    echo "  ✅ Dispatcher installed"

    # Verify claude-review exists
    if [ ! -f .git/hooks/post-commit.d/claude-review ]; then
        echo "  ❌ FAIL: Claude review hook not installed"
        return 1
    fi
    echo "  ✅ Claude review hook installed"

    # Checkpoint log before triggering commit
    local log_before
    log_before=$(codex_log_checkpoint)

    # Test it runs (use test: to trigger review without requiring approval on main)
    echo "test file" > test.txt
    git add test.txt
    git commit -m "test: claude alone verification" -q

    # Poll for log entry (more robust than fixed sleep on slow systems)
    if ! wait_for_log_match "Commit Review Needed" "$log_before"; then
        echo "  ❌ FAIL: No new review entry in log (checked lines after $log_before)"
        return 1
    fi
    echo "  ✅ Claude review logged successfully"

    echo ""
    echo "  ✅ Test 1: PASSED"
    echo ""
}

# Test 2: Git hooks then Claude hooks
test_git_then_codex() {
    echo "📋 Test 2: install-git-hooks.sh then install-claude-hooks.sh"
    echo "  Should not conflict, Claude should detect existing dispatcher"
    echo ""

    cleanup
    mkdir -p /tmp/hook-test-git-then-claude
    cd /tmp/hook-test-git-then-claude
    git init -q

    # Create initial commit (git diff-tree HEAD needs a parent commit)
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q

    # Install git hooks first (--yes for headless)
    echo "  Installing git hooks..."
    "$INSTALL_GIT_HOOKS" --yes > /dev/null

    # Verify dispatcher from git hooks
    if [ ! -f .git/hooks/post-commit ]; then
        echo "  ❌ FAIL: Git hooks didn't install dispatcher"
        return 1
    fi
    echo "  ✅ Git hooks installed dispatcher"

    # Install Claude hooks second (--yes for headless)
    echo "  Installing Claude hooks..."
    output=$("$INSTALL_CODEX_HOOKS" --yes)

    # Should see "already exists" message
    if ! echo "$output" | grep -q "already exists"; then
        echo "  ⚠️  WARNING: Expected 'already exists' message not found"
    else
        echo "  ✅ Detected existing dispatcher"
    fi

    # Verify claude-review added to .d/
    if [ ! -f .git/hooks/post-commit.d/claude-review ]; then
        echo "  ❌ FAIL: Claude review not added to .d/"
        return 1
    fi
    echo "  ✅ Claude review added to post-commit.d/"

    # Create PROGRESS.md first (hook only appends if it exists)
    touch PROGRESS.md

    # Checkpoint log before triggering commit
    local log_before
    log_before=$(codex_log_checkpoint)

    # Test both work (use test: to trigger Claude without requiring approval)
    echo "test file" > test.txt
    git add test.txt PROGRESS.md
    git commit -m "test: verify both hooks work" -q

    # Should have updated PROGRESS.md (from git hooks, runs synchronously)
    if ! grep -q "Checkpoint" PROGRESS.md; then
        echo "  ❌ FAIL: Git hooks didn't run (no checkpoint in PROGRESS.md)"
        return 1
    fi
    echo "  ✅ Git hooks ran (PROGRESS.md updated)"

    # Poll for new log entry (from Claude hooks)
    if ! wait_for_log_match "Commit Review Needed" "$log_before"; then
        echo "  ❌ FAIL: Claude hooks didn't run (no new log entry after line $log_before)"
        return 1
    fi
    echo "  ✅ Claude hooks ran (review logged)"

    echo ""
    echo "  ✅ Test 2: PASSED"
    echo ""
}

# Test 3: Bootstrap script (both at once)
test_bootstrap() {
    echo "📋 Test 3: bootstrap-crosscheck.sh (installs both)"
    echo "  Should install all hooks without conflicts"
    echo ""

    echo "  ℹ️  SKIPPED: Bootstrap requires interactive prompts"
    echo "  Manual test: Run bootstrap and verify both hooks work"
    echo ""
}

# Test 4: Claude then git hooks (reverse order)
test_codex_then_git() {
    echo "📋 Test 4: install-claude-hooks.sh then install-git-hooks.sh"
    echo "  Git hooks should see existing dispatcher and preserve it"
    echo ""

    cleanup
    mkdir -p /tmp/hook-test-claude-then-git
    cd /tmp/hook-test-claude-then-git
    git init -q

    # Create initial commit (git diff-tree HEAD needs a parent commit)
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q

    # Install Claude first (--yes for headless)
    echo "  Installing Claude hooks..."
    "$INSTALL_CODEX_HOOKS" --yes > /dev/null

    # Verify Claude installed dispatcher
    if [ ! -f .git/hooks/post-commit ]; then
        echo "  ❌ FAIL: Claude didn't install dispatcher"
        return 1
    fi
    echo "  ✅ Claude installed dispatcher"

    # Install git hooks second (--yes for headless)
    echo "  Installing git hooks..."
    "$INSTALL_GIT_HOOKS" --yes > /dev/null

    # Git hooks should overwrite dispatcher (includes more hooks)
    if [ ! -f .git/hooks/post-commit ]; then
        echo "  ❌ FAIL: Post-commit missing after git hooks install"
        return 1
    fi
    echo "  ✅ Post-commit exists after git hooks install"

    # Claude hook should still exist in .d/
    if [ ! -f .git/hooks/post-commit.d/claude-review ]; then
        echo "  ❌ FAIL: Claude review lost after git hooks install"
        return 1
    fi
    echo "  ✅ Claude review preserved in post-commit.d/"

    # Create PROGRESS.md first
    touch PROGRESS.md

    # Checkpoint log before triggering commit
    local log_before
    log_before=$(codex_log_checkpoint)

    # Test both work (use test: to trigger Claude without requiring approval)
    echo "test file" > test.txt
    git add test.txt PROGRESS.md
    git commit -m "test: verify reverse order" -q

    if ! grep -q "Checkpoint" PROGRESS.md; then
        echo "  ❌ FAIL: Git hooks not working"
        return 1
    fi
    echo "  ✅ Git hooks working"

    if ! wait_for_log_match "Commit Review Needed" "$log_before"; then
        echo "  ❌ FAIL: Claude hooks not working (no new log entry after line $log_before)"
        return 1
    fi
    echo "  ✅ Claude hooks working"

    echo ""
    echo "  ✅ Test 4: PASSED"
    echo ""
}

# Run all tests
main() {
    # Call test functions without || to preserve set -e behavior
    test_codex_alone
    test_git_then_codex
    test_bootstrap
    test_codex_then_git

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ All tests passed!"
    echo ""
    echo "Verified scenarios:"
    echo "  1. Claude installer alone ✅"
    echo "  2. Git hooks → Claude hooks ✅"
    echo "  3. Bootstrap (manual test required)"
    echo "  4. Claude hooks → Git hooks ✅"
    echo ""
    echo "Hook installation is working correctly in all scenarios."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cleanup
}

main
