#!/bin/bash
# Test script for utility functions in scripts/fix-timestamps.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/fix-timestamps.sh"

PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
    echo "     Expected content:"
    echo "$2" | sed 's/^/     /'
    echo "     Actual content:"
    cat "$3" | sed 's/^/     /'
}

# Helper to create a test file
create_test_file() {
    local file="$1"
    shift
    printf "%s\n" "$@" > "$file"
}

# Assert file content matches exactly (including newlines)
assert_file_content() {
    local file="$1"
    local expected="$2"
    local msg="$3"
    local actual
    actual=$(cat "$file")
    if [ "$actual" = "$expected" ]; then
        pass "$msg"
    else
        fail "$msg" "$expected" "$file"
    fi
}

echo "🧪 Testing fix-timestamps.sh utility functions"
echo "============================================="
echo ""

TEST_FILE=$(mktemp)
TMPFILES+=("$TEST_FILE")

# ============================================================
# inject_after_line
# ============================================================
echo "📋 Function: inject_after_line"

# Test 1: Inject after line 1
create_test_file "$TEST_FILE" "Line 1" "Line 2" "Line 3"
inject_after_line "$TEST_FILE" 1 "Injected"
EXPECTED=$(printf "Line 1\nInjected\nLine 2\nLine 3")
assert_file_content "$TEST_FILE" "$EXPECTED" "Inject after line 1"

# Test 2: Inject after line 2
create_test_file "$TEST_FILE" "Line 1" "Line 2" "Line 3"
inject_after_line "$TEST_FILE" 2 "Injected"
EXPECTED=$(printf "Line 1\nLine 2\nInjected\nLine 3")
assert_file_content "$TEST_FILE" "$EXPECTED" "Inject after line 2"

# Test 3: Multi-line injection
create_test_file "$TEST_FILE" "Line 1" "Line 2"
inject_after_line "$TEST_FILE" 1 "Multi
Line"
EXPECTED=$(printf "Line 1\nMulti\nLine\nLine 2")
assert_file_content "$TEST_FILE" "$EXPECTED" "Multi-line injection"

echo ""

# ============================================================
# inject_before_line
# ============================================================
echo "📋 Function: inject_before_line"

# Test 4: Inject before line 1
create_test_file "$TEST_FILE" "Line 1" "Line 2"
inject_before_line "$TEST_FILE" 1 "Injected"
EXPECTED=$(printf "Injected\nLine 1\nLine 2")
assert_file_content "$TEST_FILE" "$EXPECTED" "Inject before line 1"

# Test 5: Inject before line 2
create_test_file "$TEST_FILE" "Line 1" "Line 2"
inject_before_line "$TEST_FILE" 2 "Injected"
EXPECTED=$(printf "Line 1\nInjected\nLine 2")
assert_file_content "$TEST_FILE" "$EXPECTED" "Inject before line 2"

echo ""

# ============================================================
# prepend_to_file
# ============================================================
echo "📋 Function: prepend_to_file"

# Test 6: Prepend to file
create_test_file "$TEST_FILE" "Line 1" "Line 2"
prepend_to_file "$TEST_FILE" "Prepended"
EXPECTED=$(printf "Prepended\n\nLine 1\nLine 2")
assert_file_content "$TEST_FILE" "$EXPECTED" "Prepend to file"

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

# Cleanup
for f in "${TMPFILES[@]}"; do rm -f "$f"; done

[ "$FAILED" -eq 0 ]
