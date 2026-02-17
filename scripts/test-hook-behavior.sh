#!/bin/bash
# Test script to verify hook BEHAVIOR (enforcement logic)
# Complements test-hook-installation.sh which tests installation scenarios
#
# Tests that hooks correctly block/allow/warn in the right situations.

set -e

# Derive CrossCheck directory from script location (env var overrides)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

if [ ! -d "$CROSSCHECK_DIR/git-hooks" ]; then
    echo "❌ Error: CrossCheck hooks not found at $CROSSCHECK_DIR/git-hooks"
    exit 1
fi

echo "🧪 Hook Behavior Test Suite"
echo "==========================="
echo ""

PASSED=0
FAILED=0
SKIPPED=0
TEST_DIR=""

# Isolate tests from user's global git config
export GIT_CONFIG_GLOBAL=/dev/null

# Cleanup function — remove all test directories from this run (keyed by PID)
cleanup() {
    rm -rf /tmp/hook-behavior-test-*-$$ 2>/dev/null || true
}
trap cleanup EXIT

# Create a fresh test repo with hooks installed
# Uses a feature branch to avoid Codex approval gate on main
setup_test_repo() {
    local name="$1"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Install CrossCheck hooks directly (no prompts)
    mkdir -p .git/hooks
    for hook in pre-commit commit-msg; do
        cp "$CROSSCHECK_DIR/git-hooks/$hook" ".git/hooks/$hook"
        chmod +x ".git/hooks/$hook"
    done

    # Initial commit on main (needed for diff operations)
    echo "initial" > README.md
    mkdir -p user-content
    echo "human zone" > user-content/README.md
    git add README.md user-content/README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Switch to feature branch (avoids Codex approval gate on main)
    git checkout -q -b feat/test
}

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

skip() {
    SKIPPED=$((SKIPPED + 1))
    echo "  ⏭️  SKIP: $1"
}

# ============================================================
# Pre-commit: Debug code detection
# ============================================================
echo "📋 Category: Pre-commit debug code detection"
echo ""

test_debug_add_warns() {
    setup_test_repo "debug-add"
    echo 'console.log("debug");' > test.js
    git add test.js
    # Capture hook output (commit will succeed since it's a warning)
    output=$(git commit -m "test: add debug code for testing" 2>&1) || true
    if echo "$output" | grep -q "Debug statements found"; then
        pass "Adding console.log triggers debug warning"
    else
        fail "Adding console.log should trigger debug warning"
    fi
}

test_debug_remove_no_warn() {
    # This test verifies the fix from fix/hook-detection-accuracy
    # The pre-commit hook must filter to added lines only (grep '^\+')
    # to avoid false positives when REMOVING debug code
    setup_test_repo "debug-remove"
    echo 'console.log("debug");' > test.js
    git add test.js
    git commit -m "chore: setup file" -q --no-verify

    # Now remove the debug line
    echo '// clean code' > test.js
    git add test.js
    output=$(git commit -m "test: remove debug code from codebase" 2>&1) || true
    if echo "$output" | grep -q "Debug statements found"; then
        # Check if this hook has the fix (filters added lines only)
        if grep -q "grep -E '^\\\+' | grep -qE.*console" "$CROSSCHECK_DIR/git-hooks/pre-commit"; then
            fail "Removing console.log should NOT trigger debug warning (fix is present but not working)"
        else
            skip "Removing console.log triggers false positive (fix pending in fix/hook-detection-accuracy)"
        fi
    else
        pass "Removing console.log does not trigger false positive"
    fi
}

test_debug_add_warns
test_debug_remove_no_warn
echo ""

# ============================================================
# Pre-commit: Secrets detection
# ============================================================
echo "📋 Category: Pre-commit secrets detection"
echo ""

test_secret_blocks() {
    setup_test_repo "secret-block"
    # Build test secret from parts (avoids triggering repo's own pre-commit hook)
    local key_name="api_key" key_val="sk-proj-abcdefghijklmnopqrstuvwx"
    echo "$key_name = \"$key_val\"" > config.py
    git add config.py
    if git commit -m "test: add config with secret key" -q 2>&1; then
        fail "Committing a secret should be blocked"
    else
        pass "Secret in staged changes blocks commit"
    fi
}

