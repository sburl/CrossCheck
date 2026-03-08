# CrossCheck Repository Assessment (Pass 1)

**Created:** 2026-03-03-16-56
**Last Updated:** 2026-03-03-16-56
**Purpose:** Initial focused pass after PR merge-cleanup; bias toward concrete, high-confidence issues.

## 1) Scope of this pass

- Existing PR review sweep for PRs 44/45/46
- Mirror drift and workflow topology
- Script-level dead code and stale-file detection
- Security surface at repo + workflow + script level
- Bug-risk triage with actionable test ideas

## 2) Findings (validated)

### A. Dead script cleanup
- `scripts/setup-github-protection.sh`, `claude/scripts/setup-github-protection.sh`, `codex/scripts/setup-github-protection.sh`
  - Not referenced by workflows, hooks, or documented command paths.
  - Removed as a dead/unused script set.
  - `scripts/check-script-mirrors.sh` remains green after removal.

### B. PR 46 cron script risk and mitigations
- Cron script now has explicit dependency checks (`gh`, `jq`) and auth checks.
- Uses root-scoped ruleset JSON as source of truth and skips when missing, which is safer than creating malformed defaults.
- Remaining edge: first-time setup for a new repo still logs only warning on failed collaborator invite; acceptable if intentional (non-fatal policy).

### C. PR 45 telemetry setup robustness
- Added malformed JSON recovery path for `~/.gemini/settings.json`:
  - backs up invalid file to `.invalid-json`
  - recreates known-good telemetry block with local file target.
- This prevents silent script failure in malformed-user-state environments.

## 3) Bug + test ideas to carry into next pass

1. **Mirror completeness coverage**
   - Add a dedicated test that enforces:
     - executable bits parity for mirrored scripts
     - file count parity for agent/skill directories beyond script roots.
2. **Cron invitation idempotency**
   - Verify repeated `gh-repo-setup-cron.sh` runs do not create noisy failures on API permission issues.
3. **Ruleset payload integrity**
   - Add JSON schema checks around `scan` payload and API responses before rule updates.
4. **Security of local config recovery**
   - Confirm backup copy `.invalid-json` is never world-readable in CI/terminal environments.
5. **Workflow drift**
   - Add a test for `.github/workflows/*.yml` hash parity against a minimal expected checklist.

## 4) Security assessment summary

### High-impact risks
- **GH token misuse in scripts**: every GitHub API mutating script should use explicit intent and minimum required permissions.
- **Mirror drift**: stale mirrored scripts are a governance risk (behavior divergence).
- **Rule-set automation**: unvalidated payloads can over-privilege repositories if config files become malformed.

### Controls already present
- Nightly `security-gates-nightly.yml` with `scan-leaks.sh --all`.
- `quality-gates` split avoids long-running heavy checks on PR path.
- Script mirror audit in nightly CI.
- Mirror script now allows explicit Claude-only exceptions.

### Control gaps to address in next passes
- Validate executable ownership/mode and shebang consistency in CI.
- Expand security scan target list to include generated/archived docs and `.history` artifacts.
- Add a small red-team-style checklist runbook per critical script.

## 5) Simplification and readability pass status

- Completed
  - Removed dead scripts.
  - Added explicit input validation for malformed telemetry config.
- Next candidates
  - Normalize repeated command blocks in mirror scripts and setup scripts via helper functions.
  - Decompose large scripts with repeated shell parsing logic into shared helper utility.

## 6) Merge-status follow-up

- Micro PRs completed in this pass:
  1. Dead script removal (PR 51).
  2. Gemini telemetry hardening (PR 52).
- Next action:
  - Re-run PR-level review cycle after PR 51/52 documentation updates.
