# CrossCheck Troubleshooting Guide

**Created:** 2026-02-09-16-28
**Last Updated:** 2026-02-23-00-00

When automation fails, debug it here.

---

## Hook Error Reference

Exact error messages from each hook, what triggers them, and how to resolve them. Use this to understand what Claude sees when hooks block and to debug issues where hooks aren't followed correctly.

### Pre-Commit: Secrets Detected

**Trigger:** Staging files containing API keys, passwords, tokens, credentials

**Exact error message:**
```
  ❌ Possible secret detected in staged changes
     Common patterns: API keys, tokens, passwords (20+ chars)
     Review carefully. If false positive: --no-verify is blocked by permissions
```

**Resolution:**
1. Remove secret from file
2. Use environment variable instead
3. Re-stage and commit

---

### Pre-Commit: Debug Code Detected (Warning Only)

**Trigger:** Staging files with console.log, debugger, print statements

**Exact warning message:**
```
⚠️  Debug statements found (console.log, debugger, pdb, breakpoint, print)
   Consider removing before commit
```

**Note:** This is a WARNING ONLY -- the commit proceeds. No action required.

---

### Pre-Commit: Missing Documentation Timestamps (Warning Only)

**Trigger:** Modified .md file without Last Updated timestamp

**Exact warning message:**
```
⚠️  README.md: timestamp not updated to today (2026-02-07)
   Run: /doc-timestamp or manually update
   Skipping check (warning only)
```

**Note:** This is a WARNING ONLY -- the commit proceeds. Can update timestamp using `/doc-timestamp` skill for cleaner commits.

---

### Commit-Msg: Invalid Conventional Commit Format

**Trigger:** Commit message doesn't follow conventional commits

**Exact error message:**
```
❌ Commit message must follow conventional commits format

Format: <type>[(scope)][!]: <description>

Types: feat, fix, refactor, test, docs, chore, style, perf, ci, build, revert
Scope: optional (ui, api, db, etc.)
!: optional (breaking change marker)
Description: at least 10 characters

Examples:
  feat: add user authentication
  fix(api): handle null response
  feat!: remove deprecated endpoints
  refactor(core): simplify error handling

Your message:
  added some stuff

Note: --no-verify is blocked by permissions (policy enforcement)
```

**Resolution:**
1. Rewrite commit message in conventional format
2. Re-commit with proper format

---

### Commit-Msg: Claude Approval Required (CRITICAL)

**Trigger:** Committing feat/fix/refactor to main without "Claude Approved"

**Exact error message:**
```
⛔ BLOCKED: Claude approval required for feat commits to main

🤖 Claude: Follow this workflow (DO NOT skip steps):

   Step 1: Get review prompt
   ~/.crosscheck/scripts/claude-approve-commit.sh

   Step 2: Send prompt to Claude via terminal
   Copy the output and paste to Claude in your terminal session

   Step 3: Review Claude feedback
   - If Claude says APPROVED: Proceed to Step 4
   - If Claude requests changes: Fix issues and restart from Step 1
   - Keep iterating with Claude until you get APPROVED

   Step 4: ONLY after Claude approves, add to commit message:
   git commit -m "feat: add user authentication

   Claude Approved"

   ⚠️  CRITICAL: Do NOT add 'Claude Approved' without actual Claude approval!
   ⚠️  You must see Claude explicitly say 'APPROVED' or 'LGTM'

👤 If you're human:
   Same process - get actual Claude approval before adding to message

Note: --no-verify is blocked by permissions (policy enforcement)
```

**Resolution:**
1. Run `~/.crosscheck/scripts/claude-approve-commit.sh`
2. Send output to Claude in terminal
3. Wait for Claude response
4. If Claude says changes needed: fix the issues, go back to step 1
5. ONLY if Claude says "APPROVED": retry commit with "Claude Approved" in message

**Common mistakes:**
- Adding "Claude Approved" without running the script
- Adding "Claude Approved" without sending to Claude
- Adding "Claude Approved" when Claude said "changes needed"

---

### Pre-Push: Pre-Checks Not Run

**Trigger:** Pushing to main without running /techdebt and /pre-pr-check in last hour

