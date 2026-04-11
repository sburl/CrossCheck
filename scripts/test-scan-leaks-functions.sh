#!/bin/bash
# Test script for functions in scan-leaks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/scan-leaks.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "❌ Error: $TARGET_SCRIPT not found"
    exit 1
fi

# Source the target script to access functions and COMBINED regex
# shellcheck source=scripts/scan-leaks.sh
source "$TARGET_SCRIPT"

PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
    [ -n "${2:-}" ] && echo "     $2"
}

echo "🧪 Running unit tests for scan-leaks.sh functions"
echo "==============================================================="

# ============================================================
# is_known_fp
# ============================================================
echo "📋 Category: is_known_fp"

test_is_known_fp() {
    if is_known_fp "sk-proj-test"; then
        pass "is_known_fp correctly identifies sk-proj-test"
    else
        fail "is_known_fp should identify sk-proj-test as FP"
    fi

    if is_known_fp "AKIAIOSFODNN7EXAMPLE"; then
        pass "is_known_fp correctly identifies AWS example key"
    else
        fail "is_known_fp should identify AKIAIOSFODNN7EXAMPLE as FP"
    fi

    if ! is_known_fp "sk-proj-real-key-1234567890abcdefghij"; then
        pass "is_known_fp correctly identifies real-looking key as NOT FP"
    else
        fail "is_known_fp should NOT identify real-looking key as FP"
    fi
}

test_is_known_fp
echo ""

# ============================================================
# filter_false_positives
# ============================================================
echo "📋 Category: filter_false_positives"

test_filter_false_positives_clean() {
    local input="This line is clean"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ "$actual" == "$input" ]; then
        pass "Clean line is echoed as-is"
    else
        fail "Clean line was modified or filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_real() {
    local input="Here is a real key: sk-proj-real-key-1234567890abcdefghij"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ "$actual" == "$input" ]; then
        pass "Line with real secret is echoed"
    else
        fail "Line with real secret was filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_fp() {
    # Using AKIAIOSFODNN7EXAMPLE because it's long enough to match the regex
    # and is in the known FP list.
    local input="Here is a test key: AKIAIOSFODNN7EXAMPLE"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ -z "$actual" ]; then
        pass "Line with only FP is filtered"
    else
        fail "Line with only FP was not filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_mixed() {
    local input="FP: AKIAIOSFODNN7EXAMPLE and REAL: sk-proj-real-key-1234567890abcdefghij"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ "$actual" == "$input" ]; then
        pass "Line with mixed FP and REAL is echoed"
    else
        fail "Line with mixed FP and REAL was filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_substring() {
    # If sk-proj-test is a prefix/substring of a longer real secret,
    # the real secret should NOT be filtered.
    local input="Key: sk-proj-test-real-prod-key-abc123456789"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ "$actual" == "$input" ]; then
        pass "Long secret containing FP as prefix is NOT filtered"
    else
        fail "Long secret containing FP as prefix was incorrectly filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_multiple_fps() {
    local input="Multiple FPs: AKIAIOSFODNN7EXAMPLE and AKIAIOSFODNN7EXAMPLE"
    local actual
    actual=$(echo "$input" | filter_false_positives)
    if [ -z "$actual" ]; then
        pass "Line with multiple FPs is filtered"
    else
        fail "Line with multiple FPs was not filtered" "Actual: '$actual'"
    fi
}

test_filter_false_positives_clean
test_filter_false_positives_real
test_filter_false_positives_fp
test_filter_false_positives_mixed
test_filter_false_positives_substring
test_filter_false_positives_multiple_fps
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
