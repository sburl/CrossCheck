#!/bin/bash
# Test script to verify fix-timestamps utility functions
# Tests inject_after_line and other helper functions

set -e

# Derive CrossCheck directory from script location
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

# Source the functions without executing the main script body
source "$CROSSCHECK_DIR/scripts/fix-timestamps.sh"

echo "🧪 Fix-Timestamps Functions Test Suite"
echo "======================================="
echo ""

PASSED=0
FAILED=0
TEST_DIR=""

cleanup() {
    rm -rf /tmp/fix-timestamps-test-*-$$ 2>/dev/null || true
}
trap cleanup EXIT

setup_test_dir() {
    local name="$1"
    TEST_DIR="/tmp/fix-timestamps-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
}

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

# ============================================================
# inject_after_line
# ============================================================
echo "📋 Category: inject_after_line"
echo ""

test_inject_single_line() {
    setup_test_dir "inject-single"
    local test_file="$TEST_DIR/test.md"

    cat > "$test_file" << 'EOF'
Line 1
Line 2
Line 3
EOF

    inject_after_line "$test_file" 2 "Inserted Line"

    local expected
    expected="$(printf "Line 1\nLine 2\n\nInserted Line\nLine 3\n")"
    local actual
    actual="$(cat "$test_file")"

    if [ "$actual" = "$expected" ]; then
        pass "Injects a single line correctly"
    else
        fail "Failed to inject single line correctly. Expected '$expected', got '$actual'"
    fi
}

test_inject_multi_line() {
    setup_test_dir "inject-multi"
    local test_file="$TEST_DIR/test.md"

    cat > "$test_file" << 'EOF'
Line 1
Line 2
Line 3
EOF

    local multi_line_text
    multi_line_text="$(printf "Inserted Line 1\nInserted Line 2")"

    inject_after_line "$test_file" 1 "$multi_line_text"

    local expected
    expected="$(printf "Line 1\n\nInserted Line 1\nInserted Line 2\nLine 2\nLine 3\n")"
    local actual
    actual="$(cat "$test_file")"

    if [ "$actual" = "$expected" ]; then
        pass "Injects multi-line text correctly"
    else
        fail "Failed to inject multi-line text correctly. Expected '$expected', got '$actual'"
    fi
}

test_inject_end_of_file() {
    setup_test_dir "inject-eof"
    local test_file="$TEST_DIR/test.md"

    cat > "$test_file" << 'EOF'
Line 1
Line 2
EOF

    inject_after_line "$test_file" 2 "Inserted at end"

    local expected
    expected="$(printf "Line 1\nLine 2\n\nInserted at end\n")"
    local actual
    actual="$(cat "$test_file")"

    if [ "$actual" = "$expected" ]; then
        pass "Injects correctly after the last line"
    else
        fail "Failed to inject after the last line. Expected '$expected', got '$actual'"
    fi
}

test_inject_single_line
test_inject_multi_line
test_inject_end_of_file
echo ""

# ============================================================
# Summary
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests passed"
else
    echo "❌ $FAILED/$TOTAL tests failed"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAILED" -eq 0 ]
