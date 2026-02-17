---
name: list-worktrees
description: List all active git worktrees
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-16-00

# List Git Worktrees

Display all active git worktrees and their status.

## Usage

```bash
/list-worktrees
```

## What This Shows

### 1. All Active Worktrees

```bash
git worktree list
```

**Output:**
```
/Users/you/projects/repo              abc123 [main]
/Users/you/projects/worktrees/repo-auth   def456 [feature-auth]
/Users/you/projects/worktrees/repo-ui     ghi789 [feature-ui]
```

### 2. Enhanced Information

For each worktree, show:
- **Path**: Where the worktree lives
- **Branch**: Current branch name
- **Commit**: Latest commit hash
- **PR Status**: Has PR? Merged?
- **PR Counter**: How many PRs merged in this worktree
- **Last Activity**: Last commit timestamp

**Enhanced Output:**
```
📁 Worktrees for repo-name:

1. Main Worktree
   Path: /Users/you/projects/repo
   Branch: main
   Commit: abc123 (2 hours ago)
   PR Counter: 5/3 (next assessment in 1 PR)

2. Feature: Authentication
   Path: ../worktrees/repo-feature-auth
   Branch: feature-auth
   Commit: def456 (30 mins ago)
   PR: #123 (open, in review)
   PR Counter: 0/3

3. Feature: UI Redesign
   Path: ../worktrees/repo-feature-ui
   Branch: feature-ui
   Commit: ghi789 (5 mins ago)
   PR: Not created yet
   PR Counter: 0/3
```

## Quick Actions

After listing, suggest actions:

```
Quick Actions:
- cd ../worktrees/repo-<branch>  - Jump to worktree (manual cd)
- /cleanup-worktrees             - Remove finished worktrees
- /create-worktree <name>        - Create new worktree
```

## Implementation

```bash
# Get worktree list
git worktree list --porcelain

# For each worktree:
# - Get branch name
# - Get latest commit
# - Check if PR exists (gh pr list)
# - Read PR counter from git-common-dir (shared across all worktrees)
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE" 2>/dev/null || echo "0"
# - Get last commit time

# Display formatted output
```

## Use Cases

### Morning Check-In

```bash
# See what's in flight
/list-worktrees

# Output shows:
# - Main: 5 PRs (assessment needed)
# - Auth: PR #123 waiting for review
# - UI: Work in progress
# - Login fix: Merged, can cleanup
```

### Before Creating New Worktree

```bash
# Check capacity first
/list-worktrees

# If showing 5+ worktrees, clean up first
/cleanup-worktrees

# Then create new
/create-worktree new-feature
```

### End of Day Review

```bash
# See status of all parallel work
/list-worktrees

# Example output:
# 3 PRs submitted today
# 1 PR merged
# 2 PRs in review
# 1 feature still in progress
```

## Visual Indicators

**Status Icons:**
- 🟢 Main worktree
- 🔵 Active development
- 🟡 PR submitted, in review
- ✅ PR merged, ready to cleanup
- ⚠️  Stale (no commits in 7+ days)
- 🔴 Conflicts detected

## Related Commands

- `/create-worktree` - Create new worktree
- `cd` - Jump to different worktree (manual cd)
- `/cleanup-worktrees` - Remove finished worktrees