**Exact error message:**
```
⛔ BLOCKED: Pre-push quality checks required before pushing to main

🤖 Claude: Run these commands:

   # Note: Hook will show actual path with hash and branch values
   /techdebt && /pre-pr-check && touch ~/.cache/CrossCheck/prechecks-$REPO_HASH-$BRANCH && git push

📋 What this does:
   1. /techdebt      - Find and eliminate technical debt
   2. /pre-pr-check  - Comprehensive pre-PR checklist
   3. touch marker   - Record that checks passed (valid 1 hour)
   4. git push       - Retry push (will succeed with marker present)

👤 If you're human:
   # Note: Hook will show actual path with hash and branch values
   Run checks manually, then: touch ~/.cache/CrossCheck/prechecks-$REPO_HASH-$BRANCH && git push

Note: --no-verify is blocked by permissions (policy enforcement)
```

**Resolution:**
1. Run `/techdebt` skill and fix any issues found
2. Run `/pre-pr-check` skill and fix any issues found
3. Create marker file
4. Retry push

---

### Pre-Push: Merge Conflict Markers

**Trigger:** Pushing code with unresolved merge conflicts

**Exact error message:**
```
  ❌ Merge conflict markers found in committed code
     Resolve conflicts before pushing
```

**Resolution:**
1. Open files with conflicts
2. Resolve conflicts properly and remove markers
3. Test merged code
4. Commit resolution
5. Push

---

### Post-Checkout Hook (Information Only)

**Note:** This hook does not block, it only informs.

**Trigger:** Switching branches

**Message:**
```
🔄 Branch switched: cleaning up environment
  🧹 Killing orphan background processes in /Users/sqb/project...
  ✅ Killed repo-specific background processes
  🗑️  Cleaning .tmp directory...
  📝 Updating TODO.md branch context...
✅ Environment cleaned for new branch
```

No action needed. Continue working on new branch. Background processes are cleaned automatically.

---

### Post-Merge Hook (Information Only)

**Note:** This hook does not block, it only informs.

**Trigger:** Merging PR or branches

**Message:**
```
🎉 Merge completed: running post-merge actions...
  🗑️  Deleting local merged branch: feat-auth
  ✅ Local branch deleted
  ℹ️  Remote branch still exists: origin/feat-auth
     Delete manually: git push origin --delete feat-auth
     Or use GitHub's auto-delete feature in PR settings
  🔍 Checking CI status (non-blocking)...
  ⏳ CI running in background
     Monitor: gh run watch
     Or continue working - hook won't block
✅ Post-merge actions complete
```

Note the local branch was deleted. Continue to next task. Optionally monitor CI with `gh run watch`.

---

### Quick Reference: Hook Commands

When hooks block, run these exact commands:

| Hook | Scenario | Command |
|------|----------|---------|
| commit-msg | Claude approval needed | `~/.crosscheck/scripts/claude-approve-commit.sh` then send to Claude, wait for APPROVED, add to commit |
| pre-push | Pre-checks needed | `/techdebt && /pre-pr-check && touch $MARKER && git push` |
| pre-commit | Secrets detected | Remove secrets, use env vars, re-commit |
| pre-commit | Debug code | Remove debug statements, re-commit |
| pre-commit | Missing timestamps | Add timestamps, re-commit |
| commit-msg | Invalid format | Rewrite in conventional format, re-commit |

---

### Debugging: When Claude Doesn't Follow Hook Instructions

**If Claude adds "Claude Approved" without getting approval:**

Check:
1. Did Claude run the approval script?
2. Did Claude send output to Claude?
3. Did Claude wait for Claude response?
4. Did Claude actually say "APPROVED"?

Fix: Make commit-msg message more explicit about required steps.

**If Claude bypasses pre-push checks:**

Check:
1. Did Claude run /techdebt?
2. Did Claude run /pre-pr-check?
3. Did Claude create marker file?

Fix: Make pre-push message show single chained command.

**If Claude commits secrets:**

Check:
1. Is pre-commit hook installed?
2. Is pre-commit hook executable?
3. Did Claude use --no-verify?

Fix: Ensure hooks installed and Claude knows not to use --no-verify.

