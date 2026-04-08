#!/bin/bash
# Test script to verify scan-leaks.sh utility functions
# Tests is_known_fp and filter_false_positives

set -e

# Determine script directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$DIR/scan-leaks.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "❌ Error: scan-leaks.sh not found at $TARGET_SCRIPT"
    exit 1
fi

echo "🧪 scan-leaks.sh Utility Functions Test Suite"
echo "=========================================="
echo ""

PASSED=0
FAILED=0

# Source the utility functions
# shellcheck source=./scan-leaks.sh
source "$TARGET_SCRIPT"

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

# ============================================================
# is_known_fp
# ============================================================
echo "📋 Category: is_known_fp"
echo ""

test_known_fps() {
    local known=(
        "AKIAIOSFODNN7EXAMPLE"
        "sk-proj-abcdef"
        "sk-proj-abc123"
        "sk-proj-test"
        "sk-proj-xxxx"
        "sk-ant-xxxx"
        "sk_live_xxxx"
        "ghp_xxxx"
    )

    for token in "${known[@]}"; do
        if is_known_fp "$token"; then
            pass "is_known_fp correctly identified $token"
        else
            fail "is_known_fp failed to identify $token"
        fi
    done
}

test_unknown_tokens() {
    local unknown=(
        "AKIAIOSFODNN7EXAMPL" # Too short
        "sk-proj-real123"
        "sk-ant-real456"
        "ghp_real789"
        ""
        "something-else"
    )

    for token in "${unknown[@]}"; do
        if ! is_known_fp "$token"; then
            pass "is_known_fp correctly rejected $token"
        else
            fail "is_known_fp incorrectly accepted $token"
        fi
    done
}

test_known_fps
test_unknown_tokens
echo ""

# ============================================================
# filter_false_positives
# ============================================================
echo "📋 Category: filter_false_positives"
echo ""

test_filter_known_fp() {
    local input="Found key: AKIAIOSFODNN7EXAMPLE"
    local output
    output=$(echo "$input" | filter_false_positives)
    if [ -z "$output" ]; then
        pass "filter_false_positives filtered out known false positive"
    else
        fail "filter_false_positives failed to filter known false positive. Output: $output"
    fi
}

test_keep_real_secret() {
    local input="Found real key: sk-proj-ActuallyARealSecretKey12345"
    local output
    output=$(echo "$input" | filter_false_positives)
    if [ "$output" = "$input" ]; then
        pass "filter_false_positives kept real secret"
    else
        fail "filter_false_positives incorrectly filtered real secret. Output: $output"
    fi
}

test_mixed_line() {
    # Line containing both a false positive and a real secret should be kept
    local input="Example: sk-proj-abcdef, Real: sk-proj-ActuallyARealSecretKey12345"
    local output
    output=$(echo "$input" | filter_false_positives)
    if [ "$output" = "$input" ]; then
        pass "filter_false_positives kept line with both FP and real secret"
    else
        fail "filter_false_positives incorrectly filtered mixed line. Output: $output"
    fi
}

test_filter_known_fp
test_keep_real_secret
test_mixed_line
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
