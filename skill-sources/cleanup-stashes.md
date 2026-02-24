---
name: cleanup-stashes
description: |
  Review and selectively drop git stashes. Lists all stashes with branch, age, and file
  summary. Flags stashes whose branch no longer exists (orphaned work) or has been merged
  to main (likely superseded), and stashes older than 14 days (likely forgotten).
  Generates a drop script for user approval — never drops stashes directly.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-24-12-53

# Git Stash Cleanup

Review accumulated stashes, surface orphaned or stale ones, and generate a drop script
for approval. Never drops stashes directly — always generates a script for the user to run.

## Usage

```bash
/cleanup-stashes             # Full review with drop script
/cleanup-stashes --dry-run   # Analysis only, no script generated
/cleanup-stashes --show <N>  # Show full diff for stash N, then continue
```

---

## Step 1: List All Stashes

```bash
git stash list --format="%gd | %gs | %ci"
```

If the output is empty, report "No stashes found." and stop.

For each stash, collect:
- Index: `stash@{N}`
- Branch it was created on (parsed from the stash message, e.g. `WIP on feat-auth: abc1234 message`)
- Date created
- Short message

---

## Step 2: Analyze Each Stash

For each stash, run:

```bash
# Files changed (stat summary — not full diff)
git stash show stash@{N} --stat

# Age in days
git log -1 --format="%cr" stash@{N}

# Check if branch still exists locally
git show-ref --verify --quiet refs/heads/<branch> && echo "exists" || echo "gone"

# Check if branch still exists on remote
git ls-remote --heads origin <branch> | grep -q . && echo "on remote" || echo "not on remote"

# Check if branch is merged to main
git branch --merged main | grep -q "^  <branch>$" && echo "merged" || echo "not merged"
```

---

## Step 3: Categorize

Assign each stash to exactly one category (first match wins):

| Category | Condition | Risk |
|----------|-----------|------|
| **Orphaned** | Branch gone locally AND not on remote | High — work may be lost if dropped |
| **Superseded** | Branch merged to main | Medium — likely safe, but show stat |
| **Stale** | Age > 14 days (branch still exists) | Medium — probably forgotten |
| **Recent** | Age ≤ 14 days | Low — likely intentional WIP |

---

## Step 4: Present Analysis

Print a summary grouped by category. For each stash show: index, branch, age, and the
`--stat` summary (files changed, insertions, deletions).

Example output:

```
📦 Stash Analysis — 5 stashes found

🔴 ORPHANED (branch no longer exists) — review carefully before dropping
  stash@{2}  feat-old-experiment     43 days ago
              3 files changed, 89 insertions(+)
              "WIP on feat-old-experiment: abc1234 add initial draft"

🟡 SUPERSEDED (branch merged to main)
  stash@{4}  feat-auth               22 days ago
              1 file changed, 4 insertions(+), 2 deletions(-)
              "WIP on feat-auth: def5678 tweak error message"

🟡 STALE (branch exists but stash is >14 days old)
  stash@{1}  feat-ui                 18 days ago
              5 files changed, 201 insertions(+)
              "WIP on feat-ui: ghi9012 modal work in progress"

🟢 RECENT (likely intentional WIP — keeping)
  stash@{0}  feat-payments            2 days ago
              2 files changed, 34 insertions(+)
              "WIP on feat-payments: jkl3456 stripe integration"
  stash@{3}  feat-payments            5 days ago
              1 file changed, 8 insertions(+)
              "WIP on feat-payments: jkl3456 add webhook handler"

Tip: run /cleanup-stashes --show <N> to see the full diff for any stash before deciding.
```

If `--dry-run` was passed, stop here.

---

## Step 5: Generate Drop Script

Group only the Orphaned, Superseded, and Stale stashes into the script.
Recent stashes are never included unless `--force` is passed.

**Important:** `git stash drop` indices shift after each drop. Always drop in
descending index order so earlier indices remain valid.

```bash
#!/bin/bash
# Git Stash Cleanup Script
# Generated: <timestamp>
# Review carefully — dropped stashes cannot be recovered.
#
# Run /cleanup-stashes --show <N> to inspect any stash before dropping.

echo "Stashes to be dropped:"
echo ""

# Drop in DESCENDING index order — indices shift after each drop,
# so highest N must go first to keep lower indices valid.

# === SUPERSEDED (branch merged to main) ===
echo "Superseded stashes (branch merged):"
git stash drop stash@{4}   # feat-auth, 22 days ago

# === ORPHANED (branch no longer exists) ===
echo ""
echo "Orphaned stashes (branch gone):"
git stash drop stash@{2}   # feat-old-experiment, 43 days ago

# === STALE (>14 days) ===
echo ""
echo "Stale stashes (>14 days old):"
git stash drop stash@{1}   # feat-ui, 18 days ago

echo ""
echo "Done. Dropped 3 stashes."
```

Present the script and remind the user:
- Dropped stashes **cannot be recovered**
- Run `--show <N>` to inspect any stash before running the script
- Recent stashes are not included

---

## Safety Rules

**NEVER run `git stash drop` directly** — this skill only generates scripts for user approval.

**Always:**
- Sort drop commands descending by index (highest N first)
- Show the stat summary for every stash suggested for dropping
- Leave Recent stashes out of the script entirely
- Warn clearly on Orphaned stashes (work may not exist anywhere else)

**Never:**
- Drop stashes with no stash list output to verify against
- Assume a stash is safe to drop based on age alone
- Include stash@{0} in the script if it was created recently
