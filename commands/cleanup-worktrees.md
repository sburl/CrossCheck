---
name: cleanup-worktrees
description: Remove merged or abandoned git worktrees
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

# Cleanup Git Worktrees

Remove worktrees that are finished (PR merged) or abandoned (stale).

## Usage

```bash
/cleanup-worktrees
```

## What This Does

### Step 1: Identify Cleanup Candidates

**Auto-cleanup criteria:**
- ✅ PR merged to main
- ✅ Branch deleted on remote
- ✅ No uncommitted changes
- ⚠️  No commits in 7+ days (ask before removing)

**Keep (don't cleanup):**
- ❌ PR still open
- ❌ PR in review
- ❌ Uncommitted changes
- ❌ Active work (recent commits)

### Step 2: Interactive Selection

```bash
Found 3 worktrees eligible for cleanup:

1. ✅ feature-auth (PR #123 merged 2 days ago)
   Path: ../worktrees/repo-feature-auth
   Safe to remove

2. ✅ bugfix-login (PR #124 merged 1 week ago)
   Path: ../worktrees/repo-bugfix-login
   Safe to remove

3. ⚠️  feature-old (no commits in 14 days)
   Path: ../worktrees/repo-feature-old
   Stale - review before removing

Remove these worktrees? [Y/n/selective]
```

### Step 3: Remove Worktrees

```bash
# For each selected worktree:

# 1. Verify no uncommitted changes
git -C "$WORKTREE_PATH" status --porcelain

# 2. Remove worktree
git worktree remove "$WORKTREE_PATH"

# 3. Remove directory
rm -rf "$WORKTREE_PATH"

# 4. Prune worktree references
git worktree prune

# 5. Delete local branch (if merged)
git branch -d "$BRANCH_NAME"
```

## Safety Checks

Before removing any worktree:

✅ **Verify PR merged:**
```bash
gh pr view $PR_NUMBER --json state,mergedAt
```

✅ **Verify no uncommitted changes:**
```bash
git status --porcelain
# If output = empty, safe to remove
```

✅ **Verify branch on remote deleted:**
```bash
git ls-remote --heads origin $BRANCH_NAME
# If not found, safe to remove local
```

✅ **Ask user confirmation:**
```bash
# Always confirm before deletion
# Show what will be deleted
# Allow selective removal
```

## Modes

### Safe Mode (Default)

Only removes worktrees where:
- PR is merged
- Branch deleted on remote
- No uncommitted changes
- User confirms

### Aggressive Mode

```bash
/cleanup-worktrees --aggressive
```

Also considers for removal:
- Worktrees with no commits in 7+ days
- Closed PRs (even if not merged)
- Abandoned branches

Still requires user confirmation.

### Dry Run

```bash
/cleanup-worktrees --dry-run
```

Shows what would be removed without actually removing.

## Example Session

```bash
# Check current worktrees
/list-worktrees

# Output:
# 1. Main (clean)
# 2. feature-auth (PR #123 merged yesterday) ← Can cleanup
# 3. feature-ui (PR #124 in review) ← Keep
# 4. bugfix-login (PR #125 merged last week) ← Can cleanup
# 5. feature-experimental (stale, 30 days) ← Ask user

# Run cleanup
/cleanup-worktrees

# Interactive prompts:
# Remove feature-auth? [Y/n] y
# Remove bugfix-login? [Y/n] y
# Remove feature-experimental? [Y/n] n (keeping for later)

# Result:
# ✅ Removed feature-auth
# ✅ Removed bugfix-login
# ⏭️  Kept feature-experimental
# 📊 2 worktrees removed, 3 remaining
```

## After Cleanup

Report what was removed:

```bash
✅ Cleanup Complete!

Removed:
- feature-auth (PR #123 merged)
- bugfix-login (PR #125 merged)

Kept:
- Main (main branch)
- feature-ui (PR #124 in review)
- feature-experimental (user choice)

Disk space freed: 150 MB

Current worktrees: 3
Run /list-worktrees to see details
```

## Best Practices

### Clean Up Regularly

**After merging PR:**
```bash
# Immediately after merge
/cleanup-worktrees
```

**Weekly cleanup:**
```bash
# Every Friday
/cleanup-worktrees
```

**Before creating new worktrees:**
```bash
# Check capacity
/list-worktrees

# If 5+ worktrees, cleanup first
/cleanup-worktrees

# Then create new
/create-worktree new-feature
```

### Stale Worktree Detection

Worktrees with no commits in 7+ days:

**Week 1:** Warning (⚠️ )
**Week 2:** Suggest cleanup
**Week 3+:** Aggressive cleanup suggestion

## Preserving Work

### Before Cleanup: Archive Important Branches

```bash
# If worktree has work you might need later
cd ../worktrees/repo-experimental

# Push to remote for safekeeping
git push origin feature-experimental

# Then safe to cleanup worktree
# Branch preserved on remote
```

### Recovering Deleted Worktree

If you need the work again:

```bash
# Branch still exists on remote
/create-worktree feature-experimental origin/feature-experimental

# Or just checkout locally
git checkout feature-experimental
```

## Automation

### Auto-Cleanup After Merge

Add to git hook or GitHub Actions:

```bash
# After PR merge, trigger cleanup
gh pr merge $PR_NUMBER && /cleanup-worktrees --auto
```

### Scheduled Cleanup

```bash
# Weekly cron job
0 9 * * 5 /cleanup-worktrees --stale --auto
```

## Troubleshooting

### Worktree Won't Remove

```bash
# Error: worktree locked
git worktree remove --force ../worktrees/repo-feature

# Error: uncommitted changes
# Either commit them or stash
cd ../worktrees/repo-feature
git add . && git commit -m "WIP"
# Or: git stash
# Then retry cleanup
```

### Branch Still Exists After Cleanup

```bash
# Cleanup removes worktree but may keep branch
# To also delete local branch:
git branch -D feature-name

# To delete remote branch:
git push origin --delete feature-name
```

## Related Commands

- `/list-worktrees` - See all worktrees
- `/create-worktree` - Create new worktree
- `cd` - Switch to different worktree (manual cd)

## Team Tip

> "Don't let worktrees accumulate. Clean up merged branches immediately. Keep your workspace lean - only active work should have worktrees."

**Ideal state:** 3-5 active worktrees max, all with recent commits.
