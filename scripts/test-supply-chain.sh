#!/bin/bash
# Test script for supply chain protection (scan-supply-chain.sh)
# Tests blocklist, version pinning, lock file enforcement, and age quarantine.

set -e

# Derive CrossCheck directory from script location
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"
SCANNER="$CROSSCHECK_DIR/scripts/scan-supply-chain.sh"
BLOCKLIST="$CROSSCHECK_DIR/scripts/supply-chain-blocklist.txt"

if [ ! -f "$SCANNER" ]; then
    echo "❌ Error: scan-supply-chain.sh not found at $SCANNER"
    exit 1
fi

echo "🧪 Supply Chain Protection Test Suite"
echo "======================================"
echo ""

PASSED=0
FAILED=0
SKIPPED=0
TEST_DIR=""

# Cleanup function
cleanup() {
    rm -rf /tmp/supply-chain-test-*-$$ 2>/dev/null || true
}
trap cleanup EXIT

# Create a fresh test directory with a given name
setup_test_dir() {
    local name="$1"
    TEST_DIR="/tmp/supply-chain-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
}

pass() {
    PASSED=$((PASSED + 1))
    echo "  ✅ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  ❌ FAIL: $1"
}

skip() {
    SKIPPED=$((SKIPPED + 1))
    echo "  ⏭️  SKIP: $1"
}

# ============================================================
# Category 1: Blocklist Detection
# ============================================================
echo "📋 Category: Blocklist detection"
echo ""

test_blocklist_npm_blocks() {
    setup_test_dir "blocklist-npm"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "plain-crypto-js": "4.2.1"
  }
}
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "Blocklisted npm package (plain-crypto-js) triggers exit 2"
    else
        fail "Blocklisted npm package should exit 2, got $exit_code"
    fi
}

test_blocklist_pip_blocks() {
    setup_test_dir "blocklist-pip"
    cat > requirements.txt <<'EOF'
ctx==2.0.0
requests==2.31.0
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "Blocklisted pip package (ctx) triggers exit 2"
    else
        fail "Blocklisted pip package should exit 2, got $exit_code"
    fi
}

test_blocklist_gem_blocks() {
    setup_test_dir "blocklist-gem"
    cat > Gemfile <<'EOF'
source "https://rubygems.org"
gem "rest-client", "1.6.13"
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "Blocklisted gem (rest-client) triggers exit 2"
    else
        fail "Blocklisted gem should exit 2, got $exit_code"
    fi
}

test_blocklist_lockfile_catches_transitive() {
    setup_test_dir "blocklist-lockfile"
    # package.json is clean, but lock file has the malicious transitive dep
    cat > package.json <<'EOF'
{
  "dependencies": {
    "axios": "1.14.1"
  }
}
EOF
    cat > package-lock.json <<'EOF'
{
  "packages": {
    "node_modules/plain-crypto-js": {
      "version": "4.2.1"
    }
  }
}
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "Blocklisted transitive dep in lock file triggers exit 2"
    else
        fail "Blocklisted transitive dep in lock file should exit 2, got $exit_code"
    fi
}

test_clean_package_passes() {
    setup_test_dir "blocklist-clean"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2",
    "lodash": "4.17.21"
  }
}
EOF
    # Also add .npmrc to avoid pinning warnings affecting exit code
    echo "save-exact=true" > .npmrc
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "Clean package.json passes (exit 0)"
    else
        fail "Clean package.json should pass, got exit $exit_code"
    fi
}

test_blocklist_npm_blocks
test_blocklist_pip_blocks
test_blocklist_gem_blocks
test_blocklist_lockfile_catches_transitive
test_clean_package_passes
echo ""

# ============================================================
# Category 2: Version Pinning Detection
# ============================================================
echo "📋 Category: Version pinning detection"
echo ""

test_pinned_versions_pass() {
    setup_test_dir "pinning-ok"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2",
    "lodash": "4.17.21"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "Pinned npm versions pass"
    else
        fail "Pinned npm versions should pass, got exit $exit_code"
    fi
}

test_caret_range_warns() {
    setup_test_dir "pinning-caret"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "axios": "^1.14.0"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-commit 2>&1) || exit_code=$?
    if [ "$exit_code" -ge 1 ] && echo "$output" | grep -qi "unpinned"; then
        pass "Caret range (^) triggers unpinned warning"
    else
        fail "Caret range should trigger warning (exit=$exit_code)"
    fi
}

