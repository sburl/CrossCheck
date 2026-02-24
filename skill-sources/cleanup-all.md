---
name: cleanup-all
description: |
  Run all git cleanup operations in sequence: worktrees, branches, and stashes.
  Use before or after repo assessment, at the end of a sprint, or whenever local git
  state has accumulated clutter. Chains /cleanup-worktrees, /cleanup-branches, and
  /cleanup-stashes with a combined summary at the end.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-23-00-00

# Full Git Cleanup

Chains all three cleanup skills in sequence. Each skill does its own analysis, generates
its own approval script, and reports its own results. This skill orchestrates the sequence
and prints a combined summary at the end.

## Usage

```bash
/cleanup-all              # Full cleanup sequence (interactive)
/cleanup-all --dry-run    # Analysis only across all three — no scripts generated
```

`--dry-run` is passed through to each sub-skill.

---

## Sequence

### Phase 1: Worktrees

```
/cleanup-worktrees
```

Reviews git worktrees. Removes those whose PR is merged and branch is deleted on remote.
Flags stale worktrees (no commits in 7+ days) for review. Requires confirmation.

---

### Phase 2: Branches

```
/cleanup-branches
```

Analyzes local branches. Categorizes as: merged to main (safe), stale (no remote, >14
days), or pattern-based (temp-*, wip-*, test-*). Generates a single bash script for
approval — never runs `git branch -D` directly.

---

### Phase 3: Stashes

```
/cleanup-stashes
```

Reviews all stashes. Flags orphaned (branch gone), superseded (branch merged), and stale
(>14 days). Generates a drop script in descending index order for approval. Recent stashes
are always kept.

---

## Combined Summary

After all three phases complete, print:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /cleanup-all — Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Worktrees    X removed, Y kept
  Branches     Script generated for X branches (Y kept)
  Stashes      Script generated for X stashes (Y kept)

  Local git state is clean.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If nothing needed cleanup in any phase, report that and note the repo is already clean.