---

### Testing Hook Messages

To test what Claude sees when hooks fire:

```bash
# Test commit-msg (Claude approval)
git checkout main
echo "test" > test.txt
git add test.txt
git commit -m "feat: test without approval"
# See exact message Claude would see

# Test pre-push (pre-checks)
git push
# See exact message Claude would see

# Test pre-commit (secrets)
echo 'API_KEY="sk_test_123456789"' > config.py
git add config.py
git commit -m "test: add config"
# See exact message Claude would see
```

---

## Hook Not Running

```bash
# Check hook is executable
ls -la ~/.claude/git-hooks/pre-commit
# Should see: -rwxr-xr-x (x = executable)

# Make executable if needed
chmod +x ~/.claude/git-hooks/*

# Check global hooks path
git config --global core.hooksPath
# Should see: ~/.claude/git-hooks
```

## Claude Review Not Logging

```bash
# Check log file exists and is writable
ls -la ~/.claude/claude-commit-reviews.log

# Create if missing
touch ~/.claude/claude-commit-reviews.log

# Test manually
echo "test" >> ~/.claude/claude-commit-reviews.log
cat ~/.claude/claude-commit-reviews.log
```

## Pre-Push Keeps Blocking

```bash
# Hook expects these skills to exist: /techdebt, /pre-pr-check
# If you don't have them, create marker manually:

BRANCH=$(git branch --show-current)
# Cross-platform hash:
if command -v md5sum >/dev/null 2>&1; then
    REPO_HASH=$(git rev-parse --show-toplevel | md5sum | cut -d' ' -f1)
elif command -v md5 >/dev/null 2>&1; then
    REPO_HASH=$(git rev-parse --show-toplevel | md5 -q)
else
    REPO_HASH=$(git rev-parse --show-toplevel | base64 | tr -d '=\n/')
fi
CACHE_DIR="$HOME/.cache/CrossCheck"
mkdir -p "$CACHE_DIR"
PRE_CHECK_MARKER="${CACHE_DIR}/prechecks-${REPO_HASH}-${BRANCH}"

# Create marker (valid for 1 hour)
touch "$PRE_CHECK_MARKER"

# Now push will work
git push
```

## Branch Auto-Delete Not Working

**After merging PR, local branch still exists:**

```bash
# Check post-merge hook is installed
ls -la ~/.claude/git-hooks/post-merge
# Should see executable hook

# Manually delete local branch
git branch -d branch-name

# Check if remote branch was deleted by GitHub
git fetch --prune
git branch -a | grep branch-name
# Should be gone
```

**Remote branch not auto-deleted:**

GitHub setting may be disabled. Enable it:

```bash
# Check current setting
gh api repos/OWNER/REPO --jq '.delete_branch_on_merge'

# Enable auto-delete
gh api repos/OWNER/REPO -X PATCH -f delete_branch_on_merge=true
```

