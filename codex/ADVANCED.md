# Advanced CrossCheck Configuration

**Created:** 2026-02-09-16-52
**Last Updated:** 2026-02-16-00-00

Deep customization, multi-agent workflows, and power-user features.

---

## Multi-Agent Workflows

**Delegate specialized tasks to different AI models:**

### Codex Delegation

Use Codex for security reviews, architecture analysis, and deep code inspection:

```bash
# In Codex:
/codex-delegate "Review PR #42 for security vulnerabilities"
/codex-delegate "Analyze database schema for optimization opportunities"
/codex-delegate "Identify code duplication across the codebase"
```

**How it works:**
1. Codex reads CODEX.md and injects context
2. Codex runs autonomously with `--full-auto` flag
3. Results reported back to Codex
4. Codex continues with Codex findings

### Gemini Delegation

Use Gemini for alternative perspectives and creative problem-solving:

```bash
/gemini-delegate "Propose alternative architecture for user authentication"
/gemini-delegate "Review API design for consistency"
```

### Ensemble Opinions

Get consensus from multiple models before major decisions:

```bash
/ensemble-opinion "Should we use Redis or Memcached for session storage?"
/ensemble-opinion "Best approach for real-time notifications: WebSockets or SSE?"
```

**Returns:**
- Codex's opinion
- Codex's opinion
- Gemini's opinion
- Consensus summary

### Comprehensive Assessments

Every 3 PRs, run deep analysis:

```bash
/repo-assessment
```

**Codex analyzes:**
- Last 3 PRs for patterns
- Recurring issues
- Workflow friction points
- Missing automation opportunities
- Improvement recommendations

**Output:** PR with specific improvements to CrossCheck workflow.

---

## Custom Hook Integration

**Add your own logic to git hooks:**

### Create Custom Hook

```bash
# Create custom hook directory
mkdir -p ~/.codex/git-hooks/custom

# Create your hook
vim ~/.codex/git-hooks/custom/my-check.sh
```

**Example custom hook:**

```bash
#!/bin/bash
# ~/.codex/git-hooks/custom/my-check.sh

# Check for specific pattern in staged files
STAGED=$(git diff --cached --name-only)

for FILE in $STAGED; do
    if grep -q "MY_PATTERN" "$FILE" 2>/dev/null; then
        echo "❌ Found MY_PATTERN in $FILE"
        echo "   Please remove before committing"
        exit 1
    fi
done

echo "✅ Custom check passed"
exit 0
```

### Integrate with Existing Hook

```bash
# Make custom hook executable
chmod +x ~/.codex/git-hooks/custom/my-check.sh

# Add to pre-commit hook
echo "" >> ~/.codex/git-hooks/pre-commit
echo "# Custom check" >> ~/.codex/git-hooks/pre-commit
echo "~/.codex/git-hooks/custom/my-check.sh || exit 1" >> ~/.codex/git-hooks/pre-commit
```

### Hook Directory Structure

```
~/.codex/git-hooks/
├── pre-commit           # Main hook
├── commit-msg          # Conventional commits
├── post-commit         # Progress tracking
├── post-checkout       # Process cleanup
├── pre-push            # Quality gates
├── post-merge          # Branch cleanup
└── custom/             # Your hooks
    ├── my-check.sh
    ├── security-scan.sh
    └── performance-check.sh
```

---

## Per-Repo Overrides

**Different repos need different rules:**

### Install Hooks Per-Repo

```bash
cd ~/special-project

# Install hooks locally (not global) -- no flag needed, auto-detects repo
~/.crosscheck/scripts/install-git-hooks.sh

# Hooks are installed to $(git rev-parse --git-common-dir)/hooks/
# This works correctly in both regular repos and worktrees
```

### Customize Repo-Specific Hooks

```bash
# Edit local hook (doesn't affect other repos)
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
vim "$HOOKS_DIR/pre-commit"

# Example: Disable secrets detection for this repo
# Comment out the secrets check section
```

### Per-Repo Customization

