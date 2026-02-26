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
# Uses a feature branch to avoid Claude approval gate on main
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

    # Switch to feature branch (avoids Claude approval gate on main)
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
# Pre-commit: Provider-specific token detection
# ============================================================
echo "📋 Category: Pre-commit provider-specific tokens"
echo ""

test_provider_token_blocks() {
    setup_test_repo "provider-token"
    # Use a GitHub PAT pattern with a non-keyword variable name
    # so only the provider-specific check catches it (not the generic secret check)
    local token_prefix="ghp_" token_body="abcdefghijklmnopqrstuvwxyz1234567890"
    echo "SETTING=${token_prefix}${token_body}" > config.txt
    git add config.txt
    if git commit -m "feat: add config template file" -q 2>&1; then
        fail "Committing provider-specific token should be blocked"
    else
        pass "Provider-specific token (GitHub PAT) blocks commit"
    fi
}

test_provider_token_blocks
echo ""

# ============================================================
# Post-commit: Checkpoint and session tracking
# ============================================================
echo "📋 Category: Post-commit checkpoint and session tracking"
echo ""

test_progress_checkpoint_created() {
    setup_test_repo "progress-checkpoint"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    # Create PROGRESS.md and commit it (no-verify to skip hooks for setup)
    echo "# Progress" > PROGRESS.md
    git add PROGRESS.md
    git commit -m "chore: add progress tracking file" -q --no-verify

    # Now make a real commit that triggers post-commit hook
    echo "change" > data.txt
    git add data.txt
    git commit -m "feat: add data file for testing" -q 2>&1 || true

    if grep -q "## Checkpoint:" PROGRESS.md; then
        pass "PROGRESS.md checkpoint created after commit"
    else
        fail "PROGRESS.md should have checkpoint after commit"
    fi
}

test_session_counter_incremented() {
    setup_test_repo "session-counter"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    echo "change" > data.txt
    git add data.txt
    git commit -m "feat: add data file for testing" -q 2>&1 || true

    counter_file=".git/hooks-session-counter"
    if [ -f "$counter_file" ] && [ "$(cat "$counter_file")" -ge 1 ]; then
        pass "Session counter incremented after commit"
    else
        fail "Session counter should be >= 1 after commit"
    fi
}

test_session_reminder_at_five() {
    setup_test_repo "session-reminder"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    # Pre-set counter to 4 so next commit triggers reminder at 5
    echo "4" > ".git/hooks-session-counter"

    echo "change5" > data.txt
    git add data.txt
    output=$(git commit -m "feat: trigger session reminder now" 2>&1) || true

    if echo "$output" | grep -q "Long session detected"; then
        pass "Session reminder shown at 5 commits"
    else
        fail "Session reminder should appear at 5 commits"
    fi
}

test_progress_checkpoint_created
test_session_counter_incremented
test_session_reminder_at_five
echo ""

# ============================================================
# Pre-push: Secret detection and branch rules
# ============================================================
echo "📋 Category: Pre-push secret detection"
echo ""

setup_test_repo_with_remote() {
    local name="$1"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    local REMOTE_DIR="/tmp/hook-behavior-test-${name}-remote-$$"
    rm -rf "$TEST_DIR" "$REMOTE_DIR" 2>/dev/null || true

    # Create bare remote
    mkdir -p "$REMOTE_DIR"
    cd "$REMOTE_DIR"
    git init -q --bare

    # Create local repo
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"
    git remote add origin "$REMOTE_DIR"

    # Install commit hooks only (pre-push installed AFTER initial push to avoid
    # the pre-check gate that blocks pushes to main without /techdebt marker)
    mkdir -p .git/hooks
    for hook in pre-commit commit-msg; do
        cp "$CROSSCHECK_DIR/git-hooks/$hook" ".git/hooks/$hook"
        chmod +x ".git/hooks/$hook"
    done

    # Initial commit and push (no pre-push hook yet)
    # Include timestamps in README.md to satisfy pre-push timestamp check
    cat > README.md << 'READMEEOF'
# Test

**Created:** 2026-01-01-00-00
**Last Updated:** 2026-01-01-00-00
READMEEOF
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify
    git push -u origin main -q 2>/dev/null

    # NOW install pre-push hook (after initial main push)
    cp "$CROSSCHECK_DIR/git-hooks/pre-push" ".git/hooks/pre-push"
    chmod +x ".git/hooks/pre-push"

    # Switch to feature branch
    git checkout -q -b feat/test
}

test_prepush_secret_rescan_blocks() {
    setup_test_repo_with_remote "prepush-secret"

    # Build secret from parts to avoid triggering repo's own hooks
    local key_name="api_key" key_val="sk-proj-abcdefghijklmnopqrstuvwx"
    echo "$key_name = \"$key_val\"" > secret.py
    git add secret.py
    git commit -m "feat: add config file with key" -q --no-verify

    if git push origin feat/test 2>&1; then
        fail "Pushing secret should be blocked by pre-push"
    else
        pass "Pre-push secret re-scan blocks push"
    fi
}

test_prepush_feature_branch_allowed() {
    setup_test_repo_with_remote "prepush-clean"

    echo "clean code" > app.py
    git add app.py
    git commit -m "feat: add clean application code" -q --no-verify

    if git push origin feat/test 2>&1; then
        pass "Clean feature branch push allowed"
    else
        fail "Clean feature branch push should be allowed"
    fi
}

