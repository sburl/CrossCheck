**Created:** 2026-03-03-16-00
**Last Updated:** 2026-03-03-12-54

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

- Current branch: `feat/review-pr44-fix`
- Working tree: clean before each major stage
- Open PRs found: 44, 45, 46, 49, 50, 51, 52, 53, 54, 56

## 1) Existing PRs to process now

| PR | Title | Files changed | Current status | Review action | Merge intent |
| --- | --- | --- | --- | --- | --- |
| 51 | Remove dead `setup-github-protection` scripts | 3 script files | **Gemini PASS + ready** | confirmed unreferenced via repo-wide string scan; pass script mirror audit | Merge before PR 44 packaging |
| 52 | Harden Gemini telemetry setup scripts | 3 script files | **Gemini PASS + ready** | syntax-checked and handles invalid JSON by backup + recreate; preserves valid config idempotently | Merge after PR 51 |
| 53 | Add script mirror executable-mode parity checks | 3 script files | **Gemini PASS + ready** | detects executable bit mismatches between root/codex (+ warnings for claude) | Merge before PR 50 and CI split if needed |
| 54 | Fix runtime regression in Gemini telemetry scripts | 3 script files | **Gemini PASS + ready** | fix malformed inline Python and preserve idempotent telemetry settings update behavior | Merge after PR 53 |
| 56 | Harden cron setup script payload lookup | 2 script files | **Gemini PASS + ready** | mirrored-path tolerant payload lookup + admin-safe repo mutation and invite-idempotence | Merge after PR 46 prep |
| PR 49 | feat: split quality gates into PR + nightly workflows | 2 workflow files | **Gemini PASS + ready** | review for PR/CI boundary and execution policy; run and log Gemini opinion before merge | Merge first (infrastructure risk reduction before broader changes) |
| PR 50 | feat: add nightly security gates + script mirror audit | 3 workflow/script files | **Gemini PASS + ready** | run `scan-secrets.sh` nightly and add script mirror drift coverage in nightly quality gates | Merge after CI split PR, before broad Stage 3 work |
| 44 | feat: Add missing agents to repository | 40 files | reviewed; split into micro-PRs | inspect for duplicate/conflicting agent intent and doc consistency; fixed `codex_critic` naming + inventory drift in `codex/agents/README.md`; removed orphaned helper script | Merge once this PR-set completes |
| 57 | Add bot-aware PR reviewer request + mirror sync helper | 11 files | **READY** | bot-aware reviewer mapping supports `-bot`, `_bot`, and `[bot]`; docs include custom bot-name mapping and `--reviewer/--actor` usage; `/submit-pr` now auto-triggers bot-reviewer request; sync helper now auto-discovers NotActive CrossCheck installs while still supporting `.crosscheck` skip semantics and explicit `.claude` / `.cache` targets. Verified sync pass across all known CrossCheck installs. | Merge after PR 56 |
| 45 | feat: integrate Gemini CLI as a first-class agent | 14 files | **Gemini PASS + ready** | fixed dead link to Gemini repo URL in `gemini/README.md` and captured response | Merge once branch includes URL fix and final scope review sync |
| 46 | feat: add cron script to auto-configure new repos | 1 file | **Gemini PASS + ready** | bot invite is now gated on repo admin permission, idempotent collaborator checks, and viewer-permission fallback when `viewerPermission` is unavailable | Merge once reviewed and confirmed |

### Current intended merge order (assumption)

1. CI split PR (this workflow change)
2. PR 49: split quality gates and nightly workflow
3. PR 50: nightly security + script mirror audit
4. PR 45 (after link fix)
5. PR 44 micro-PR A: `codex/agents/README.md` consistency
6. PR 44 micro-PR B: dead-code removal (`fix_all_descriptions2.py`)
7. PR 51: remove unused `setup-github-protection.sh` scripts
8. PR 52: harden Gemini telemetry setup scripts
9. PR 53: add script mirror executable-mode parity checks
10. PR 54: fix telemetry script runtime regression
11. PR 44 micro-PR C: final PR-44 merge packaging
12. PR 56: harden cron script payload lookup and mirror path behavior
13. PR 57: bot-aware reviewer mapping + sync propagation
14. PR 46

### Stage 2 add-on actions

- Added nightly workflow split:
  - `quality-gates.yml` now keeps PR-friendly checks only.
  - `quality-gates-nightly.yml` runs hook/doc metadata/mirror drift checks on a daily schedule and on `workflow_dispatch`.
- Value add:
  - Faster PR feedback.
  - Heavier or longer-running checks preserved for nightly audit coverage.
- Gemini review status:
  - `PASS_WITH_NOTES` on scope and risk.
  - Action item: keep this workflow tracked in PR and release cadence.
  - Explicit trade-off: `Mirror Drift Check` is nightly-only, so sync issues may not block PR merge immediately but are caught on daily run.

- Security gates baseline:
  - Added `security-gates-nightly.yml` to run `scripts/scan-secrets.sh --all` on schedule/dispatch.
  - Purpose: separate secret + history + log scanning from PR feedback path.
- Maintenance hardening:
  - Added `scripts/check-script-mirrors.sh` and wired it into nightly quality gates.
  - Enforces exact root↔codex mirror parity; Claude mirror extras are tracked by allowlist.
- 44A implemented:
  - Fixed `codex/agents/README.md` inventory drift (`engineering`, `product`, `project`, `testing`, `bonus` headings).
  - Confirmed `codex_critic` remains the canonical Codex critic label in Codex docs.
- 44B implemented:
  - Removed `fix_all_descriptions2.py` (migration utility with no runtime references).
- 52 implemented:
  - Hardened Gemini telemetry setup scripts for invalid JSON recovery with backup and clean config recreation.
- 53 implemented:
  - Initial bug/security pass documented in `docs/repo-assessment-pass-1.md`.
- 54 implemented:
  - Risk-pattern pass completed in `docs/repo-assessment-pass-2.md`.
- 55 implemented:
  - Added script-mirror executable-mode parity checks in `scripts/check-script-mirrors.sh` and mirrored copies.
- 56 implemented:
  - Hardened cron setup payload lookup/mirror behavior and admin-safe mutation flow for new-repo protection automation.

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
