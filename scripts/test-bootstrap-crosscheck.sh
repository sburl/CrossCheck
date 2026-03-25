#!/bin/bash
# Test script to verify bootstrap-crosscheck.sh behavior, particularly error paths
# like missing dependencies (e.g., jq).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/scripts/bootstrap-crosscheck.sh"

echo "🧪 Bootstrap Script Test Suite"
echo "============================="
echo ""

# Cleanup function
cleanup() {
    echo "  🧹 Cleaning up test directories..."
    rm -rf /tmp/bootstrap-test-* 2>/dev/null || true
}
trap cleanup EXIT

# Test 1: Missing jq dependency
test_missing_jq() {
    echo "📋 Test 1: Missing 'jq' dependency"
    echo "  Should emit warning and skip deny rule sync, but exit successfully"
    echo ""

    cleanup
    local test_dir="/tmp/bootstrap-test-$$"
    mkdir -p "$test_dir/home"
    mkdir -p "$test_dir/bin"
    mkdir -p "$test_dir/repo"

    # We copy the script to a mock repo directory so it runs in traditional mode
    # instead of multi-project mode which tries to write to the parent directory.
    cp "$BOOTSTRAP_SCRIPT" "$test_dir/repo/bootstrap-crosscheck.sh"
    local mock_bootstrap="$test_dir/repo/bootstrap-crosscheck.sh"

    # Create a shadow PATH containing all current binaries except 'jq'
    # This robustly simulates a missing dependency
    for dir in $(echo "$PATH" | tr ':' ' '); do
        if [ -d "$dir" ]; then
            for cmd in "$dir"/*; do
                if [ -f "$cmd" ] && [ -x "$cmd" ]; then
                    local base
                    base=$(basename "$cmd")
                    if [ "$base" != "jq" ]; then
                        # Do not overwrite if multiple directories contain the same binary name
                        if [ ! -e "$test_dir/bin/$base" ]; then
                            ln -s "$cmd" "$test_dir/bin/$base" 2>/dev/null || true
                        fi
                    fi
                fi
            done
        fi
    done

    # Run the bootstrap script in an isolated environment
    local output_file="$test_dir/output.log"

    # We use a subshell to strictly control the environment variables and path
    (
        export HOME="$test_dir/home"
        export PATH="$test_dir/bin"

        # Verify jq is actually missing in this subshell
        if command -v jq >/dev/null 2>&1; then
            echo "  ❌ FATAL: jq is still in PATH ($PATH)"
            exit 1
        fi

        # Run script - it should succeed (set -e is active in this script,
        # but we also explicitly check the exit code)
        # yes n will handle interactive prompts if any.
        yes n 2>/dev/null | bash "$mock_bootstrap" > "$output_file" 2>&1
    )
    local exit_code=$?

    # Verify script exited successfully despite missing jq
    if [ $exit_code -ne 0 ]; then
        echo "  ❌ FAIL: Script failed with exit code $exit_code when jq was missing"
        cat "$output_file"
        return 1
    fi
    echo "  ✅ Script exited successfully (0)"

    # Verify the specific warning message was printed
    if ! grep -q "⚠️  WARNING: 'jq' not found — deny rule sync will be skipped" "$output_file"; then
        echo "  ❌ FAIL: Expected warning message not found in output"
        echo "  --- Output ---"
        cat "$output_file"
        echo "  --------------"
        return 1
    fi
    echo "  ✅ Expected warning message found"

    echo ""
    echo "  ✅ Test 1: PASSED"
    echo ""
}

# Run all tests
main() {
    # Call test functions without || to preserve set -e behavior
    test_missing_jq

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ All bootstrap tests passed!"
    echo ""
    echo "Verified scenarios:"
    echo "  1. Missing jq dependency handles gracefully ✅"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cleanup
}

main