test_prepush_provider_token_blocks() {
    setup_test_repo_with_remote "prepush-provider"

    # Use a GitHub PAT pattern with a non-keyword variable name
    # to ensure only the provider-specific check catches it (not the generic secret check)
    local token_prefix="ghp_" token_body="abcdefghijklmnopqrstuvwxyz1234567890"
    echo "SETTING=${token_prefix}${token_body}" > config.txt
    git add config.txt
    git commit -m "feat: add config template file" -q --no-verify

    if git push origin feat/test 2>&1; then
        fail "Pushing provider-specific token should be blocked"
    else
        pass "Pre-push blocks provider-specific token (GitHub PAT)"
    fi
}

test_prepush_delete_branch_allowed() {
    setup_test_repo_with_remote "prepush-delete"

    # Push a feature branch first
    echo "feature code" > feature.py
    git add feature.py
    git commit -m "feat: add feature code here" -q --no-verify
    git push origin feat/test -q 2>/dev/null

    # Now delete the remote branch — should NOT be blocked
    if git push origin --delete feat/test 2>&1; then
        pass "Branch deletion push is not blocked"
    else
        fail "git push --delete should not be blocked by pre-push hook"
    fi
}

test_prepush_secret_rescan_blocks
test_prepush_feature_branch_allowed
test_prepush_provider_token_blocks
test_prepush_delete_branch_allowed
echo ""

# ============================================================
# Post-checkout: Environment cleanup and TODO.md
# ============================================================
echo "📋 Category: Post-checkout environment cleanup"
echo ""

test_postcheckout_todo_branch_header() {
    setup_test_repo "checkout-todo"
    cp "$CROSSCHECK_DIR/git-hooks/post-checkout" ".git/hooks/post-checkout"
    chmod +x ".git/hooks/post-checkout"

    # Create TODO.md on the feature branch
    echo "# TODO" > TODO.md
    echo "- Task 1" >> TODO.md
    git add TODO.md
    git commit -m "chore: add todo file for testing" -q --no-verify

    # Switch to a new branch (triggers post-checkout)
    git checkout -q -b feat/other 2>&1 || true

    if grep -q "## Current Branch: feat/other" TODO.md; then
        pass "TODO.md branch header updated on checkout"
    else
        fail "TODO.md should have branch header after checkout"
    fi
}

test_postcheckout_cleanup_runs() {
    setup_test_repo "checkout-cleanup"
    cp "$CROSSCHECK_DIR/git-hooks/post-checkout" ".git/hooks/post-checkout"
    chmod +x ".git/hooks/post-checkout"

    # Switch branches and check that the hook runs (check output)
    output=$(git checkout -q -b feat/cleanup-test 2>&1) || true

    if echo "$output" | grep -q "Branch switched"; then
        pass "Post-checkout hook runs on branch switch"
    else
        fail "Post-checkout hook should run on branch switch"
    fi
}

test_postcheckout_todo_branch_header
test_postcheckout_cleanup_runs
echo ""

# ============================================================
# Post-merge: PR counter and waterfall reminder
# ============================================================
echo "📋 Category: Post-merge PR counter and waterfall"
echo ""

test_postmerge_pr_counter_incremented() {
    local name="postmerge-counter"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"

    mkdir -p .git/hooks
    cp "$CROSSCHECK_DIR/git-hooks/post-merge" ".git/hooks/post-merge"
    chmod +x ".git/hooks/post-merge"

    # Initial commit on main
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Create and commit on feature branch
    git checkout -q -b feat/merge-test
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "feat: add feature for merge" -q --no-verify

    # Merge into main (diverge first to force true merge)
    git checkout -q main
    echo "main diverge" > diverge.txt
    git add diverge.txt
    git commit -m "chore: diverge main for merge" -q --no-verify
    git merge feat/merge-test --no-edit -q 2>&1 || true

    counter_file=".git/hooks-pr-counter"
    if [ -f "$counter_file" ] && [ "$(cat "$counter_file")" -ge 1 ]; then
        pass "PR counter incremented after merge"
    else
        fail "PR counter should be >= 1 after merge"
    fi
}

test_postmerge_waterfall_reminder() {
    local name="postmerge-waterfall"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"

    mkdir -p .git/hooks
    cp "$CROSSCHECK_DIR/git-hooks/post-merge" ".git/hooks/post-merge"
    chmod +x ".git/hooks/post-merge"

    # Initial commit on main
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Pre-set PR counter to 2 so next merge triggers reminder at 3
    echo "2" > ".git/hooks-pr-counter"

    # Create and commit on feature branch
    git checkout -q -b feat/waterfall-test
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "feat: add feature for waterfall" -q --no-verify

    # Merge into main
    git checkout -q main
    echo "main diverge" > diverge.txt
    git add diverge.txt
    git commit -m "chore: diverge main for merge" -q --no-verify
    output=$(git merge feat/waterfall-test --no-edit 2>&1) || true

    if echo "$output" | grep -q "Assessment waterfall due"; then
        pass "Waterfall reminder shown at 3 PR merges"
    else
        fail "Waterfall reminder should appear at 3 PR merges"
    fi
}

test_postmerge_pr_counter_incremented
test_postmerge_waterfall_reminder
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
