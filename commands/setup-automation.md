---
name: setup-automation
description: Install all automation for a new repo (git hooks + GitHub Actions)
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-12-12-00

# Setup Automation for Claude Code Workflow

Installs all automation tools for autonomous operation in the current repo.

## EXECUTION INSTRUCTIONS FOR CLAUDE

When this skill is invoked, do the following:

1. **Run the bootstrap script (if first-time setup):**
   ```bash
   ~/.claude/CrossCheck/scripts/bootstrap-crosscheck.sh
   ```
   This clones/updates CrossCheck, installs settings, and offers to install git hooks globally.

2. **Or install git hooks for the current repo only:**
   ```bash
   ~/.claude/CrossCheck/scripts/install-git-hooks.sh
   ```

3. **Then follow Steps 1-5 below** to initialize repo structure, GitHub config, and workflow docs.

4. **After setup, tell the user:**
   ```
   Setup complete! Automation installed for this repo.

   IMPORTANT: You need to restart Claude Code for skills to work in future sessions:

   1. Exit: exit
   2. Restart: claude

   Skills like /submit-pr and /plan are loaded at startup.
   ```

**IMPORTANT:** Skills are loaded at startup. The user MUST restart Claude Code after running setup for the first time.

---

## What Gets Installed

### Git Hooks (Local)
- **post-merge**: Auto-increment PR counter on merges
- **pre-commit**: Check doc timestamps before commits
- **post-checkout**: Context management reminders

### GitHub Actions (CI/CD)
- **PR checks**: Documentation timestamp verification

### Repository Files
- `$(git rev-parse --git-common-dir)/hooks-pr-counter`: PR counter (managed by post-merge hook)
- `.claude/assessment-history.txt`: Assessment log
- `garbage/`: Folder for safe file deletion (gitignored)
- `do-work/`: Task queue for autonomous agent work
- `user-content/`: Human-only zone (protected by pre-commit hook)
- `.gitignore`: Updated with garbage folder

## Installation Steps

### Step 1: Install Git Hooks

```bash
~/.claude/CrossCheck/scripts/install-git-hooks.sh
```

This installs local git hooks that trigger during your git operations.

### Step 2: Install GitHub Actions (Optional)

If you want CI/CD automation:

```bash
# Create workflows directory
mkdir -p .github/workflows

# Copy quality gates workflow from CrossCheck
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$HOME/.claude/CrossCheck}"
cp "$CROSSCHECK_DIR/.github/workflows/quality-gates.yml" .github/workflows/quality-gates.yml

# Commit and push
git add .github/workflows/quality-gates.yml
git commit -m "feat: add quality gates CI workflow"
git push
```

### Step 3: Initialize Repo Structure

```bash
# Create .claude directory
mkdir -p .claude

# Initialize PR counter (managed by post-merge hook in git-common-dir)
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
echo "0" > "$COUNTER_FILE"

# Create empty history file
touch .claude/assessment-history.txt

# Create standard directories
mkdir -p garbage      # Safe file deletion (gitignored)
mkdir -p do-work      # Task queue for autonomous work
mkdir -p user-content      # Human-only zone (hook-protected)

# Add READMEs to tracked directories (if not already present)
SETUP_DATE=$(date +"%Y-%m-%d-%H-%M")

if [ ! -f "do-work/README.md" ]; then
    cat > do-work/README.md << DOWORK
**Created:** $SETUP_DATE
**Last Updated:** $SETUP_DATE

# Task Queue

Drop .md files here for the agent to process with /do-work.
Numbers 001-099 are for humans. 100+ are for agents.
See /do-work skill for full details.
DOWORK
fi

if [ ! -f "user-content/README.md" ]; then
    cat > user-content/README.md << CONTENT
**Created:** $SETUP_DATE
**Last Updated:** $SETUP_DATE

# Content (Human-Only Zone)

Agents may read files here for context but must never modify them.
Protected by pre-commit hook.
CONTENT
fi

# Update .gitignore
if ! grep -q "^garbage/$" .gitignore 2>/dev/null; then
    echo "garbage/" >> .gitignore
fi

# Commit structure
git add .claude/ .gitignore
git commit -m "chore: initialize Claude Code automation structure"
git push
```

### Step 4: GitHub Configuration

```bash
# Create GitHub config directory
mkdir -p .github/rulesets

# CODEOWNERS -- set default reviewer
if [ ! -f ".github/CODEOWNERS" ]; then
    GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "YOUR_GITHUB_USERNAME")
    cat > .github/CODEOWNERS << OWNERS
# Default code owner for all files
* @${GITHUB_USER}
OWNERS
fi

# Dependabot -- dependency update monitoring
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$HOME/.claude/CrossCheck}"
if [ ! -f ".github/dependabot.yml" ]; then
    cp "$CROSSCHECK_DIR/.github/dependabot.yml" .github/dependabot.yml
    echo "  Edit .github/dependabot.yml to uncomment ecosystems you use (npm, pip, docker)"
fi

# Branch protection ruleset template
if [ ! -f ".github/rulesets/protect-main.json" ]; then
    cp "$CROSSCHECK_DIR/.github/rulesets/protect-main.json" .github/rulesets/protect-main.json
    echo "  Import .github/rulesets/protect-main.json via GitHub Settings > Rules > Rulesets"
fi

git add .github/
git commit -m "chore: add GitHub config (CODEOWNERS, dependabot, branch protection)"
```

### Step 5: Copy Workflow Documentation

