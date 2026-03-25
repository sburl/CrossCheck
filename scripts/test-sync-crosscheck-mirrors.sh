#!/bin/bash
# Test for sync-crosscheck-mirrors.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/sync-crosscheck-mirrors.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

# Helper to create temporary directory securely
create_temp_dir() {
    mktemp -d "/tmp/crosscheck-sync-test-$$-XXXXXX"
}

test_cleanup() {
    rm -rf /tmp/crosscheck-sync-test-$$-* 2>/dev/null || true
}
trap test_cleanup EXIT

# List of files we expect to be synced (from the script)
EXPECTED_FILES=(
  "scripts/request-pr-reviewer.sh"
  "scripts/sync-crosscheck-mirrors.sh"
  "claude/scripts/sync-crosscheck-mirrors.sh"
  "codex/scripts/sync-crosscheck-mirrors.sh"
  "claude/scripts/request-pr-reviewer.sh"
  "codex/scripts/request-pr-reviewer.sh"
  "skill-sources/submit-pr.md"
  "claude/skill-sources/submit-pr.md"
  "codex/skill-sources/submit-pr.md"
  "codex/skills/submit-pr/SKILL.md"
)

# Scripts that should be executable
EXECUTABLE_FILES=(
    "scripts/sync-crosscheck-mirrors.sh"
    "claude/scripts/sync-crosscheck-mirrors.sh"
    "codex/scripts/sync-crosscheck-mirrors.sh"
    "scripts/request-pr-reviewer.sh"
    "claude/scripts/request-pr-reviewer.sh"
    "codex/scripts/request-pr-reviewer.sh"
)

test_basic_sync() {
    echo "📋 Testing basic sync..."
    local target_dir
    target_dir="$(create_temp_dir)"

    # Run the script
    "$TARGET_SCRIPT" --target "$target_dir" > /dev/null

    local missing=0
    for rel in "${EXPECTED_FILES[@]}"; do
        if [ ! -f "$target_dir/$rel" ]; then
            missing=1
            echo "   ❌ Missing: $rel"
            break
        fi
    done

    if [ "$missing" -eq 0 ]; then
        pass "Files copied correctly"
    else
        fail "Not all files were copied"
    fi

    local exec_missing=0
    for rel in "${EXECUTABLE_FILES[@]}"; do
        if [ ! -x "$target_dir/$rel" ]; then
            exec_missing=1
            echo "   ❌ Not executable: $rel"
            break
        fi
    done

    if [ "$exec_missing" -eq 0 ]; then
        pass "Executable permissions set correctly"
    else
        fail "Executable permissions not set on all scripts"
    fi
}

test_verify_match() {
    echo "📋 Testing verify mode (match)..."
    local target_dir
    target_dir="$(create_temp_dir)"

    # First sync to get a matching state
    "$TARGET_SCRIPT" --target "$target_dir" > /dev/null

    # Now verify
    local output
    output=$("$TARGET_SCRIPT" --target "$target_dir" --verify)

    if echo "$output" | grep -q "✅ Match"; then
        pass "Verify mode detects matches"
    else
        fail "Verify mode failed to detect matches"
    fi

    if echo "$output" | grep -q "⚠️  Drift:" || echo "$output" | grep -q "❌ Missing mirror file:"; then
        fail "Verify mode incorrectly reported drift or missing files on a fresh sync"
    else
        pass "Verify mode has no false positives"
    fi
}

test_verify_drift() {
    echo "📋 Testing verify mode (drift & missing)..."
    local target_dir
    target_dir="$(create_temp_dir)"

    # Sync first
    "$TARGET_SCRIPT" --target "$target_dir" > /dev/null

    # Introduce drift
    echo "drift" >> "$target_dir/scripts/request-pr-reviewer.sh"
    # Remove a file to test missing
    rm "$target_dir/claude/scripts/sync-crosscheck-mirrors.sh"

    local output
    output=$("$TARGET_SCRIPT" --target "$target_dir" --verify) || true

    if echo "$output" | grep -q "⚠️  Drift: scripts/request-pr-reviewer.sh"; then
        pass "Verify mode detects drift"
    else
        fail "Verify mode failed to detect drift"
    fi

    if echo "$output" | grep -q "❌ Missing mirror file: $target_dir/claude/scripts/sync-crosscheck-mirrors.sh"; then
        pass "Verify mode detects missing files"
    else
        fail "Verify mode failed to detect missing files"
    fi
}

test_env_vars() {
    echo "📋 Testing environment variables handling..."
    local target_dir1
    target_dir1="$(create_temp_dir)"
    local target_dir2
    target_dir2="$(create_temp_dir)"

    # Run the script with NO arguments (should use env vars)
    # We must mock HOME so we don't sync to the actual ~/.crosscheck or ~/.claude/CrossCheck
    # during tests!
    local mock_home
    mock_home="$(create_temp_dir)"

    # We want to use env command to override HOME for the script execution only
    env HOME="$mock_home" CROSSCHECK_MIRROR_PATHS="$target_dir1" "$TARGET_SCRIPT" > /dev/null

    if [ -f "$target_dir1/scripts/sync-crosscheck-mirrors.sh" ]; then
        pass "CROSSCHECK_MIRROR_PATHS works"
    else
        fail "CROSSCHECK_MIRROR_PATHS failed"
    fi

    # Test CROSSCHECK_INCLUDE_NOTACTIVE
    local notactive_dir="$mock_home/Documents/Developer/NotActive/Project1"
    mkdir -p "$notactive_dir/CrossCheck"

    env HOME="$mock_home" CROSSCHECK_INCLUDE_NOTACTIVE=1 "$TARGET_SCRIPT" > /dev/null

    if [ -f "$notactive_dir/CrossCheck/scripts/sync-crosscheck-mirrors.sh" ]; then
        pass "CROSSCHECK_INCLUDE_NOTACTIVE works"
    else
        fail "CROSSCHECK_INCLUDE_NOTACTIVE failed"
    fi

    # Test that without it, NotActive is NOT synced
    rm -rf "$notactive_dir/CrossCheck/scripts"
    env HOME="$mock_home" CROSSCHECK_INCLUDE_NOTACTIVE=0 "$TARGET_SCRIPT" > /dev/null

    if [ ! -f "$notactive_dir/CrossCheck/scripts/sync-crosscheck-mirrors.sh" ]; then
        pass "CROSSCHECK_INCLUDE_NOTACTIVE=0 respects disabling"
    else
        fail "CROSSCHECK_INCLUDE_NOTACTIVE=0 synced anyway. File exists."
    fi
}

test_basic_sync
test_verify_match
test_verify_drift
test_env_vars

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests completed ($PASSED passed)"
else
    echo "❌ $FAILED/$TOTAL tests failed"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Explicit exit via exit code calculation
[ "$FAILED" -eq 0 ]
