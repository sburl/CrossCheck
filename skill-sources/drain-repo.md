---
name: drain-repo
description: |
  Drain review-approved PRs for a target repo via the integration-branch process.
  Partitions open PRs into DRAINABLE / PENDING / STALE / QUEUE:HUMAN / DUP buckets,
  validates the combined branch with dispatch-only CI, and merges wave-by-wave.
  Pass the target as an argument: acorn | firehose | thriftfit | switchyard.
argument-hint: "<repo: acorn|firehose|thriftfit|switchyard>"
date: 2026-06-11
source: ~/Desktop/integration-drain-prompt.md (GIT-2633 Acorn + FireHose drain sessions)
---

**Created:** 2026-06-11
**Last Updated:** 2026-06-11

# Drain Repo — Integration-Branch Drain / Triage

Drain review-approved PRs for a target repo following the integration-batch v2 process
(docs/integration_drain_runbook.md + GIT-2633). Pass the target repo as an argument:

```bash
/drain-repo acorn
/drain-repo firehose
/drain-repo thriftfit
/drain-repo switchyard
```

If no argument is provided, ask for exactly one of the valid targets before continuing.

---

## Repo → GitHub mapping

| Argument | GitHub repo | Notes |
|----------|-------------|-------|
| `acorn` | `sqburl/Acorn-Compute` | eyeball harness: `tests/browser/eyeball*.spec.js` |
| `firehose` | `sqburl/FireHose` | merge→done webhook is RELIABLE (proven ~107 merges) |
| `thriftfit` | `sqburl/ThriftFit` | — |
| `switchyard` | `sburl/switchyard` | conductor itself — extra care on combined-CI |

---

## Phase 0 — Partition first (report, don't act)

List all open PRs and classify each. **CRITICAL:** readiness is the Linear *workflow
STATE* `review: approved`, NOT the label of that name (the label is a known trap —
check state via the Linear API / `get_issue`, not the label). Bucket into:

- **DRAINABLE:** Linear state `review: approved` + CI green + git-mergeable
- **PENDING:** not yet approved (still in pr-open/in-progress/queue) — leave alone
- **STALE/SUPERSEDED:** forked far behind main, or competing with work main already
  landed (see disposition rules)
- **QUEUE:HUMAN / rejected:** needs operator decision
- **DUP/COMPETING:** multiple PRs doing the same thing

Report the partition + counts + recommendation per cluster **before** proceeding.

---

## Non-negotiable gates

1. Readiness = Linear state `review: approved` only. Don't drain anything else.
2. `git merge` is ground truth (not filename overlap). Use a FULL clone, not shallow
   (shallow has no merge base).
3. Validate the COMBINED branch with dispatch-only CI (Fast Checks) before merge:
   `gh workflow run`. CI auto-triggers are disabled; monitors are off.
4. Merge is YOURS to execute once authorized — `gh pr merge <N> --merge` and
   `gh pr ready` work for the agent (only `--admin` and force-push-to-a-bot-branch
   are denied; TEST before assuming blocked). "Operator go" is a one-time
   authorization, not a per-PR wall. Always a MERGE COMMIT, never squash
   (squash breaks constituent auto-close).
5. Branch DELETION is operator-only. Never pass `--linear-apply`.
6. No bash for/while loops (sandbox blocks them) — use python3 scripts instead.

---

## Disposition rules

- **Fresh + approved + green** → batch into integration waves grouped by conflict graph;
  resolve conflicts individually; validate (lint + targeted tests) + combined CI;
  then operator-gate the merge.
- **Stale parallel work** → before merging, check if it's SUPERSEDED-BY-APPROACH: did
  main's own evolved convention already do this? If a PR is N-hundred commits stale
  and reimplements something main now does differently, do NOT blind-merge a competing
  scheme. Verify, then close with evidence + set Linear `stale` + file ONE fresh
  consolidated issue capturing the real remaining work under main's current direction.
- **Visual/UI PRs** → EYEBALL before disposition: boot the app + playwright screenshot +
  console-error sweep of the affected pages; compare to main.
- **Dup/competing** → resolve individually with written reasoning; never auto-close blindly.
- **SUPERSEDED-BY-APPROACH can appear MID-DRAIN** — a modify/delete conflict is the signal;
  re-verify the delete scope against current main and NARROW it.

---

## Linear bookkeeping

- Merged → status `done`. Superseded/closed-without-merge → status `stale`.

  ```bash
  bin/switchyard linear mutate status --issue GIT-NNN --status <done|stale> --actor operator --apply
  ```

- FireHose's merge→done webhook is reliable (verify a sample, don't double-set).
  Other repos: set `done` manually after merging.

---

## Hard-won gotchas

- **Continuous loop, not one-time:** the conductor refills in waves. "Caught up" =
  open count hits a floor of structural residual (drafts, not-yet-approved), not zero.
- **Conflict tail:** all approved PRs usually merge clean individually vs main, yet
  greedy accumulation surfaces 1–3. Run both checks. To land a conflicter: worktree
  at origin/main, `git fetch origin pull/<N>/head` ALONE (multi-refspec leaves
  FETCH_HEAD at the first ref), checkout it, `git merge origin/main`, resolve,
  non-force push to the PR branch, `gh pr merge`.
  - Additive → union; timestamp-only → newer; lockfile → regenerate (`uv lock`),
    never hand-merge; competing refactor → verify test set identical then take one side wholesale.
- **Draft PR + approved Linear issue:** `gh` won't merge a draft — `gh pr ready <N>` first.
- **Migration-number collisions** are file-disjoint: two PRs adding the same migration
  number won't git-conflict but break the combined tree. Scan for them.
- **Dependabot:** GitHub-Actions version bumps are independent + safe; a
  dependency constraint-widening with pyproject-only change needs no lock regen if
  the locked version still satisfies the wider range.
- **git merge hooksPath gotcha:** neutralize with `-c core.hooksPath=/dev/null` on
  every git call (not `--no-verify`, which is policy-blocked).
- **switchyard is the conductor itself** — its PRs touch the batch/merge machinery;
  be extra careful with combined-CI validation on that repo.

---

## Context (don't re-derive)

- Hand-draining is a RELIEF VALVE, not the fix: the Fly batch-merge cron is report-only
  by design (auto-finalize not enabled — GIT-2612), so approved-green PRs pile up.
- A conductor session may be actively producing PRs — check newest-PR timestamps;
  if one's live, counts will move under you. Say so.

Start with Phase 0 and report the partition.
