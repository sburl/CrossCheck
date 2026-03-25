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

# Source the utility functions (the script is wrapped in a main guard,
# so only function definitions are loaded — no set -e or trap side effects)
source "$CROSSCHECK_DIR/scripts/fix-timestamps.sh"

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
    expected=$(printf 'INJECTED\nLine 1\nLine 2')
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
    expected=$(printf 'Line 1\nINJECTED\nLine 2\nLine 3')
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
    expected=$(printf 'Line 1\nINJECTED\nLine 2')
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
    expected=$(printf 'INJECTED\nLine 1')
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
# inject_after_line
# ============================================================
echo "📋 Category: inject_after_line"
echo ""

test_inject_after_single_line() {
    local file
    file=$(setup_test_file "inject_after_single" << 'EOF'
Line 1
Line 2
Line 3
EOF
)
    inject_after_line "$file" 2 "Inserted Line"

    actual=$(cat "$file")
    expected=$(printf 'Line 1\nLine 2\n\nInserted Line\nLine 3')
    if [ "$actual" = "$expected" ]; then
        pass "Injects a single line after line 2 correctly"
    else
        fail "Failed to inject single line after line 2. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_inject_after_multi_line() {
    local file
    file=$(setup_test_file "inject_after_multi" << 'EOF'
Line 1
Line 2
Line 3
EOF
)
    inject_after_line "$file" 1 "$(printf 'Inserted 1\nInserted 2')"

    actual=$(cat "$file")
    expected=$(printf 'Line 1\n\nInserted 1\nInserted 2\nLine 2\nLine 3')
    if [ "$actual" = "$expected" ]; then
        pass "Injects multi-line text correctly"
    else
        fail "Failed to inject multi-line text. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_inject_after_last_line() {
    local file
    file=$(setup_test_file "inject_after_last" << 'EOF'
Line 1
Line 2
EOF
)
    inject_after_line "$file" 2 "Inserted at end"

    actual=$(cat "$file")
    expected=$(printf 'Line 1\nLine 2\n\nInserted at end')
    if [ "$actual" = "$expected" ]; then
        pass "Injects correctly after the last line"
    else
        fail "Failed to inject after last line. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_inject_after_single_line
test_inject_after_multi_line
test_inject_after_last_line
echo ""

# ============================================================
# prepend_to_file
# ============================================================
echo "📋 Category: prepend_to_file"
echo ""

test_prepend_single_line() {
    local file
    file=$(setup_test_file "prepend_single" << 'EOF'
Line 1
Line 2
EOF
)
    prepend_to_file "$file" "Inserted at top"

    actual=$(cat "$file")
    expected=$(printf 'Inserted at top\n\nLine 1\nLine 2')
    if [ "$actual" = "$expected" ]; then
        pass "Prepends single line correctly"
    else
        fail "Failed to prepend single line. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_prepend_multi_line() {
    local file
    file=$(setup_test_file "prepend_multi" << 'EOF'
Line 1
Line 2
EOF
)
    prepend_to_file "$file" "$(printf 'Inserted 1\nInserted 2')"

    actual=$(cat "$file")
    expected=$(printf 'Inserted 1\nInserted 2\n\nLine 1\nLine 2')
    if [ "$actual" = "$expected" ]; then
        pass "Prepends multi-line text correctly"
    else
        fail "Failed to prepend multi-line text. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_prepend_empty_file() {
    local file
    file=$(setup_test_file "prepend_empty" < /dev/null)
    prepend_to_file "$file" "Inserted at top"

    actual=$(cat "$file")
    # Using printf to preserve exactly what's expected for an empty file, which should be the text plus 2 newlines
    expected=$(printf 'Inserted at top\n\n')
    if [ "$actual" = "$expected" ]; then
        pass "Prepends to empty file correctly"
    else
        fail "Failed to prepend to empty file. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_prepend_single_line_file() {
    local file
    file=$(setup_test_file "prepend_single_file" << 'EOF'
Line 1
EOF
)
    prepend_to_file "$file" "Inserted at top"

    actual=$(cat "$file")
    expected=$(printf 'Inserted at top\n\nLine 1')
    if [ "$actual" = "$expected" ]; then
        pass "Prepends to single-line file correctly"
    else
        fail "Failed to prepend to single-line file. Actual content:"
        cat "$file" | sed 's/^/    /'
    fi
}

test_prepend_single_line
test_prepend_multi_line
test_prepend_empty_file
test_prepend_single_line_file
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
