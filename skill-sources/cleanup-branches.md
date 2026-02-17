---
name: cleanup-branches
description: Batch git branch cleanup - generates single approval script
---

# Git Branch Cleanup (Batched)

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

This skill analyzes git branches and generates a SINGLE bash script for you to approve and run, eliminating the need for individual permission approvals on each `git branch -D` command.

## Process

1. **Analyze all local branches**
   - Get list of all branches
   - Check merge status
   - Check remote tracking status
   - Check last commit date

2. **Categorize branches for deletion**

   **Safe to delete (merged):**
   - Branches fully merged to main/master
   - No unique commits

   **Stale branches:**
   - No remote tracking branch
   - Last commit > 14 days ago
   - Not currently checked out

   **Pattern-based candidates:**
   - temp-*, test-*, wip-*, experiment-*
   - feature/* that are merged
   - bugfix/* that are merged

3. **Generate cleanup script**
   - Group by category with comments
   - Add safety check (show what will be deleted)
   - Make copyable for user approval

4. **Present summary + script**

## Output Format

```bash
#!/bin/bash
# Git Branch Cleanup Script
# Generated: [timestamp]
# Review carefully before running!

echo "🔍 Branches to be deleted:"
echo ""

# === MERGED BRANCHES (Safe) ===
echo "Merged branches (safe):"
git branch -D feature/completed-work    # Merged to main on 2026-01-15
git branch -D bugfix/old-fix           # Merged to main on 2026-01-10

# === STALE BRANCHES (No remote, >14 days) ===
echo ""
echo "Stale branches (no remote, >14 days old):"
git branch -D temp-experiment          # Last commit: 2025-12-20
git branch -D wip-abandoned           # Last commit: 2025-12-15

# === PATTERN-BASED ===
echo ""
echo "Pattern-based cleanup:"
git branch -D test-something          # Matches test-* pattern

echo ""
echo "✅ Cleanup complete! Deleted X branches."
```

## Critical Rules

**NEVER run git branch -D commands directly** - This skill ONLY generates scripts for user approval.

**Safety checks before including in script:**
- Branch is not currently checked out
- Branch is not main/master/develop
- Branch is not protected by name patterns (release-*, hotfix-*)
- For stale branches: verify no unpushed commits

## Usage

```bash
# In any git repository
/cleanup-branches

# Review the generated script
# Copy and run if approved
```

## Execution

When invoked, perform these steps:

1. Run `git branch -a` to get all branches
2. For each local branch, check:
   - `git branch --merged main` (or master)
   - `git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/`
   - `git log -1 --format=%ci <branch>` for last commit date
3. Categorize branches based on analysis
4. Generate the script with clear categorization
5. Present summary statistics
6. Show the copyable script
7. Remind user to review before running

**Do NOT:**
- Run any git branch -D commands yourself
- Delete branches without user explicitly running the script
- Include branches with unpushed commits
- Include protected branch patterns

**Example output:**

```
📊 Branch Analysis Complete

Found 40 total local branches:
- 11 merged to main (safe to delete)
- 8 stale (no remote, >14 days old)
- 3 pattern-based (temp-*, test-*)
- 18 active (keeping)

Generated cleanup script below ↓

Copy and run this script to delete 22 branches:

[script here]

⚠️  Review carefully before running!
```
