---
name: create-worktree
description: Create new git worktree for parallel development
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-16-00

# Create Git Worktree

Create a new git worktree to work on multiple features in parallel. This is the **#1 productivity tip** from the Codex team.

## What Are Worktrees?

> "Spin up 3-5 git worktrees at once, each running its own Codex session in parallel. It's the single biggest productivity unlock." -- Boris Cherny (Claude Code creator)

Git worktrees let you have **multiple working directories** from the same repo:
- Each worktree = separate feature/branch
- Each worktree = separate Codex session
- Work on 3-5 features simultaneously
- No branch switching, no context loss

## Usage

```bash
/create-worktree <branch-name> [base-branch]
```

**Examples:**
```bash
/create-worktree feature-auth          # Create from current branch
/create-worktree feature-auth main     # Create from main
/create-worktree bugfix-login develop  # Create from develop
```

## What This Does

### Step 1: Create Worktree Directory

```bash
# Worktrees live in ../worktrees/
REPO_NAME=$(basename $(git rev-parse --show-toplevel))
WORKTREE_DIR="../worktrees/${REPO_NAME}-${BRANCH_NAME}"

# Create worktree
git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" "$BASE_BRANCH"
```

### Step 2: Initialize Automation

```bash
cd "$WORKTREE_DIR"

# Copy .codex structure from main worktree
cp -r /path/to/main/.codex .codex/

# Initialize fresh PR counter (managed by post-merge hook)
# In worktrees, git-common-dir points to the main repo's .git dir,
# so the counter is shared across all worktrees automatically.
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE" 2>/dev/null || echo "0" > "$COUNTER_FILE"

# Copy CODEX.md
cp /path/to/main/CODEX.md ./
```

### Step 3: Launch Codex Session

```bash
# Open new terminal tab/window
# Name it after the branch
# cd to worktree directory
# Launch Codex

# Provide instructions:
echo "✅ Worktree created: $WORKTREE_DIR"
echo ""
echo "Next steps:"
echo "1. Open new terminal tab"
echo "2. cd $WORKTREE_DIR"
echo "3. Run: codex"
echo ""
echo "You can now work on $BRANCH_NAME in parallel!"
echo "(CODEX.md will be auto-loaded in the worktree)"
```

## Directory Structure

After creating worktrees:

```
your-repo/                    ← Main worktree
├── .git/
│   └── hooks-pr-counter      (PR counter -- shared by all worktrees)
├── .codex/
└── [code]

worktrees/
├── your-repo-feature-auth/   ← Worktree 1
│   ├── .codex/
│   └── [code on feature-auth branch]
├── your-repo-feature-ui/     ← Worktree 2
│   ├── .codex/
│   └── [code on feature-ui branch]
└── your-repo-bugfix-login/   ← Worktree 3
    ├── .codex/
    └── [code on bugfix-login branch]
```

## Workflow: Parallel Development

### Terminal Setup

**Tab 1: Main** (main branch)
```bash
~/projects/your-repo
Branch: main
Codex: Coordinating, reviewing
```

**Tab 2: Feature Auth** (feature-auth branch)
```bash
~/projects/worktrees/your-repo-feature-auth
Branch: feature-auth
Codex: Building auth system
```

**Tab 3: Feature UI** (feature-ui branch)
```bash
~/projects/worktrees/your-repo-feature-ui
Branch: feature-ui
Codex: Designing new UI
```

**Tab 4: Bugfix** (bugfix-login branch)
```bash
~/projects/worktrees/your-repo-bugfix-login
Branch: bugfix-login
Codex: Fixing login bug
```

### Parallel Work Example

```bash
# Morning: Spin up 3 worktrees
/create-worktree feature-auth
/create-worktree feature-ui
/create-worktree bugfix-login

# Each worktree gets own Codex session
# All work in parallel

# Feature Auth Codex: Implementing OAuth
# Feature UI Codex: Building new dashboard
# Bugfix Codex: Fixing login race condition

# All independent, no context switching!
```

## PR Counter Sharing

All worktrees share a **single PR counter** because `git rev-parse --git-common-dir`
resolves to the main repo's `.git` directory regardless of which worktree you are in.
The counter file is `$(git rev-parse --git-common-dir)/hooks-pr-counter`.

```bash
# All worktrees read/write the same counter:
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE"  # Same value from any worktree
```

This means the assessment waterfall triggers based on total PRs merged across all
worktrees, not per-worktree -- which is the desired behavior since assessments
cover the whole repo.

## Benefits

✅ **3-5x productivity** - Work on multiple features simultaneously
✅ **No context switching** - Each feature has dedicated environment
✅ **No branch conflicts** - Separate working directories
✅ **Independent Codex sessions** - Each with own context
✅ **Parallel PRs** - Submit multiple PRs without blocking

## Best Practices

### 1. Name Terminal Tabs
```bash
# Tab names:
"Main"
"Auth Feature"
"UI Redesign"
"Login Fix"
```

### 2. Color-Code Tabs
Use terminal color settings to visually distinguish worktrees

### 3. Use /statusline
```bash
# In each worktree, show branch name
/statusline set-format "{{branch}} | {{context}}%"
```

### 4. Limit Active Worktrees
- Don't exceed 5 active worktrees
- Codex team uses 3-5
- More = harder to manage

### 5. Clean Up When Done
```bash
# After merging PR, remove worktree
/cleanup-worktrees
```

## Advanced: Tmux Setup

For tmux users:

```bash
# Create tmux session per worktree
tmux new-session -s "auth-feature" -c "$WORKTREE_DIR"

# Switch between sessions
tmux attach -t "auth-feature"
tmux attach -t "ui-feature"
```

## Troubleshooting

### Worktree Creation Fails

```bash
# Check if branch already exists
git branch -a | grep feature-name

# If exists, use different name or checkout existing
git worktree add ../worktrees/repo-feature -b feature-v2
```

### Can't Delete Worktree

```bash
# Remove worktree properly
git worktree remove ../worktrees/repo-feature

# If locked, force remove
git worktree remove --force ../worktrees/repo-feature
```

### Shared .git Directory

All worktrees share `.git` directory:
- Commits in any worktree are visible in all
- Fetch/pull in one affects all
- Be mindful of this shared state

## Related Commands

- `cd ../worktrees/repo-<branch>` - Switch between worktrees (manual cd)
- `/list-worktrees` - See all active worktrees
- `/cleanup-worktrees` - Remove merged/abandoned worktrees

## Example Session

```bash
# Monday morning: Three features to build
/create-worktree feature-payment-gateway main
/create-worktree feature-notification-system main
/create-worktree feature-user-settings main

# Open 3 terminal tabs, start 3 Codex sessions

# Tab 1: Payment Gateway
cd ../worktrees/repo-feature-payment-gateway
codex
# CODEX.md auto-loaded
# "Build Stripe integration"

# Tab 2: Notifications
cd ../worktrees/repo-feature-notification-system
codex
# CODEX.md auto-loaded
# "Build push notification system"

# Tab 3: User Settings
cd ../worktrees/repo-feature-user-settings
codex
# CODEX.md auto-loaded
# "Build user preferences UI"

# All three Codex instances work in parallel
# Submit 3 PRs by end of day
# Main branch never touched
```