test_tilde_range_warns() {
    setup_test_dir "pinning-tilde"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "lodash": "~4.17.0"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-commit 2>&1) || exit_code=$?
    if [ "$exit_code" -ge 1 ] && echo "$output" | grep -qi "unpinned"; then
        pass "Tilde range (~) triggers unpinned warning"
    else
        fail "Tilde range should trigger warning (exit=$exit_code)"
    fi
}

test_pip_unpinned_warns() {
    setup_test_dir "pinning-pip"
    cat > requirements.txt <<'EOF'
requests>=2.28.0
flask
numpy==1.24.0
EOF
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-commit 2>&1) || exit_code=$?
    if [ "$exit_code" -ge 1 ] && echo "$output" | grep -qi "unpinned"; then
        pass "Unpinned pip versions (>= and bare) trigger warning"
    else
        fail "Unpinned pip versions should trigger warning (exit=$exit_code)"
    fi
}

test_npmrc_missing_warns() {
    setup_test_dir "pinning-no-npmrc"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2"
  }
}
EOF
    # No .npmrc file
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-commit 2>&1) || exit_code=$?
    if echo "$output" | grep -qi "save-exact\|npmrc"; then
        pass "Missing .npmrc triggers save-exact warning"
    else
        fail "Missing .npmrc should trigger warning"
    fi
}

test_pinned_versions_pass
test_caret_range_warns
test_tilde_range_warns
test_pip_unpinned_warns
test_npmrc_missing_warns
echo ""

# ============================================================
# Category 3: Lock File Enforcement
# ============================================================
echo "📋 Category: Lock file enforcement"
echo ""

test_lockfile_missing_warns() {
    setup_test_dir "lockfile-missing"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    # No package-lock.json, yarn.lock, or pnpm-lock.yaml
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-push 2>&1) || exit_code=$?
    if echo "$output" | grep -qi "lock file"; then
        pass "Missing lock file triggers warning"
    else
        fail "Missing lock file should trigger warning"
    fi
}

test_lockfile_present_passes() {
    setup_test_dir "lockfile-ok"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    echo '{"lockfileVersion": 3}' > package-lock.json
    local exit_code=0
    local output
    output=$(SUPPLY_CHAIN_SKIP_AGE=1 bash "$SCANNER" --pre-push 2>&1) || exit_code=$?
    if echo "$output" | grep -q "Lock files present"; then
        pass "Present lock file passes check"
    else
        fail "Present lock file should pass (exit=$exit_code)"
    fi
}

test_gemfile_lock_missing_warns() {
    setup_test_dir "lockfile-gem"
    cat > Gemfile <<'EOF'
source "https://rubygems.org"
gem "rails", "7.1.0"
EOF
    # No Gemfile.lock
    local exit_code=0
    local output
    output=$(bash "$SCANNER" --pre-push 2>&1) || exit_code=$?
    if echo "$output" | grep -qi "Gemfile.lock"; then
        pass "Missing Gemfile.lock triggers warning"
    else
        fail "Missing Gemfile.lock should trigger warning"
    fi
}

test_lockfile_missing_warns
test_lockfile_present_passes
test_gemfile_lock_missing_warns
echo ""

# ============================================================
# Category 4: Age Quarantine
# ============================================================
echo "📋 Category: Age quarantine"
echo ""

test_age_skip_env() {
    setup_test_dir "age-skip"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "express": "4.18.2"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    echo '{}' > package-lock.json
    local output
    output=$(SUPPLY_CHAIN_SKIP_AGE=1 bash "$SCANNER" --pre-push 2>&1) || true
    if echo "$output" | grep -q "skipped.*SUPPLY_CHAIN_SKIP_AGE"; then
        pass "SUPPLY_CHAIN_SKIP_AGE=1 skips age check"
    else
        fail "SUPPLY_CHAIN_SKIP_AGE=1 should skip age check"
    fi
}

