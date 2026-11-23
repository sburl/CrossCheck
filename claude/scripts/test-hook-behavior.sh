#!/bin/bash
# Test script to verify hook BEHAVIOR (enforcement logic)
# Complements test-hook-installation.sh which tests installation scenarios
#
# Tests that hooks correctly block/allow/warn in the right situations.

set -e

# Derive CrossCheck directory from script location (env var overrides)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$SCRIPT_DIR}"

if [ ! -d "$CROSSCHECK_DIR/git-hooks" ]; then
    echo "❌ Error: CrossCheck hooks not found at $CROSSCHECK_DIR/git-hooks"
    exit 1
fi

echo "🧪 Hook Behavior Test Suite"
echo "==========================="
echo ""

PASSED=0
FAILED=0
SKIPPED=0
TEST_DIR=""

# Isolate tests from user's global git config
export GIT_CONFIG_GLOBAL=/dev/null

# Cleanup function — remove all test directories from this run (keyed by PID)
cleanup() {
    rm -rf /tmp/hook-behavior-test-*-$$ 2>/dev/null || true
}
trap cleanup EXIT

# Create a fresh test repo with hooks installed
# Uses a feature branch to avoid Claude approval gate on main
setup_test_repo() {
    local name="$1"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Install CrossCheck hooks directly (no prompts)
    mkdir -p .git/hooks
    for hook in pre-commit commit-msg; do
        cp "$CROSSCHECK_DIR/git-hooks/$hook" ".git/hooks/$hook"
        chmod +x ".git/hooks/$hook"
    done

    # Initial commit on main (needed for diff operations)
    echo "initial" > README.md
    mkdir -p user-content
    echo "human zone" > user-content/README.md
    git add README.md user-content/README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Switch to feature branch (avoids Claude approval gate on main)
    git checkout -q -b feat/test
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
# Pre-commit: Debug code detection
# ============================================================
echo "📋 Category: Pre-commit debug code detection"
echo ""

test_debug_add_warns() {
    setup_test_repo "debug-add"
    echo 'console.log("debug");' > test.js
    git add test.js
    # Capture hook output (commit will succeed since it's a warning)
    output=$(git commit -m "test: add debug code for testing" 2>&1) || true
    if echo "$output" | grep -q "Debug statements found"; then
        pass "Adding console.log triggers debug warning"
    else
        fail "Adding console.log should trigger debug warning"
    fi
}

test_debug_remove_no_warn() {
    # This test verifies the fix from fix/hook-detection-accuracy
    # The pre-commit hook must filter to added lines only (grep '^\+')
    # to avoid false positives when REMOVING debug code
    setup_test_repo "debug-remove"
    echo 'console.log("debug");' > test.js
    git add test.js
    git commit -m "chore: setup file" -q --no-verify

    # Now remove the debug line
    echo '// clean code' > test.js
    git add test.js
    output=$(git commit -m "test: remove debug code from codebase" 2>&1) || true
    if echo "$output" | grep -q "Debug statements found"; then
        # Check if this hook has the fix (filters added lines only)
        if grep -q "grep -E '^\\\+' | grep -qE.*console" "$CROSSCHECK_DIR/git-hooks/pre-commit"; then
            fail "Removing console.log should NOT trigger debug warning (fix is present but not working)"
        else
            skip "Removing console.log triggers false positive (fix pending in fix/hook-detection-accuracy)"
        fi
    else
        pass "Removing console.log does not trigger false positive"
    fi
}

test_debug_add_warns
test_debug_remove_no_warn
echo ""

# ============================================================
# Pre-commit: Secrets detection
# ============================================================
echo "📋 Category: Pre-commit secrets detection"
echo ""

test_secret_blocks() {
    setup_test_repo "secret-block"
    # Build test secret from parts (avoids triggering repo's own pre-commit hook)
    local key_name="api_key" key_val="sk-proj-abcdefghijklmnopqrstuvwx"
    echo "$key_name = \"$key_val\"" > config.py
    git add config.py
    if git commit -m "test: add config with secret key" -q 2>&1; then
        fail "Committing a secret should be blocked"
    else
        pass "Secret in staged changes blocks commit"
    fi
}

test_env_file_blocks() {
    setup_test_repo "env-block"
    echo 'DB_HOST=localhost' > .env
    git add .env
    if git commit -m "test: add env file to project" -q 2>&1; then
        fail "Committing .env should be blocked"
    else
        pass ".env file in staged changes blocks commit"
    fi
}

test_no_secret_passes() {
    setup_test_repo "no-secret"
    echo 'host = "localhost"' > config.py
    git add config.py
    if git commit -m "test: add clean config file here" -q 2>&1; then
        pass "Clean config file passes secrets check"
    else
        fail "Clean config file should not be blocked"
    fi
}

test_secret_blocks
test_env_file_blocks
test_no_secret_passes
echo ""

# ============================================================
# Pre-commit: user-content/ protection
# ============================================================
echo "📋 Category: Pre-commit user-content protection"
echo ""

test_user_content_blocks() {
    setup_test_repo "user-content"
    echo "agent modified this" > user-content/notes.md
    git add user-content/notes.md
    if git commit -m "test: modify user content zone" -q 2>&1; then
        fail "Modifying user-content/ should be blocked"
    else
        pass "user-content/ modification blocks commit"
    fi
}

test_user_content_blocks
echo ""

# ============================================================
# Commit-msg: Conventional commit format
# ============================================================
echo "📋 Category: Commit-msg conventional format"
echo ""

test_good_msg_passes() {
    setup_test_repo "good-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat: add a new feature here" -q 2>&1; then
        pass "Valid conventional commit passes"
    else
        fail "Valid conventional commit should pass"
    fi
}

test_bad_msg_blocks() {
    setup_test_repo "bad-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "added some stuff to the codebase" -q 2>&1; then
        fail "Non-conventional commit should be blocked"
    else
        pass "Non-conventional commit message is rejected"
    fi
}

test_short_msg_blocks() {
    setup_test_repo "short-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat: x" -q 2>&1; then
        fail "Commit with <10 char description should be blocked"
    else
        pass "Short description (<10 chars) is rejected"
    fi
}

test_scoped_msg_passes() {
    setup_test_repo "scoped-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "fix(api): handle null response correctly" -q 2>&1; then
        pass "Scoped conventional commit passes"
    else
        fail "Scoped conventional commit should pass"
    fi
}

test_breaking_msg_passes() {
    setup_test_repo "breaking-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "feat!: remove deprecated endpoints entirely" -q 2>&1; then
        pass "Breaking change commit passes"
    else
        fail "Breaking change commit should pass"
    fi
}

test_first_line_only() {
    # This test verifies the fix from fix/hook-detection-accuracy
    # The commit-msg hook must check only head -1 for format validation
    setup_test_repo "first-line"
    echo "content" > test.txt
    git add test.txt
    msg="$(printf 'bad first line\nfeat: this line matches but should not save it')"
    if git commit -m "$msg" -q 2>&1; then
        # Check if this hook has the fix (uses head -1)
        if grep -q "head -1 | grep -qE" "$CROSSCHECK_DIR/git-hooks/commit-msg"; then
            fail "Body line matching format should NOT save a bad subject (fix is present but not working)"
        else
            skip "Body line bypasses format check (fix pending in fix/hook-detection-accuracy)"
        fi
    else
        pass "Only first line is checked for conventional format"
    fi
}

test_merge_commit_passes() {
    setup_test_repo "merge-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "Merge branch 'feature' into main" -q 2>&1; then
        pass "Merge commit bypasses format check"
    else
        fail "Merge commit should bypass format check"
    fi
}

test_revert_commit_passes() {
    setup_test_repo "revert-msg"
    echo "content" > test.txt
    git add test.txt
    if git commit -m "Revert \"feat: previous change\"" -q 2>&1; then
        pass "Revert commit bypasses format check"
    else
        fail "Revert commit should bypass format check"
    fi
}

test_good_msg_passes
test_bad_msg_blocks
test_short_msg_blocks
test_scoped_msg_passes
test_breaking_msg_passes
test_first_line_only
test_merge_commit_passes
test_revert_commit_passes
echo ""

# ============================================================
# Pre-commit: Provider-specific token detection
# ============================================================
echo "📋 Category: Pre-commit provider-specific tokens"
echo ""

test_provider_token_blocks() {
    setup_test_repo "provider-token"
    # Use a GitHub PAT pattern with a non-keyword variable name
    # so only the provider-specific check catches it (not the generic secret check)
    local token_prefix="ghp_" token_body="abcdefghijklmnopqrstuvwxyz1234567890"
    echo "SETTING=${token_prefix}${token_body}" > config.txt
    git add config.txt
    if git commit -m "feat: add config template file" -q 2>&1; then
        fail "Committing provider-specific token should be blocked"
    else
        pass "Provider-specific token (GitHub PAT) blocks commit"
    fi
}

test_provider_token_blocks
echo ""

# ============================================================
# Post-commit: Checkpoint and session tracking
# ============================================================
echo "📋 Category: Post-commit checkpoint and session tracking"
echo ""

test_progress_checkpoint_created() {
    setup_test_repo "progress-checkpoint"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    # Create PROGRESS.md and commit it (no-verify to skip hooks for setup)
    echo "# Progress" > PROGRESS.md
    git add PROGRESS.md
    git commit -m "chore: add progress tracking file" -q --no-verify

    # Now make a real commit that triggers post-commit hook
    echo "change" > data.txt
    git add data.txt
    git commit -m "feat: add data file for testing" -q 2>&1 || true

    if grep -q "## Checkpoint:" PROGRESS.md; then
        pass "PROGRESS.md checkpoint created after commit"
    else
        fail "PROGRESS.md should have checkpoint after commit"
    fi
}

test_session_counter_incremented() {
    setup_test_repo "session-counter"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    echo "change" > data.txt
    git add data.txt
    git commit -m "feat: add data file for testing" -q 2>&1 || true

    counter_file=".git/hooks-session-counter"
    if [ -f "$counter_file" ] && [ "$(cat "$counter_file")" -ge 1 ]; then
        pass "Session counter incremented after commit"
    else
        fail "Session counter should be >= 1 after commit"
    fi
}

test_session_reminder_at_five() {
    setup_test_repo "session-reminder"
    cp "$CROSSCHECK_DIR/git-hooks/post-commit" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"

    # Pre-set counter to 4 so next commit triggers reminder at 5
    echo "4" > ".git/hooks-session-counter"

    echo "change5" > data.txt
    git add data.txt
    output=$(git commit -m "feat: trigger session reminder now" 2>&1) || true

    if echo "$output" | grep -q "Long session detected"; then
        pass "Session reminder shown at 5 commits"
    else
        fail "Session reminder should appear at 5 commits"
    fi
}

test_progress_checkpoint_created
test_session_counter_incremented
test_session_reminder_at_five
echo ""

# ============================================================
# Pre-push: Secret detection and branch rules
# ============================================================
echo "📋 Category: Pre-push secret detection"
echo ""

setup_test_repo_with_remote() {
    local name="$1"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    local REMOTE_DIR="/tmp/hook-behavior-test-${name}-remote-$$"
    rm -rf "$TEST_DIR" "$REMOTE_DIR" 2>/dev/null || true

    # Create bare remote
    mkdir -p "$REMOTE_DIR"
    cd "$REMOTE_DIR"
    git init -q --bare

    # Create local repo
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"
    git remote add origin "$REMOTE_DIR"

    # Install commit hooks only (pre-push installed AFTER initial push to avoid
    # the pre-check gate that blocks pushes to main without /techdebt marker)
    mkdir -p .git/hooks
    for hook in pre-commit commit-msg; do
        cp "$CROSSCHECK_DIR/git-hooks/$hook" ".git/hooks/$hook"
        chmod +x ".git/hooks/$hook"
    done

    # Initial commit and push (no pre-push hook yet)
    # Include timestamps in README.md to satisfy pre-push timestamp check
    cat > README.md << 'READMEEOF'
# Test

**Created:** 2026-01-01-00-00
**Last Updated:** 2026-01-01-00-00
READMEEOF
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify
    git push -u origin main -q 2>/dev/null

    # NOW install pre-push hook (after initial main push)
    cp "$CROSSCHECK_DIR/git-hooks/pre-push" ".git/hooks/pre-push"
    chmod +x ".git/hooks/pre-push"

    # Switch to feature branch
    git checkout -q -b feat/test
}

test_prepush_secret_rescan_blocks() {
    setup_test_repo_with_remote "prepush-secret"

    # Build secret from parts to avoid triggering repo's own hooks
    local key_name="api_key" key_val="sk-proj-abcdefghijklmnopqrstuvwx"
    echo "$key_name = \"$key_val\"" > secret.py
    git add secret.py
    git commit -m "feat: add config file with key" -q --no-verify

    if git push origin feat/test 2>&1; then
        fail "Pushing secret should be blocked by pre-push"
    else
        pass "Pre-push secret re-scan blocks push"
    fi
}

test_prepush_feature_branch_allowed() {
    setup_test_repo_with_remote "prepush-clean"

    echo "clean code" > app.py
    git add app.py
    git commit -m "feat: add clean application code" -q --no-verify

    if git push origin feat/test 2>&1; then
        pass "Clean feature branch push allowed"
    else
        fail "Clean feature branch push should be allowed"
    fi
}

test_prepush_provider_token_blocks() {
    setup_test_repo_with_remote "prepush-provider"

    # Use a GitHub PAT pattern with a non-keyword variable name
    # to ensure only the provider-specific check catches it (not the generic secret check)
    local token_prefix="ghp_" token_body="abcdefghijklmnopqrstuvwxyz1234567890"
    echo "SETTING=${token_prefix}${token_body}" > config.txt
    git add config.txt
    git commit -m "feat: add config template file" -q --no-verify

    if git push origin feat/test 2>&1; then
        fail "Pushing provider-specific token should be blocked"
    else
        pass "Pre-push blocks provider-specific token (GitHub PAT)"
    fi
}

test_prepush_delete_branch_allowed() {
    setup_test_repo_with_remote "prepush-delete"

    # Push a feature branch first
    echo "feature code" > feature.py
    git add feature.py
    git commit -m "feat: add feature code here" -q --no-verify
    git push origin feat/test -q 2>/dev/null

    # Now delete the remote branch — should NOT be blocked
    if git push origin --delete feat/test 2>&1; then
        pass "Branch deletion push is not blocked"
    else
        fail "git push --delete should not be blocked by pre-push hook"
    fi
}

test_prepush_secret_rescan_blocks
test_prepush_feature_branch_allowed
test_prepush_provider_token_blocks
test_prepush_delete_branch_allowed
echo ""

# ============================================================
# Post-checkout: Environment cleanup and TODO.md
# ============================================================
echo "📋 Category: Post-checkout environment cleanup"
echo ""

test_postcheckout_todo_branch_header() {
    setup_test_repo "checkout-todo"
    cp "$CROSSCHECK_DIR/git-hooks/post-checkout" ".git/hooks/post-checkout"
    chmod +x ".git/hooks/post-checkout"

    # Create TODO.md on the feature branch
    echo "# TODO" > TODO.md
    echo "- Task 1" >> TODO.md
    git add TODO.md
    git commit -m "chore: add todo file for testing" -q --no-verify

    # Switch to a new branch (triggers post-checkout)
    git checkout -q -b feat/other 2>&1 || true

    if grep -q "## Current Branch: feat/other" TODO.md; then
        pass "TODO.md branch header updated on checkout"
    else
        fail "TODO.md should have branch header after checkout"
    fi
}

test_postcheckout_cleanup_runs() {
    setup_test_repo "checkout-cleanup"
    cp "$CROSSCHECK_DIR/git-hooks/post-checkout" ".git/hooks/post-checkout"
    chmod +x ".git/hooks/post-checkout"

    # Switch branches and check that the hook runs (check output)
    output=$(git checkout -q -b feat/cleanup-test 2>&1) || true

    if echo "$output" | grep -q "Branch switched"; then
        pass "Post-checkout hook runs on branch switch"
    else
        fail "Post-checkout hook should run on branch switch"
    fi
}

test_postcheckout_todo_branch_header
test_postcheckout_cleanup_runs
echo ""

# ============================================================
# Post-merge: PR counter and waterfall reminder
# ============================================================
echo "📋 Category: Post-merge PR counter and waterfall"
echo ""

test_postmerge_pr_counter_incremented() {
    local name="postmerge-counter"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"

    mkdir -p .git/hooks
    cp "$CROSSCHECK_DIR/git-hooks/post-merge" ".git/hooks/post-merge"
    chmod +x ".git/hooks/post-merge"

    # Initial commit on main
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Create and commit on feature branch
    git checkout -q -b feat/merge-test
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "feat: add feature for merge" -q --no-verify

    # Merge into main (diverge first to force true merge)
    git checkout -q main
    echo "main diverge" > diverge.txt
    git add diverge.txt
    git commit -m "chore: diverge main for merge" -q --no-verify
    git merge feat/merge-test --no-edit -q 2>&1 || true

    counter_file=".git/hooks-pr-counter"
    if [ -f "$counter_file" ] && [ "$(cat "$counter_file")" -ge 1 ]; then
        pass "PR counter incremented after merge"
    else
        fail "PR counter should be >= 1 after merge"
    fi
}

test_postmerge_waterfall_reminder() {
    local name="postmerge-waterfall"
    TEST_DIR="/tmp/hook-behavior-test-$name-$$"
    rm -rf "$TEST_DIR" 2>/dev/null || true
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.email "test@test.com"
    git config user.name "Test"

    mkdir -p .git/hooks
    cp "$CROSSCHECK_DIR/git-hooks/post-merge" ".git/hooks/post-merge"
    chmod +x ".git/hooks/post-merge"

    # Initial commit on main
    echo "initial" > README.md
    git add README.md
    git commit -m "chore: initial commit" -q --no-verify

    # Pre-set PR counter to 2 so next merge triggers reminder at 3
    echo "2" > ".git/hooks-pr-counter"

    # Create and commit on feature branch
    git checkout -q -b feat/waterfall-test
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "feat: add feature for waterfall" -q --no-verify

    # Merge into main
    git checkout -q main
    echo "main diverge" > diverge.txt
    git add diverge.txt
    git commit -m "chore: diverge main for merge" -q --no-verify
    output=$(git merge feat/waterfall-test --no-edit 2>&1) || true

    if echo "$output" | grep -q "Assessment waterfall due"; then
        pass "Waterfall reminder shown at 3 PR merges"
    else
        fail "Waterfall reminder should appear at 3 PR merges"
    fi
}

test_postmerge_pr_counter_incremented
test_postmerge_waterfall_reminder
echo ""

# ============================================================
# Supply-chain PreToolUse gate (GIT-6494)
# ============================================================
echo "📋 Category: Supply-chain gate parses executed commands"
echo ""

supply_gate_run() {
    GATE_STATUS=0
    GATE_OUTPUT=""
    local payload gate
    gate="$CROSSCHECK_DIR/scripts/preuse-supply-chain-gate.sh"
    # The gate lives in the canonical scripts/ tree. Mirror suites still run it.
    if [ ! -f "$gate" ]; then
        gate="$(cd "$CROSSCHECK_DIR/.." && pwd)/scripts/preuse-supply-chain-gate.sh"
    fi
    payload=$(jq -n --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    set +e
    if [ "${2:-}" = "fault" ]; then
        GATE_OUTPUT=$(printf '%s' "$payload" | GATE_TEST_FAULT=1 bash "$gate" 2>&1)
    else
        GATE_OUTPUT=$(printf '%s' "$payload" | bash "$gate" 2>&1)
    fi
    GATE_STATUS=$?
    set -e
}

test_supply_gate_blocks_structured_installs() {
    local label cmd
    while IFS=$'\t' read -r label cmd; do
        [ -z "$label" ] && continue
        supply_gate_run "$cmd"
        if [ "$GATE_STATUS" -eq 2 ] && printf '%s\n' "$GATE_OUTPUT" | grep -q "Parsed action:"; then
            pass "$label"
        else
            fail "$label (status=$GATE_STATUS)"
        fi
    done <<'EOF'
if/then install	if true; then pip install foo; fi
for/do install	for x in a; do pip install foo; done
bang install	! pip install foo
process substitution	cat <(pip install foo)
timeout wrapper	timeout 60 pip install foo
timeout signal	timeout --signal=TERM 60 pip install foo
nice wrapper	nice -n 10 pip install foo
stdbuf wrapper	stdbuf -o L pip install foo
env chdir	env -C /tmp pip install foo
escaped double quote	echo "a\"b" ; pip install foo ; echo "c"
escaped single quote	echo \' ; pip install foo ; echo \'
quote-glued hash	echo "hi"#; pip install foo
dollar-quote escape	echo $'a\'b'; pip install foo
exec dash-a	exec -a x pip install foo
sudo chdir	sudo -D /tmp pip install foo
sudo cluster	sudo -iu root pip install foo
sudo cluster E	sudo -Eu root pip install foo
sudo cluster n	sudo -nu root npm install x
sudo attached user	sudo -uroot pip install foo
leading redirect	2>/dev/null pip install x
redirect fd	2>&1 pip install x
sudo long user	sudo --user root pip install foo
time long format	time --format %e pip install x
stdbuf long output	stdbuf --output L pip install x
env cluster	env -iu FOO pip install x
timeout cluster	timeout -vk 5 10 pip install x
exec cluster	exec -ca name pip install x
coproc	coproc pip install x
function body	function f { pip install x; }
env altpath	env -P /usr/bin pip install foo
env split-string	env -S pip install foo
time format	time -f %e pip install foo
eval	eval pip install foo
builtin	builtin pip install foo
uv run	uv run pip install foo
poetry run	poetry run pip install foo
pipenv run	pipenv run pip install foo
mise exec	mise exec -- npm install foo
watch	watch pip install foo
doas	doas pip install foo
arch	arch -arm64 pip install foo
caffeinate	caffeinate -i npm install foo
xcrun	xcrun pip install foo
flock	flock /tmp/l pip install foo
script	script -q /dev/null pip install foo
find exec	find . -exec pip install foo \;
ssh	ssh host pip install foo
docker exec	docker exec c pip install foo
op run --env-file	op run --env-file=.env pip install foo
docker run	docker run node npm install foo
docker run flags	docker run --rm node npm install foo
compose exec	docker compose exec app pip install foo
podman exec	podman exec c pip install foo
kubectl exec	kubectl exec pod -- pip install foo
conda run	conda run pip install foo
pixi run	pixi run pip install foo
pyenv exec	pyenv exec pip install foo
direnv exec	direnv exec . pip install foo
bundle exec	bundle exec pip install foo
pnpm exec	pnpm exec pip install foo
yarn exec	yarn exec pip install foo
nix develop	nix develop -c pip install foo
coproc name	coproc NAME { pip install x; }
arith cmdsub	echo $(( $(pip install foo) ))
arith backtick	echo $(( `pip install foo` ))
arith then install	echo $((1+2)); pip install foo
op run	op run -- pip install foo
quoted executable	"npm" install foo
quoted subcommand	pnpm "add" foo
quoted npx argument	npx "cowsay"
escaped manager	p\ip install foo
npm prefix before verb	npm --prefix x install y
npm global before verb	npm -g install x
pip quiet before verb	pip --quiet install foo
pip late no-deps	pip install foo --no-deps
npm late offline	npm install foo --offline
arith command	(( '$(pip install foo)' ))
EOF
    supply_gate_run 'echo hi # pip install foo'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Comment after a command is not an install"
    else
        fail "Comment should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'npm ci'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "npm ci stays allowed"
    else
        fail "npm ci should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'git status'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Commands that name no package manager stay allowed"
    else
        fail "git status should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'echo pip install foo'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Unquoted prose that does not execute pip stays allowed"
    else
        fail "echo pip install foo should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'git commit -m "pip install foo"'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "git commit prose stays allowed"
    else
        fail "git commit prose should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'git bisect run pip install foo'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "git bisect run package install is blocked"
    else
        fail "git bisect run package install should be blocked (status=$GATE_STATUS)"
    fi
    supply_gate_run 'op run -- npm ci'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "A wrapped npm ci stays allowed"
    else
        fail "Wrapped npm ci should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'grep -n pip install file'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "grep mentioning an install stays allowed"
    else
        fail "grep should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run "$(printf '%s\n' 'cat <<EOF' '$(pip install foo)' 'EOF')"
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Unquoted heredoc command substitution is blocked"
    else
        fail "Heredoc command substitution should block (status=$GATE_STATUS)"
    fi
    supply_gate_run $'sh <<EOF\npip install foo\nEOF'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Shell-fed heredoc install is blocked"
    else
        fail "Shell-fed heredoc install should block (status=$GATE_STATUS)"
    fi
    supply_gate_run $'bash <<\x27EOF\x27\nnpm install x\nEOF'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Quoted shell-fed heredoc install is blocked"
    else
        fail "Quoted shell-fed heredoc install should block (status=$GATE_STATUS)"
    fi
    supply_gate_run $'cat <<EOF | sh\npip install foo\nEOF'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Pipeline shell-fed heredoc install is blocked"
    else
        fail "Pipeline shell-fed heredoc install should block (status=$GATE_STATUS)"
    fi
    supply_gate_run $'python - <<\x27PY\x27\nsubprocess.run(["pip", "install", "foo"])\nPY'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Python stdin install is blocked"
    else
        fail "Python stdin install should block (status=$GATE_STATUS)"
    fi
    supply_gate_run $'sh <<EOF\n# pip install is prose\nprintf "%s" "pip install prose"\nEOF'
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Shell-fed heredoc prose stays allowed"
    else
        fail "Shell-fed heredoc prose should be allowed (status=$GATE_STATUS)"
    fi
    supply_gate_run 'else pip install foo'
    if [ "$GATE_STATUS" -eq 2 ] && printf '%s\n' "$GATE_OUTPUT" | grep -Fq 'Parsed action: pip install foo'; then
        pass "Diagnostic omits shell keywords"
    else
        fail "Diagnostic should name only the package action (status=$GATE_STATUS)"
    fi
    supply_gate_run 'pip install foo &>/dev/null'
    if [ "$GATE_STATUS" -eq 2 ] && printf '%s\n' "$GATE_OUTPUT" | grep -Fq 'Parsed action: pip install foo'; then
        pass "Diagnostic keeps redirect-free parsed action"
    else
        fail "Diagnostic should omit redirects (status=$GATE_STATUS)"
    fi
    local big i start
    big=$'cat <<EOF\n'
    i=0
    while [ "$i" -lt 4000 ]; do
        big+='npm run build'$'\n'
        i=$((i + 1))
    done
    big+=$'EOF'
    start=$SECONDS
    supply_gate_run "$big"
    if [ "$GATE_STATUS" -eq 0 ] && [ $((SECONDS - start)) -le 8 ]; then
        pass "A 50KB unquoted heredoc stays within the time bound"
    else
        fail "Large heredoc status=$GATE_STATUS elapsed=$((SECONDS - start))s"
    fi
    big="echo a"
    i=0
    while [ "$i" -lt 400 ]; do
        big+=" && echo a"
        i=$((i + 1))
    done
    big+=" && pip install foo"
    start=$SECONDS
    supply_gate_run "$big"
    if [ "$GATE_STATUS" -eq 2 ] && [ $((SECONDS - start)) -le 8 ]; then
        pass "A long command chain still blocks within the time bound"
    else
        fail "Long chain status=$GATE_STATUS elapsed=$((SECONDS - start))s"
    fi
    big=$'cat <<EOF\n'
    i=0
    while [ "$i" -lt 1000 ]; do
        big+='v=$(date)'$'\n'
        i=$((i + 1))
    done
    big+=$'npm ci\nEOF'
    gate="$CROSSCHECK_DIR/scripts/preuse-supply-chain-gate.sh"
    if [ ! -f "$gate" ]; then
        gate="$(cd "$CROSSCHECK_DIR/.." && pwd)/scripts/preuse-supply-chain-gate.sh"
    fi
    start=$SECONDS
    payload=$(jq -n --arg cmd "$big" '{tool_name:"Bash", tool_input:{command:$cmd}}')
    set +e
    printf '%s' "$payload" | /bin/bash "$gate" >/dev/null 2>&1
    GATE_STATUS=$?
    set -e
    if [ "$GATE_STATUS" -eq 0 ] && [ $((SECONDS - start)) -le 8 ]; then
        pass "Heredoc expansions stay within the time bound under /bin/bash"
    else
        fail "Expansion heredoc status=$GATE_STATUS elapsed=$((SECONDS - start))s"
    fi
    supply_gate_run "pip install foo" fault
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "A scanner fault refuses the command"
    else
        fail "A scanner fault should refuse (status=$GATE_STATUS)"
    fi
}

test_supply_gate_ignores_quoted_install_prose() {
    supply_gate_run "python3 -c 'print(\"pip install switchyard cannot ever be an acceptance criterion\")'"
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Quoted pip install prose is not an install"
    else
        fail "Quoted pip install prose should be allowed (status=$GATE_STATUS)"
    fi
}

test_supply_gate_ignores_heredoc_body() {
    supply_gate_run "$(printf '%s\n' 'cat <<EOF' 'pip install foo' 'EOF')"
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "Here-document body mentioning pip install is not an install"
    else
        fail "Here-document body should be allowed (status=$GATE_STATUS)"
    fi
}

test_supply_gate_blocks_real_pip_install() {
    supply_gate_run "pip install foo"
    if [ "$GATE_STATUS" -eq 2 ] && printf '%s\n' "$GATE_OUTPUT" | grep -q "Parsed action: pip install foo"; then
        pass "pip install foo is blocked and the parsed action is named"
    else
        fail "pip install foo should block with a parsed action (status=$GATE_STATUS)"
    fi
}

test_supply_gate_blocks_install_after_safe_command() {
    supply_gate_run "npm ci && pip install evil"
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "A later pip install is not masked by npm ci"
    else
        fail "npm ci && pip install evil should block (status=$GATE_STATUS)"
    fi
}

test_supply_gate_override_must_be_assignment() {
    supply_gate_run "SAFE_INSTALL_OVERRIDE=1 pip install foo"
    if [ "$GATE_STATUS" -eq 0 ]; then
        pass "SAFE_INSTALL_OVERRIDE=1 assignment allows the install"
    else
        fail "Override assignment should allow the install (status=$GATE_STATUS)"
    fi
    supply_gate_run 'echo "SAFE_INSTALL_OVERRIDE=1" && pip install evil'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Override text inside quotes does not allow a later install"
    else
        fail "Quoted override text should not allow pip install (status=$GATE_STATUS)"
    fi
}

test_supply_gate_blocks_command_substitution() {
    supply_gate_run 'echo $(pip install foo)'
    if [ "$GATE_STATUS" -eq 2 ]; then
        pass "Command substitution that installs is blocked"
    else
        fail "Command substitution install should block (status=$GATE_STATUS)"
    fi
}

test_supply_gate_ignores_quoted_install_prose
test_supply_gate_ignores_heredoc_body
test_supply_gate_blocks_real_pip_install
test_supply_gate_blocks_install_after_safe_command
test_supply_gate_override_must_be_assignment
test_supply_gate_blocks_command_substitution
test_supply_gate_blocks_structured_installs
echo ""

# ============================================================
# Summary
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASSED + FAILED + SKIPPED))
if [ "$FAILED" -eq 0 ]; then
    echo "✅ All $TOTAL tests completed ($PASSED passed, $SKIPPED skipped)"
else
    echo "❌ $FAILED/$TOTAL tests failed"
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAILED" -eq 0 ]