To customize hooks for a specific repo, edit the hooks directly after installing locally:

```bash
# Install locally first
~/.crosscheck/scripts/install-git-hooks.sh

# Then edit the local copy
vim "$(git rev-parse --git-common-dir)/hooks/pre-commit"
```

---

## Advanced Customization

### Adjust Hook Behavior

**Location:** `~/.codex/git-hooks/`

#### Pre-Commit Customization

```bash
vim ~/.codex/git-hooks/pre-commit
```

**Common tweaks:**

```bash
# 1. TODO/FIXME markers
# Note: pre-commit does NOT block on TODO markers.
# The pre-push hook warns about TODO/FIXME/WIP in committed code
# but allows push in non-interactive mode. To suppress warnings,
# edit ~/.codex/git-hooks/pre-push and comment out the markers check.

# 2. Disable secrets detection for specific patterns
# Add to exceptions:
if ! echo "$SECRET_CHECK" | grep -v "MY_SAFE_PATTERN"; then
    # Not actually a secret
    continue
fi

# 3. Skip timestamp checks for certain files
# Add to exclusions:
EXCLUDE_TIMESTAMP="README.md|CHANGELOG.md|MY_FILE.md"
```

#### Commit-Msg Customization

```bash
vim ~/.codex/git-hooks/commit-msg
```

**Custom commit types:**

```bash
# Add your commit types (default: feat, fix, docs, style, refactor, test, chore)
ALLOWED_TYPES="feat|fix|docs|style|refactor|test|chore|perf|ci|build"

# Require ticket number
if ! echo "$MSG" | grep -qE "^(feat|fix): #[0-9]+"; then
    echo "❌ feat/fix commits must include ticket number: feat: #123 description"
    exit 1
fi
```

#### Pre-Push Customization

```bash
vim ~/.codex/git-hooks/pre-push
```

**Adjust required checks:**

```bash
# Default: /techdebt && /pre-pr-check
# Custom: Add your check
REQUIRED_CHECKS="/techdebt && /pre-pr-check && /my-custom-check"

# Or disable for feature branches
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
    echo "✅ Feature branch - skipping pre-push checks"
    exit 0
fi
```

### Customize Settings

**Location:** `~/.codex/settings.json`

#### Language-Specific Permissions

```json
{
  "permissions": {
    "allow": [
      "Bash(git*)",
      "Bash(npm*)",
      "Bash(node*)",
      // Add your languages:
      "Bash(python*)",    // Python projects
      "Bash(cargo*)",     // Rust projects
      "Bash(go*)",        // Go projects
      "Bash(ruby*)",      // Ruby projects
      "Bash(mvn*)",       // Java projects
      "Bash(dotnet*)"     // C# projects
    ]
  }
}
```

**Remove languages you don't use to tighten security.**

#### Custom CLI Tools

```json
{
  "permissions": {
    "allow": [
      // Platform tools
      "Bash(vercel*)",      // Vercel
      "Bash(netlify*)",     // Netlify
      "Bash(supabase*)",    // Supabase
      "Bash(stripe*)",      // Stripe
      "Bash(aws*)",         // AWS CLI
      "Bash(gcloud*)",      // Google Cloud
      "Bash(heroku*)",      // Heroku

      // Your custom tools
      "Bash(myapp*)",       // Your app CLI
      "Bash(deploy*)",      // Your deploy scripts
      "Bash(backup*)"       // Your backup scripts
    ]
  }
}
```

#### Model Selection

```json
{
  "model": "sonnet"  // Default: fast and cost-effective
}
```

**Options:**
- `"sonnet"` - Fast, cost-effective (recommended for daily work)
- `"opus"` - Most capable, slower, expensive (complex tasks)
- `"haiku"` - Fastest, cheapest (simple tasks)

#### Understanding Permission Model

**Three levels:**

```json
{
  "permissions": {
    "allow": [
      "Bash(git*)",      // ✅ Runs without asking
      "Bash(npm*)"
    ],
    "ask": [
      "WebFetch(*)"      // ⚠️ Prompts for approval
    ],
    "deny": [
      "Bash(rm*)",       // ❌ Blocked completely
      "Bash(sudo*)"
    ]
  }
}
```