test_age_old_package_passes() {
    # This test requires network — skip if offline
    if ! curl -s --max-time 3 -o /dev/null "https://registry.npmjs.org" 2>/dev/null; then
        skip "Age check for old package (offline)"
        return
    fi

    setup_test_dir "age-old-pkg"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "lodash": "4.17.21"
  }
}
EOF
    echo "save-exact=true" > .npmrc
    echo '{}' > package-lock.json
    local exit_code=0
    bash "$SCANNER" --pre-push > /dev/null 2>&1 || exit_code=$?
    # lodash 4.17.21 was published years ago — should pass
    if [ "$exit_code" -eq 0 ]; then
        pass "Old package (lodash@4.17.21) passes age quarantine"
    else
        fail "Old package should pass age quarantine, got exit $exit_code"
    fi
}

test_age_skip_env
test_age_old_package_passes
echo ""

# ============================================================
# Category 5: Ecosystem Detection
# ============================================================
echo "📋 Category: Ecosystem detection"
echo ""

test_no_ecosystem_exits_clean() {
    setup_test_dir "no-ecosystem"
    # Empty directory — no package files
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "No ecosystem files → clean exit"
    else
        fail "No ecosystem files should exit 0, got $exit_code"
    fi
}

test_multi_ecosystem_detected() {
    setup_test_dir "multi-eco"
    cat > package.json <<'EOF'
{"dependencies": {"express": "4.18.2"}}
EOF
    echo "save-exact=true" > .npmrc
    cat > requirements.txt <<'EOF'
flask==3.0.0
EOF
    local output
    output=$(bash "$SCANNER" --pre-commit 2>&1) || true
    if echo "$output" | grep -q "npm" && echo "$output" | grep -q "pip"; then
        pass "Multiple ecosystems (npm + pip) detected"
    else
        fail "Should detect both npm and pip ecosystems"
    fi
}

test_no_ecosystem_exits_clean
test_multi_ecosystem_detected
echo ""

# ============================================================
# Category 6: Blocklist File Integrity
# ============================================================
echo "📋 Category: Blocklist file integrity"
echo ""

test_blocklist_parseable() {
    if [ ! -f "$BLOCKLIST" ]; then
        fail "Blocklist file not found at $BLOCKLIST"
        return
    fi
    # Check that every non-comment, non-blank line has ecosystem:package format
    local bad_lines
    bad_lines=$(grep -vE '^\s*#|^\s*$' "$BLOCKLIST" | grep -vE '^[a-z]+:[a-zA-Z0-9._-]+' || true)
    if [ -z "$bad_lines" ]; then
        pass "Blocklist file is properly formatted"
    else
        fail "Blocklist has malformed lines: $bad_lines"
    fi
}

test_blocklist_has_entries() {
    local count
    count=$(grep -cvE '^\s*#|^\s*$' "$BLOCKLIST" 2>/dev/null || echo "0")
    if [ "$count" -gt 0 ]; then
        pass "Blocklist contains $count entries"
    else
        fail "Blocklist should have at least one entry"
    fi
}

test_blocklist_parseable
test_blocklist_has_entries
echo ""

# ============================================================
# Category 7: Exit Code Conventions
# ============================================================
echo "📋 Category: Exit code conventions"
echo ""

test_soft_fail_always_zero() {
    setup_test_dir "soft-fail"
    cat > package.json <<'EOF'
{
  "dependencies": {
    "plain-crypto-js": "4.2.1"
  }
}
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit --soft-fail > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "--soft-fail exits 0 even with malicious package"
    else
        fail "--soft-fail should exit 0, got $exit_code"
    fi
}

test_malicious_beats_warning() {
    setup_test_dir "exit-priority"
    # Both malicious (exit 2) and unpinned (exit 1) — should get 2
    cat > package.json <<'EOF'
{
  "dependencies": {
    "plain-crypto-js": "4.2.1",
    "axios": "^1.14.0"
  }
}
EOF
    local exit_code=0
    bash "$SCANNER" --pre-commit > /dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "Malicious exit code (2) takes priority over warning (1)"
    else
        fail "Should get exit 2 (malicious), got $exit_code"
    fi
}

test_soft_fail_always_zero
test_malicious_beats_warning
echo ""

# ============================================================
# Summary
# ============================================================
echo "======================================"
TOTAL=$((PASSED + FAILED + SKIPPED))
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped (of $TOTAL)"

if [ "$FAILED" -gt 0 ]; then
    echo "❌ Some tests failed"
    exit 1
else
    echo "✅ All tests passed"
    exit 0
fi
