**Created:** 2026-03-03-16-00
**Last Updated:** 2026-03-03-16-00

# CrossCheck Rework Plan + PR Tracker

## 0) How we operate from here

### Global rules

- Use very small, topic-focused PRs.
- Review every PR with at least:
  - functional read-through
  - risk review
  - explicit merge readiness decision
- After edits, run Gemini review (where practical) before merge.
- Record every stage and PR in this file in merge order.

### Repo-first status

- Current branch: `main`
- Working tree: clean before each major stage
- Open PRs found: 44, 45, 46

## 1) Existing PRs to process now

| PR | Title | Files changed | Current status | Review action | Merge intent |
| --- | --- | --- | --- | --- | --- |
| 44 | feat: Add missing agents to repository | 40 files | reviewed | inspect for duplicate/conflicting agent intent and doc consistency; fixed `codex_critic` heading mismatch in `codex/agents/README.md` | Merge once this naming fix is mirrored upstream |
| 45 | feat: integrate Gemini CLI as a first-class agent | 14 files | reviewed, CI failing `Markdown Link Check` | fixed dead link to Gemini repo URL in `gemini/README.md` and captured response | Hold until upstream branch includes URL fix and Gemini review can complete |
| 46 | feat: add cron script to auto-configure new repos | 1 file | reviewed | verify script safety and permissions policy alignment | Merge once reviewed and confirmed |

### Current intended merge order (assumption)

1. PR 45 (after link fix)
2. PR 44 (with naming fix)
3. PR 46

Rationale: isolate risk by landing smaller, bounded changes first, then larger content/agent changes.

## 2) Stage plan (10+ features per category, grouped into 5–15 task stages)

### Category: Improvements (12)

1. Tighten PR-size enforcement by adding explicit check for >5 new files with guidance.
2. Add PR title convention lint for category/action consistency.
3. Centralize do-work lifecycle status in one canonical doc.
4. Add repo bootstrap smoke test command (`scripts/verify-bootstrap.sh`).
5. Create “queue heartbeat” checks for stale entries.
6. Normalize hook installation output and telemetry messages across `claude` and `codex` mirrors.
7. Reduce shellcheck false positives via stricter script shims and shell style guide.
8. Add `do-work` stage templates with explicit acceptance criteria.
9. Add dependency update policy and update cadence log.
10. Introduce minimal staged feature flag for major workflow changes.
11. Improve agent selection visibility in logs (`agent`, `prompt`, `task`, `duration`).
12. Add changelog entry rule for non-doc workflow behavior changes.

### Category: Big Vision (12)

1. Add repo health scorecard (quality, risk, review debt).
2. Add cross-agent consensus step for high-risk PRs.
3. Build automated “runbook generator” from markdown headers and skill docs.
4. Add workflow policy dashboard (rules + CI + review loops).
5. Add PR readiness assistant that summarizes check health before `/pr-review`.
6. Add repo “intent manifest” for long-term direction with versioned goals.
7. Introduce semantic tags for PRs (`agent`, `risk`, `category`) in docs.
8. Add safe rollback playbooks for broken automation scripts.
9. Build optional local-only mode for private repos with no network.
10. Introduce evidence logs for security findings and mitigations.
11. Add migration helper that updates mirrored docs (`codex`/`claude`) safely with previews.
12. Add “quality debt aging” report (when/where issues recur).

### Category: Maintenance (12)

1. Remove dead code in scripts not covered by any workflow path.
2. Consolidate duplicated AGENTS guidance references.
3. De-duplicate agent descriptions duplicated with minor drift.
4. Audit and prune deprecated scripts.
5. Replace brittle regex checks with tested helper functions.
6. Normalize error handling across setup scripts.
7. Add missing newline/format consistency checks on generated artifacts.
8. Update `.gitignore` with temporary workspace rules for scratch outputs.
9. Reduce mirrored doc drift (`root`, `claude`, `codex`) by validation script.
10. Remove historical command aliases that no longer exist.
11. Add dead-link detection snapshot for all generated docs.
12. Add tests for `doc-metadata` timestamps on CI docs changes.

## 3) Staged execution plan

Each stage should complete before the next stage is started.

### Stage 1 — Stabilize merge surface (5 tasks)

- PR 45: fix Markdown dead link and rerun link checks.
- PR 46: verify and/or patch script permissions and edge cases.
- PR 44: split into two or more micro-PRs if needed after review.
- Run CI review pass after each split PR.
- Record Gemini/Codex acceptance for each.

### Stage 2 — Infrastructure cleanup and governance (7 tasks)

- Implement repo health basics for do-work backlog, PR tracking, and review logs.
- Add nightly/per-PR workflow split baseline.
- Add mirror drift hardening docs and checks.
- Add queue lifecycle scripts for DONE/SKIP naming discipline.
- Add baseline bug/security review notes and owner matrix.

### Stage 3 — Red-team readiness + bug surfacing (10 tasks)

- Introduce redteam checklist pass for shell and automation attack paths.
- Add security abuse case tests for key scripts and hook workflows.
- Build integration test that exercises setup scripts in temp repos.
- Add dependency threat updates and review gates.
- Add stronger secrets-path handling for telemetry and local config.
- Add output redaction policy.
- Add regression tests for setup idempotency.
- Add mutation-like test approach for high-risk helper scripts.
- Add chaos check list for hook failures.
- Add PR template for manual verification notes.

### Stage 4 — Simplification and readability (11 tasks)

- Prune duplicated agent files and canonicalize schema.
- Replace brittle shell patterns with shared helper functions.
- Remove unused docs sections and keep only active workflow docs.
- Rework long scripts into smaller composable units.
- Reduce command duplication across codex/claude scaffolding.
- Introduce explicit command ownership tags in docs.
- Add consistent naming conventions and structure linting.
- Improve comments and rationale blocks across scripts.
- Add local smoke-tests for quick verification.
- Clean up script permissions and executable consistency.
- Consolidate optional dependency setup docs.
- Document anti-patterns that caused past failures.

### Stage 5 — Hardening and future work (7 tasks)

- Add nightly extended checks matrix.
- Add automated review evidence export (for trend tracking).
- Add optional policy mode for strict mode vs experimental mode.
- Add long-term roadmap review every 3 PRs.
- Add user guidance for conflict/merge failure recovery.
- Add minimal e2e smoke scenario for setup + branch flow.
- Prepare stage 2 roadmap based on first cycle findings.

## 4) What gets recorded after each stage

- Stage PR list and intended merge order.
- Summary of what was removed, simplified, or refactored.
- Test/bug/security pass findings.
- Open risks and follow-up actions for next stage.
- Whether this stage is approved to proceed by your explicit confirmation.