```bash
# Copy CLAUDE.md to repo
CROSSCHECK_DIR="${CROSSCHECK_DIR:-$HOME/.claude/CrossCheck}"
cp "$CROSSCHECK_DIR/CLAUDE.md" ./CLAUDE.md

# Customize for your project
# Edit CLAUDE.md with project-specific details

# Commit
git add CLAUDE.md
git commit -m "docs: add workflow documentation"
git push
```

## Verification

After installation, verify everything works:

### Test Git Hooks

```bash
# Test pre-commit hook
echo "# Test Doc" > test.md
git add test.md
git commit -m "test: verify pre-commit hook"
# Should warn about missing timestamp

# Test post-checkout hook
git checkout -b test-branch
# Should show context management tip
git checkout main
git branch -d test-branch
```

### Test PR Counter

The PR counter is managed automatically by the `post-merge` git hook, stored at
`$(git rev-parse --git-common-dir)/hooks-pr-counter`. No separate script is needed.

```bash
# Check counter status
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE" 2>/dev/null || echo "0 (counter not yet initialized)"

# Manually increment to test
echo "1" > "$COUNTER_FILE"

# Reset for actual use
echo "0" > "$COUNTER_FILE"
```

### Test GitHub Actions (if installed)

```bash
# Create a test PR
git checkout -b test-automation
echo "test" >> README.md
git add README.md
git commit -m "test: automation"
git push -u origin test-automation
gh pr create --title "Test Automation" --body "Testing workflow"

# Check GitHub Actions tab - should see workflow running
gh pr close --delete-branch
```

## What Happens Automatically Now

### Before (Manual)
```bash
# Finish feature
/pre-pr-check
gh pr create
/pr-review
# ... review process ...
# Manually track PR count
# Check if 3 PRs
/repo-assessment  # ← Manual
# Manually reset counter
```

### After (Automated)
```bash
# Finish feature
/submit-pr  # ← Combines pre-check + PR creation + review start
# ... review process ...
git merge  # ← Automatically increments counter via git hook
# Automatic assessment reminder if 3 PRs
/repo-assessment  # ← When prompted
# Counter automatically resets via git hook
```

## Automation Summary

| Action | Manual | Automated | How |
|--------|--------|-----------|-----|
| Pre-PR checks | ❌ Manual `/pre-pr-check` | ✅ Auto in `/submit-pr` | Combined command |
| Create PR | ❌ Manual `gh pr create` | ✅ Auto in `/submit-pr` | Combined command |
| Start review | ❌ Manual `/pr-review` | ✅ Auto in `/submit-pr` | Combined command |
| Increment counter | ❌ Manual tracking | ✅ Auto on merge | post-merge git hook |
| Assessment reminder | ❌ Manual check | ✅ Auto notification | Git hook |
| Reset counter | ❌ Manual reset | ✅ Auto after assessment | post-merge git hook |
| Doc timestamp check | ❌ Manual verify | ✅ Auto before commit | Git hook |
| Context reminder | ❌ Manual remember | ✅ Auto on branch switch | Git hook |

## Customization

### Disable Specific Hooks

```bash
# Disable a hook by removing execute permission
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
chmod -x "$HOOKS_DIR/post-merge"

# Or rename it
mv "$HOOKS_DIR/post-merge" "$HOOKS_DIR/post-merge.disabled"
```

### Modify GitHub Actions

Edit `.github/workflows/quality-gates.yml` to customize:
- Markdown lint rules
- Shellcheck severity
- Link check configuration
- Documentation metadata requirements

### Change Assessment Threshold

Default is 3 PRs. To change to 5:

```bash
# In git hooks (source of truth):
# Edit ~/.claude/CrossCheck/git-hooks/post-merge
# Change: if [ "$pr_count" -ge 3 ]; then
# To: if [ "$pr_count" -ge 5 ]; then
# Then reinstall hooks: ~/.claude/CrossCheck/scripts/install-git-hooks.sh
```

## Troubleshooting

### Git hooks not running
```bash
# Verify hooks are executable
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
ls -la "$HOOKS_DIR/"

# Reinstall
~/.claude/CrossCheck/scripts/install-git-hooks.sh
```

### GitHub Actions not triggering
```bash
# Check workflow file exists
ls -la .github/workflows/quality-gates.yml

# Check GitHub Actions enabled
gh repo view --json hasIssuesEnabled,hasProjectsEnabled

# View workflow runs
gh run list --workflow=quality-gates.yml
```

### Counter not incrementing
```bash
# The PR counter is managed by the post-merge git hook.
# Counter file location:
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"

# Check counter file exists
ls -la "$COUNTER_FILE"

# Check the post-merge hook is installed and executable
ls -la "$(git rev-parse --git-common-dir)/hooks/post-merge"

# Manually set counter to test
echo "1" > "$COUNTER_FILE"
cat "$COUNTER_FILE"
```

## Uninstall

To remove automation:

```bash
# Remove git hooks
HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"
rm "$HOOKS_DIR/post-merge"
rm "$HOOKS_DIR/pre-commit"
rm "$HOOKS_DIR/post-checkout"

# Remove GitHub Actions
rm .github/workflows/quality-gates.yml

# Keep .claude/ directory (has counter history)
# Or remove completely:
# rm -rf .claude/
```

## Next Steps

After installation:

1. ✅ Automation installed
2. ✅ Test with practice PR
3. ✅ Customize CLAUDE.md for project
4. ✅ Start using `/submit-pr` for new features
5. ✅ Let automation handle tracking
6. ✅ Focus on coding, not process
