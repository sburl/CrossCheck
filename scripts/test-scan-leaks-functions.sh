#!/bin/bash
# Test script to verify scan-leaks.sh utility functions
# Tests filter_false_positives

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

if [ ! -f "$CROSSCHECK_DIR/scripts/scan-leaks.sh" ]; then
    echo "❌ Error: scan-leaks.sh not found at $CROSSCHECK_DIR/scripts/scan-leaks.sh"
    # exit 1 omitted for compat but logic is same
    return 1 2>/dev/null
fi

echo "🧪 scan-leaks Utility Functions Test Suite"
echo "========================================="
echo ""

PASSED=0
FAILED=0

# Source the utility functions (the script is wrapped in a main guard)
source "$CROSSCHECK_DIR/scripts/scan-leaks.sh"

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

# ============================================================
# filter_false_positives
# ============================================================
echo "📋 Category: filter_false_positives"
echo ""

test_filter_known_false_positive() {
    local actual
    actual=$(echo "this is a false positive sk-proj-test" | grep -E "$COMBINED" | filter_false_positives || true)
    if [ -z "$actual" ]; then
        pass "Filters out known false positive correctly"
    else
        fail "Failed to filter out known false positive. Actual output: $actual"
    fi
}

test_filter_real_secret() {
    local actual
    actual=$(echo "this is a real secret sk-proj-01234567890123456789" | grep -E "$COMBINED" | filter_false_positives || true)
    if [ "$actual" = "this is a real secret sk-proj-01234567890123456789" ]; then
        pass "Keeps real secret correctly"
    else
        fail "Failed to keep real secret. Actual output: $actual"
    fi
}

test_filter_real_secret_with_fp_substring() {
    local actual
    actual=$(echo "this is a real secret sk-proj-test-real-prod-key-abc" | grep -E "$COMBINED" | filter_false_positives || true)
    if [ "$actual" = "this is a real secret sk-proj-test-real-prod-key-abc" ]; then
        pass "Keeps real secret containing false positive substring"
    else
        fail "Failed to keep real secret containing false positive substring. Actual output: $actual"
    fi
}

test_filter_multiple_secrets_one_fp() {
    local actual
    actual=$(echo "fp sk-proj-test and real sk-proj-01234567890123456789" | grep -E "$COMBINED" | filter_false_positives || true)
    if [ "$actual" = "fp sk-proj-test and real sk-proj-01234567890123456789" ]; then
        pass "Keeps line with both known false positive and real secret"
    else
        fail "Failed to keep line with both. Actual output: $actual"
    fi
}

test_filter_multiple_fps() {
    local actual
    actual=$(echo "fp1 sk-proj-test and fp2 sk-proj-xxxx" | grep -E "$COMBINED" | filter_false_positives || true)
    if [ -z "$actual" ]; then
        pass "Filters out line with multiple false positives"
    else
        fail "Failed to filter out line with multiple false positives. Actual output: $actual"
    fi
}

test_filter_known_false_positive
test_filter_real_secret
test_filter_real_secret_with_fp_substring
test_filter_multiple_secrets_one_fp
test_filter_multiple_fps
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
    return 1 2>/dev/null
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