**Deny list protects against:**
- `rm` - Prevents accidental deletions (use `mv file garbage/`)
- `git reset --hard` - Prevents data loss
- `.env` reads - Prevents secret leaks
- `sudo` - Prevents privilege escalation
- `docker` - Prevents container access outside sandbox
- `while read` loops - Prevents infinite loops

**Never remove items from deny list without understanding implications.**

#### Avoid Malformed Permissions

When Codex asks for approval:

- ✅ **"Once"** for complex commands (heredocs, long arguments)
- ⚠️ **"Always"** only for simple, repeatable patterns
- ❌ **Never "Always"** for 200+ character commands

**Why:** "Always" creates a permission rule. Complex commands with heredocs or long arguments create malformed rules that break settings.json.

---

## Verification Procedures

### Verify Codex Review Logging

**Check log file exists:**

```bash
ls -la ~/.codex/codex-commit-reviews.log
# Should see: -rw-r--r-- with recent timestamp
```

**Test logging manually:**

```bash
# Make a feature commit
git commit -m "feat: test codex review logging"

# Check the log
tail -5 ~/.codex/codex-commit-reviews.log
# Should see review prompt for this commit
```

**Log format:**

```
=== Commit Review Needed: 2026-02-09 16:30:00 ===
Quick commit review - this is a git post-commit hook so keep feedback brief.

Commit: abc123d...
Message: feat: test codex review logging
[review prompt here]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**If not logging:**

```bash
# Create log file
touch ~/.codex/codex-commit-reviews.log

# Make writable
chmod 644 ~/.codex/codex-commit-reviews.log

# Test again
echo "test" >> ~/.codex/codex-commit-reviews.log
cat ~/.codex/codex-commit-reviews.log
```

### Verify Git Hooks

**Check hooks are installed:**

```bash
# Global hooks
git config --global core.hooksPath
# Should see: ~/.codex/git-hooks

# Or local hooks (use git-common-dir for worktree compatibility)
ls -la "$(git rev-parse --git-common-dir)/hooks/"
# Should see executable hooks
```

**Test each hook:**

```bash
# Pre-commit
echo "test" > test.txt
git add test.txt
git commit -m "test: hook verification"
# Should run pre-commit checks

# Commit-msg
git commit -m "bad message"
# Should fail: "must follow conventional commits"

# Pre-push
git push
# Should check for quality gates (if pushing to main)

# Post-merge
git merge some-branch
# Should auto-delete merged branch
```

---

## Troubleshooting Advanced Setups

### Custom Hook Not Running

```bash
# Check hook is executable
ls -la ~/.codex/git-hooks/custom/my-hook.sh
# Should see: -rwxr-xr-x

# Make executable
chmod +x ~/.codex/git-hooks/custom/my-hook.sh

# Check it's called from main hook
grep "my-hook.sh" ~/.codex/git-hooks/pre-commit
# Should see the call

# Test manually
~/.codex/git-hooks/custom/my-hook.sh
# Should run and show output
```

### Per-Repo Override Not Working

```bash
# Check local hooks override global
git config core.hooksPath
# Should be empty (local hooks) or point to git-common-dir/hooks

# Unset global hooks for this repo
git config --unset core.hooksPath

# Verify local hooks exist
ls -la "$(git rev-parse --git-common-dir)/hooks/"
# Should see hooks
```

### Settings.json Syntax Error

```bash
# Validate JSON
cat ~/.codex/settings.json | python -m json.tool
# Should show formatted JSON or error

# Common issues:
# - Trailing commas
# - Missing quotes
# - Unescaped characters in patterns

# Fix by comparing to template
diff ~/.codex/settings.json ~/.crosscheck/settings.template.json
```

---

## Related Documentation

- **[README.md](README.md#detailed-setup)** - Setup guide
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues
- **[CODEX.md](CODEX.md)** - Daily workflow
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design
