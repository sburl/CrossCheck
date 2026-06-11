---
name: triage-repo
description: |
  Autonomous Linear intake triage and queue allocation for one target repo.
  Sweeps issues in triage/needs-clarification/hold/queue:human, dedupes, marks
  stale, chains dependencies, enriches specs, and routes to the correct queue.
  Pass the target as an argument: acorn | firehose | thriftfit | switchyard.
argument-hint: "<repo: acorn|firehose|thriftfit|switchyard>"
date: 2026-06-11
source: ~/Desktop/general_repo_linear_triage_prompt.md
---

**Created:** 2026-06-11
**Last Updated:** 2026-06-11

# Triage Repo — Autonomous Linear Intake Triage & Queue Allocation

Run a full Switchyard-governed Linear intake sweep for one target repo:

```bash
/triage-repo acorn
/triage-repo firehose
/triage-repo thriftfit
/triage-repo switchyard
```

If no argument is provided, ask for exactly one of the valid targets before continuing.

---

## Repo → Linear mapping

| Argument | GitHub repo | Linear project |
|----------|-------------|----------------|
| `acorn` | `sqburl/Acorn-Compute` | Acorn |
| `firehose` | `sqburl/FireHose` | Firehose |
| `thriftfit` | `sqburl/ThriftFit` | ThriftFit |
| `switchyard` | `sburl/switchyard` | switchYard |

Prefer Linear project ID/project membership over issue prefix. Some projects share
`GIT-*` issue IDs, so never classify by prefix alone.

---

## Source of truth

Use the Switchyard docs/config as the authoritative reference:

- `AGENTS.md`
- `docs/workflow_states_v2.md`
- `docs/linear_triage_workflow.md`
- `docs/periodic_triage_runbook.md`
- `docs/findings_and_dedupe.md`
- `docs/linear_mutations.md`
- `docs/agent_linear_workflow.md`
- `docs/linear_agent_roles.md`
- `docs/repos_registry.md`
- `docs/multi_project_calibration.md`
- `config/repos.yaml`
- `config/projects.yaml`
- repo-specific prompt files under `config/prompts/`, if present

---

## Target statuses

Sweep all issues for the target repo in:
- `triage`
- `needs-clarification`
- `hold`
- `queue: human`

Also read neighboring active states only as needed for dedupe/dependency context:
`queue: standard`, `queue: deep`, `needs-human-decision`, `blocked`, `pr-open:*`,
`review:*`, recently `done` / `stale`.

Do not implement code. Do not open PRs. Do not create repo-local task queues.
Linear remains the source of work intent, status, dedupe, dependencies, priority,
and audit trail.

---

## Waterfall phases

### 1. Inventory

Snapshot all target issues by project/status. Capture: ID, title, project, status,
priority, estimate, labels, parent/relations, linked PRs, last update, and whether
the body has enough metadata/spec to route. Record connector/API failures precisely
and continue with returned data.

### 2. Dedupe

Cluster across intake, hold, queues, blocked, PR/review states, and recently closed
issues. Dedupe by: same failure, same acceptance criteria, same source PR/issue, same
file/symbol, same generated finding text, or same underlying mechanism.

- Keep the canonical issue that is richest, most current, correctly queued, or
  already has dependency/PR context.
- Do not dedupe merely because issues touch the same area.
- For duplicates: set duplicate relation/state when permitted and add a short evidence
  comment.

### 3. Stale Detection

Close as `stale` only with high-confidence evidence: merged PR, current repo search,
command result, or linked canonical issue already landed. If uncertain, keep active
and route normally. Add an evidence comment for every stale closure.

### 4. Dependency Chaining

Add native Linear blocker/related relations where merge/order matters.
- Blockers only for true ordering constraints.
- Related links for historical/source context that does not block work.
- Comment briefly when adding a blocker.

### 5. Enrichment

For issues that can be made executable from body/comments/code context, append a
concise spec without changing intended scope:

- Problem
- Approach
- Likely files/paths
- Acceptance criteria
- Validation
- Dependencies
- Non-goals
- Risk and size

Do not invent product, architecture, security, billing, data, or ops decisions.

### 6. Routing / Queue Allocation

Route each non-duplicate, non-stale issue to the narrowest correct state:

| State | Criteria |
|-------|----------|
| `queue: standard` | r0/r1, execution-ready, bounded/mechanical, no blockers, no human decision |
| `queue: deep` | concrete r2 work, shared behavior, meaningful implementation latitude, cross-module/CI/API/gateway/conductor/queue behavior |
| `queue: human` | clear work but human execution required: r3/r4 risk, production credentials, deploy authority, manual UI/admin, security sensitivity, billing/data risk |
| `needs-human-decision` | next step is choosing a product/architecture/security/dependency/data/billing/ops direction |
| `needs-clarification` | missing facts cannot be inferred from Linear/docs/code |
| `hold` | leave held unless it clearly belongs elsewhere and a human approves moving it |

**Key distinction:** `needs-human-decision` = a decision is missing.
`queue: human` = work is clear, but a human should execute/control it.

#### Per-repo risk calibration (from `docs/multi_project_calibration.md`)

- **Acorn:** API contract, worker protocol, ledger/billing, deploy behavior,
  migrations, signing/notarization, and production data boundaries are high-risk.
- **FireHose:** LLM pipeline, token spend, Neon migrations, delivery scheduling,
  search ranking, new ingest sources, and production ingestion history are high-risk.
- **ThriftFit:** LLM scoring prompts/models, eBay OAuth/rate limits, recommendation
  thresholds, database migrations, and production listing history are high-risk.

### 7. Human Rapid-Fire Pass

After all deterministic work is done, batch only the remaining true human decisions.
For each, give:

- Issue ID + title
- 1 sentence of context
- The exact decision needed
- 2–3 options with your recommendation first (marked "Recommended")
- Consequence of each option

Format:
```
Decision 1: <ISSUE-ID> - <title>
Context: <one sentence>
Question: <exact decision>
Options:
A. <recommended option> (Recommended) - <impact>
B. <option> - <impact>
C. <option> - <impact>
```

Wait for the human's selections before applying human-dependent moves.

### 8. Final Consistency Check

Verify:
- No r2+ issue remains in `queue: standard`.
- No decision-missing issue is in `queue: human`.
- No duplicate lacks a canonical relation/comment.
- Queued issues have usable risk, size, validation, readiness/spec metadata.
- Issues with prerequisites have blocker relations.
- Human-decision issues have comments naming the exact decision needed.
- Stale issues have evidence comments.

---

## Mutation rules

- Prefer Switchyard policy-gated mutation commands or approved Linear connector paths.
- Use dry-run first where available.
- Do not mutate GitHub settings, Linear workspace settings, rulesets, secrets, billing,
  protected branches, or repo policy.
- Do not push to `main`.
- Do not use git stashes.
- Add short audit comments for non-obvious transitions.

---

## Final report format

```
| Issue | From | To | Reason |
| --- | --- | --- | --- |
```

Also include:
- Duplicates collapsed
- Stale issues closed
- Blockers/relations added
- Queue allocations: standard vs deep vs human
- Remaining human decisions
- Commands/tools run
- Mutations applied vs dry-run only
- Blockers or missing permissions