See [README.md](README.md#detailed-setup) for how to configure this setting.

## Hooks Bypassed on Some Commits

**Symptoms:**
- Some commits don't trigger hooks
- Hooks work sometimes but not always

**Causes:**

1. **Using git aliases that bypass hooks:**
   ```bash
   # Bad: Custom alias might skip hooks
   git config --global alias.quickcommit '!git commit --no-verify'

   # Check your aliases
   git config --get-regexp alias
   ```

2. **IDE git integration bypassing hooks:**
   - VSCode, IntelliJ may have "Skip hooks" option
   - Check IDE git settings
   - Use terminal for commits if unsure

3. **Different repository using different hooks:**
   ```bash
   # Check which hooks are active in current repo
   git config core.hooksPath

   # Should point to global hooks
   # If empty, repo is using local hooks in $(git rev-parse --git-common-dir)/hooks/
   ```

## GitHub Protection Not Enforcing

**Can push directly to main when you shouldn't:**

```bash
# Verify protection is enabled
gh api repos/OWNER/REPO/rulesets | jq '.[] | select(.name == "protect-main")'

# Should show ruleset with enforcement: "active"
```

If not active:
1. Go to GitHub → Settings → Rules → Rulesets
2. Find "protect-main" ruleset
3. Change enforcement status to "Active"

See [README.md](README.md#detailed-setup) for full setup instructions.

## Permission Denied Errors

**"Permission to use Bash with command X has been denied"**

This is intentional. The command is blocked by your permissions settings.

**Common blocks:**
- `rm` - Use `mv file garbage/` instead
- `git reset --hard` - Destructive, use feature branches instead
- `sudo` - Agents shouldn't use sudo
- `docker` - May access filesystem outside sandbox

**If you really need the command:**
1. Review why it's blocked (usually for safety)
2. Consider safer alternative
3. If absolutely necessary, update `~/.claude/settings.json` permissions

**Never remove from deny list without understanding why it's there.**

## Skills Not Found

**"/techdebt: command not found"**

Skills aren't installed. Install them:

```bash
# Copy skills from CrossCheck repo
cp ~/Documents/Developer/CrossCheck/skill-sources/*.md ~/.claude/commands/

# Verify installation
ls ~/.claude/commands/ | wc -l
# Should show 28 files (27 skills + INSTALL.md)

# Restart Claude
# Skills should now be available
```

See [skill-sources/INSTALL.md](skill-sources/INSTALL.md) for detailed skill installation.

## Tests Failing After Setup

**Symptoms:**
- Tests pass locally but fail in `/pre-pr-check`
- "Test command not found" errors

**Note:** The pre-push hook does NOT run tests directly. Tests are run by the
`/pre-pr-check` skill (invoked by `/submit-pr`). The pre-push hook checks
timestamps, markers, conflicts, and secrets.

**Check test setup:**

```bash
# For Node projects
npm test

# For Python projects
pytest

# Tests are run by /pre-pr-check, not by git hooks directly
```

**Fix:**
1. Ensure tests work manually first
2. `/pre-pr-check` detects test commands from package.json, pytest.ini, etc.
3. Check package.json has "test" script (Node)
4. Check pytest is installed (Python)

## Context Window Issues

**"Context limit exceeded" errors:**

```bash
# Compact conversation to free context
/compact

# Restart Claude session for fresh context
exit  # or Ctrl+D
claude  # start new session
```

See [CLAUDE.md](CLAUDE.md) for context management rules.

## Worktree Conflicts

**"Cannot create worktree, branch checked out elsewhere"**

```bash
# List all worktrees
git worktree list

# Remove worktree that's blocking
git worktree remove path/to/worktree

# Or use cleanup skill
/cleanup-worktrees
```

**"Worktree path already exists"**

```bash
# Check what's at that path
ls -la path/to/worktree

# If it's a stale worktree
git worktree remove path/to/worktree --force

# If it's unrelated files, choose different path
git worktree add ../different-name branch-name
```

See [CLAUDE.md](CLAUDE.md) for worktree usage patterns.

## CI Checks Always Failing

**GitHub Actions failing but unclear why:**

```bash
# View recent runs
gh run list --limit 5

# View specific run details
gh run view RUN_ID

# View logs
gh run view RUN_ID --log

# Re-run failed checks
gh run rerun RUN_ID
```

**Common CI failures:**
1. **Missing secrets** - Add to GitHub → Settings → Secrets
2. **Wrong Node/Python version** - Update .github/workflows/*.yml
3. **Dependencies not installed** - Check workflow has install step
4. **Tests fail in CI but pass locally** - Environment difference, check logs

## Getting Help

If troubleshooting doesn't resolve your issue:

1. **Check recent issues:** [github.com/sburl/CrossCheck/issues](https://github.com/sburl/CrossCheck/issues)
2. **Search discussions:** [github.com/sburl/CrossCheck/discussions](https://github.com/sburl/CrossCheck/discussions)
3. **Create new issue:** Include error message, what you tried, environment (OS, shell)

**When reporting issues:**
- Include full error message
- Show what commands you ran
- Mention which hook/script failed
- OS and shell version (`uname -a`, `echo $SHELL`)

---

## Related Documentation

- **[README.md](README.md#detailed-setup)** - Setup guide
- **[ADVANCED.md](../ADVANCED.md)** - Advanced customization and verification
- **[CLAUDE.md](CLAUDE.md)** - Workflow reference
