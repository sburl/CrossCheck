#!/bin/bash
# Test for resolve_map_reviewer function in request-pr-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/request-pr-reviewer.sh"

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

test_resolve_map_reviewer() {
    echo "📋 Testing resolve_map_reviewer..."

    # Test arrow separator
    local map="bot-test->human-test"
    local result
    result="$(resolve_map_reviewer "$map" "bot-test")"
    if [ "$result" = "human-test" ]; then
        pass "Arrow separator (->)"
    else
        fail "Arrow separator (->). Expected 'human-test', got '$result'"
    fi

    # Test equals separator
    map="bot-test=human-test"
    result="$(resolve_map_reviewer "$map" "bot-test")"
    if [ "$result" = "human-test" ]; then
        pass "Equals separator (=)"
    else
        fail "Equals separator (=). Expected 'human-test', got '$result'"
    fi

    # Test colon separator
    map="bot-test:human-test"
    result="$(resolve_map_reviewer "$map" "bot-test")"
    if [ "$result" = "human-test" ]; then
        pass "Colon separator (:)"
    else
        fail "Colon separator (:). Expected 'human-test', got '$result'"
    fi

    # Test whitespaces
    map="  bot-test  :  human-test  "
    result="$(resolve_map_reviewer "$map" "bot-test")"
    if [ "$result" = "human-test" ]; then
        pass "Whitespace handling"
    else
        fail "Whitespace handling. Expected 'human-test', got '$result'"
    fi

    # Test comments
    map=$(printf "# comment\n\nbot-test:human-test\n# another comment")
    result="$(resolve_map_reviewer "$map" "bot-test")"
    if [ "$result" = "human-test" ]; then
        pass "Comment and empty line handling"
    else
        fail "Comment and empty line handling. Expected 'human-test', got '$result'"
    fi

    # Test unmapped actor
    map="bot-test:human-test"
    if resolve_map_reviewer "$map" "other-bot" > /dev/null; then
        fail "Unmapped actor should return 1"
    else
        pass "Unmapped actor returns error code"
    fi

    # Test multiline config with multiple bots
    map=$(printf "bot1:human1\nbot2:human2\nbot3:human3")
    result="$(resolve_map_reviewer "$map" "bot2")"
    if [ "$result" = "human2" ]; then
        pass "Multiple mapping entries"
    else
        fail "Multiple mapping entries. Expected 'human2', got '$result'"
    fi
}

test_resolve_map_reviewer

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
