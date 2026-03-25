#!/bin/bash
# Test script to verify the confirm() function in install scripts

set -e

# Derive CrossCheck directory from script location
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/scripts/install-git-hooks.sh"

# Test setup
PASSED=0
FAILED=0
TEST_TTY_FILE="/tmp/test_tty_$$"

cleanup() {
    rm -f "$TEST_TTY_FILE"
}
trap cleanup EXIT

# Setup mock TTY
export CONFIRM_TTY="$TEST_TTY_FILE"

# Source the script to get the confirm() function
# The execution guard prevents main() from running
source "$INSTALL_SCRIPT"

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

run_confirm_test() {
    local test_name="$1"
    local input_char="$2"
    local default_arg="$3"
    local is_yes="$4"
    local expected_result="$5" # 0 for true/yes, 1 for false/no

    echo "$input_char" > "$TEST_TTY_FILE"

    # Temporarily disable set -e for the test
    set +e
    YES=$is_yes
    confirm "Test prompt: " "$default_arg" >/dev/null
    local actual_result=$?
    set -e

    if [ "$actual_result" -eq "$expected_result" ]; then
        pass "$test_name"
    else
        fail "$test_name (Expected $expected_result, got $actual_result)"
    fi
}

echo "🧪 confirm() Function Test Suite"
echo "================================="
echo ""

echo "📋 Testing Auto-accept (--yes)"
run_confirm_test "YES=true bypasses prompt and returns 0" "n" "N" true 0
echo ""

echo "📋 Testing Default=N (No)"
run_confirm_test "Input 'Y' returns 0 (Yes)" "Y" "N" false 0
run_confirm_test "Input 'y' returns 0 (Yes)" "y" "N" false 0
run_confirm_test "Input 'N' returns 1 (No)" "N" "N" false 1
run_confirm_test "Input 'n' returns 1 (No)" "n" "N" false 1
run_confirm_test "Empty input returns 1 (No, default)" "" "N" false 1
run_confirm_test "Random input 'x' returns 1 (No)" "x" "N" false 1
echo ""

echo "📋 Testing Default=Y (Yes)"
run_confirm_test "Input 'N' returns 1 (No)" "N" "Y" false 1
run_confirm_test "Input 'n' returns 1 (No)" "n" "Y" false 1
run_confirm_test "Input 'Y' returns 0 (Yes)" "Y" "Y" false 0
run_confirm_test "Input 'y' returns 0 (Yes)" "y" "Y" false 0
run_confirm_test "Empty input returns 0 (Yes, default)" "" "Y" false 0
run_confirm_test "Random input 'x' returns 0 (Yes)" "x" "Y" false 0
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests passed"
    exit 0
else
    echo "❌ $FAILED/$TOTAL tests failed"
    exit 1
fi
