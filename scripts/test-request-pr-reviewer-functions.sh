#!/bin/bash
# Test script for functions in request-pr-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/request-pr-reviewer.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "❌ Error: $TARGET_SCRIPT not found"
    exit 1
fi

# Source the target script to access functions
# shellcheck source=scripts/request-pr-reviewer.sh
source "$TARGET_SCRIPT"

PASSED=0
FAILED=0

# Helper to run a test
run_test() {
    local test_name="$1"
    local input="$2"
    local expected="$3"

    local actual
    actual="$(trim "$input")"

    if [ "$actual" == "$expected" ]; then
        echo "✅ PASS: $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: '$expected'"
        echo "   Actual:   '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

echo "🧪 Running tests for trim() function in request-pr-reviewer.sh"
echo "==============================================================="

run_test "Leading whitespace" "  hello" "hello"
run_test "Trailing whitespace" "world  " "world"
run_test "Leading and trailing whitespace" "  trim me  " "trim me"
run_test "Multiple words with internal spaces" "  a b  c  " "a b  c"
run_test "No whitespace" "nospace" "nospace"
run_test "Empty string" "" ""
run_test "Tabs and newlines" "$(printf '\t\n hello world \n\t')" "hello world"

echo "==============================================================="
echo "Tests Passed: $PASSED"
echo "Tests Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0