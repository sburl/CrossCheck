#!/bin/bash
# Test script to verify fix-timestamps.sh utility functions
# Tests inject_before_line, inject_after_line, prepend_to_file

set -e

# Derive CrossCheck directory from script location (env var overrides)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

if [ ! -f "$CROSSCHECK_DIR/scripts/fix-timestamps.sh" ]; then
    echo "❌ Error: fix-timestamps.sh not found at $CROSSCHECK_DIR/scripts/fix-timestamps.sh"
    exit 1
fi

echo "🧪 Timestamp Utility Functions Test Suite"
echo "========================================="
echo ""

PASSED=0
FAILED=0
TEST_DIR=""

# Cleanup function — remove all test directories from this run (keyed by PID)
cleanup() {
    rm -rf /tmp/timestamp-utils-test-*-$$ 2>/dev/null || true
}
trap cleanup EXIT

# Source the utility functions (the script should be wrapped in a main guard)
source "$CROSSCHECK_DIR/scripts/fix-timestamps.sh"

# fix-timestamps.sh sets its own EXIT trap which overwrites ours.
# We must re-establish a combined trap to ensure both cleanups run.
trap 'cleanup; cleanup_tmpfiles' EXIT

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

setup_test_file() {
    local name="$1"
    TEST_DIR="/tmp/timestamp-utils-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"

    # Generate content
    cat > "$TEST_DIR/test.md"

    echo "$TEST_DIR/test.md"
}

# ============================================================
# inject_before_line
# ============================================================
echo "📋 Category: inject_before_line"
echo ""

test_inject_before_first_line() {
    local file
    file=$(setup_test_file "inject_before_first" << 'EOF'
Line 1
Line 2
EOF
)
    inject_before_line "$file" 1 "INJECTED"

    # grep -z with string patterns matches entire string with null bytes. But here we have normal files.
    # We can use tr to compare.
    actual=$(cat "$file")
    expected=$(printf 'INJECTED\n\nLine 1\nLine 2')
    if [ "$actual" = "$expected" ]; then
        pass "Inject before line 1 works correctly"
    else
        fail "Inject before line 1 failed. Actual content:"
        cat "$file" | sed 's/^/    /'
        echo "    --- HEX ---"
        od -c "$file" | sed 's/^/    /'
    fi
}

test_inject_before_middle_line() {
    local file
    file=$(setup_test_file "inject_before_middle" << 'EOF'
Line 1
Line 2
Line 3
EOF
)
    inject_before_line "$file" 2 "INJECTED"

    actual=$(cat "$file")
    expected=$(printf 'Line 1\nINJECTED\n\nLine 2\nLine 3')
    if [ "$actual" = "$expected" ]; then
        pass "Inject before middle line works correctly"
    else
        fail "Inject before middle line failed. Actual content:"
        cat "$file" | sed 's/^/    /'
        echo "    --- HEX ---"
        od -c "$file" | sed 's/^/    /'
    fi
}

test_inject_before_last_line() {
    local file
    file=$(setup_test_file "inject_before_last" << 'EOF'
Line 1
Line 2
EOF
)
    inject_before_line "$file" 2 "INJECTED"

    actual=$(cat "$file")
    expected=$(printf 'Line 1\nINJECTED\n\nLine 2')
    if [ "$actual" = "$expected" ]; then
        pass "Inject before last line works correctly"
    else
        fail "Inject before last line failed. Actual content:"
        cat "$file" | sed 's/^/    /'
        echo "    --- HEX ---"
        od -c "$file" | sed 's/^/    /'
    fi
}

test_inject_before_single_line_file() {
    local file
    file=$(setup_test_file "inject_before_single" << 'EOF'
Line 1
EOF
)
    inject_before_line "$file" 1 "INJECTED"

    actual=$(cat "$file")
    expected=$(printf 'INJECTED\n\nLine 1')
    if [ "$actual" = "$expected" ]; then
        pass "Inject before line 1 in single-line file works"
    else
        fail "Inject before line 1 in single-line file failed. Actual content:"
        cat "$file" | sed 's/^/    /'
        echo "    --- HEX ---"
        od -c "$file" | sed 's/^/    /'
    fi
}

test_inject_before_first_line
test_inject_before_middle_line
test_inject_before_last_line
test_inject_before_single_line_file
echo ""

# ============================================================
# Summary
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests completed ($PASSED passed)"
else
    echo "❌ $FAILED/$TOTAL tests failed"
    exit 1
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