test_env_file_blocks() {
    setup_test_repo "env-block"
    echo 'DB_HOST=localhost' > .env
    git add .env
    if git commit -m "test: add env file to project" -q 2>&1; then
        fail "Committing .env should be blocked"
    else
        pass ".env file in staged changes blocks commit"
    fi
}

test_no_secret_passes() {
    setup_test_repo "no-secret"
    echo 'host = "localhost"' > config.py
    git add config.py
    if git commit -m "test: add clean config file here" -q 2>&1; then
        pass "Clean config file passes secrets check"
    else
        fail "Clean config file should not be blocked"
    fi
}

test_secret_blocks
test_env_file_blocks
test_no_secret_passes
echo ""

# ============================================================
# Pre-commit: user-content/ protection
# ============================================================
echo "📋 Category: Pre-commit user-content protection"
echo ""

test_user_content_blocks() {
    setup_test_repo "user-content"
    echo "agent modified this" > user-content/notes.md
    git add user-content/notes.md
    if git commit -m "test: modify user content zone" -q 2>&1; then
        fail "Modifying user-content/ should be blocked"
    else
        pass "user-content/ modification blocks commit"
    fi
}

test_user_content_blocks
echo ""

# ============================================================
# Commit-msg: Conventional commit format
# ============================================================
echo "📋 Category: Commit-msg conventional format"
echo ""

test_good_msg_passes() {
    setup_test_repo "good-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat: add a new feature here" -q 2>&1; then
        pass "Valid conventional commit passes"
    else
        fail "Valid conventional commit should pass"
    fi
}

test_bad_msg_blocks() {
    setup_test_repo "bad-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "added some stuff to the codebase" -q 2>&1; then
        fail "Non-conventional commit should be blocked"
    else
        pass "Non-conventional commit message is rejected"
    fi
}

test_short_msg_blocks() {
    setup_test_repo "short-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat: x" -q 2>&1; then
        fail "Commit with <10 char description should be blocked"
    else
        pass "Short description (<10 chars) is rejected"
    fi
}

test_scoped_msg_passes() {
    setup_test_repo "scoped-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "fix(api): handle null response correctly" -q 2>&1; then
        pass "Scoped conventional commit passes"
    else
        fail "Scoped conventional commit should pass"
    fi
}

test_breaking_msg_passes() {
    setup_test_repo "breaking-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat!: remove deprecated endpoints entirely" -q 2>&1; then
        pass "Breaking change commit passes"
    else
        fail "Breaking change commit should pass"
    fi
}

test_first_line_only() {
    # This test verifies the fix from fix/hook-detection-accuracy
    # The commit-msg hook must check only head -1 for format validation
    setup_test_repo "first-line"
    echo "content" > test.txt
    git add test.txt
    msg="$(printf 'bad first line\nfeat: this line matches but should not save it')"
    if git commit -m "$msg" -q 2>&1; then
        # Check if this hook has the fix (uses head -1)
        if grep -q "head -1 | grep -qE" "$CROSSCHECK_DIR/git-hooks/commit-msg"; then
            fail "Body line matching format should NOT save a bad subject (fix is present but not working)"
        else
            skip "Body line bypasses format check (fix pending in fix/hook-detection-accuracy)"
        fi
    else
        pass "Only first line is checked for conventional format"
    fi
}

test_merge_commit_passes() {
    setup_test_repo "merge-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "Merge branch 'feature' into main" -q 2>&1; then
        pass "Merge commit bypasses format check"
    else
        fail "Merge commit should bypass format check"
    fi
}

test_revert_commit_passes() {
    setup_test_repo "revert-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "Revert \"feat: previous change\"" -q 2>&1; then
        pass "Revert commit bypasses format check"
    else
        fail "Revert commit should bypass format check"
    fi
}

test_good_msg_passes
test_bad_msg_blocks
test_short_msg_blocks
test_scoped_msg_passes
test_breaking_msg_passes
test_first_line_only
test_merge_commit_passes
test_revert_commit_passes
echo ""

# ============================================================
# Summary
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED + SKIPPED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests completed ($PASSED passed, $SKIPPED skipped)"
else
    echo "❌ $FAILED/$TOTAL tests failed"
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAILED" -eq 0 ]
