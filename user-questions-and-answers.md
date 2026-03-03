**Created:** 2026-03-03-16-00
**Last Updated:** 2026-03-03-16-00

# User Questions and Assumptions Log

## 0) Executive Understanding (what this repo is now)

- This repository is currently an **AI-native workflow engine**, not a product app.
- Core purpose: enforce quality and review gates for autonomous agents (CrossCheck) via hooks, workflows, skills, and agent prompts.
- The highest-leverage risk right now is **process quality drift**:
  - conventions hidden in many docs
  - large PRs reducing review precision
  - stale patterns spreading across mirrored paths (`codex`, `claude`, root, hooks, scripts)
- User goal is to reduce entropy and rebuild momentum by making the codebase cleaner, safer, and easier to evolve.

## 1) Repo-level Questions and Explicit Working Assumptions

These are the high-value questions I need from you before we move into execution-heavy stages.

### 1. Purpose and audience

- Is this repository for your **personal workflow only**, or should it be maintained as a **general tool template** for others?
- Who is the long-term maintainer: only you, or also delegated collaborators/agents?
- Should compatibility with both Codex + Claude + Gemini be kept equal, or is one primary?
- Should `/do-work` be a strict execution queue or an optional planning aid?

### 2. Risk posture

- Is your current priority:
  1. strictest security,
  2. fastest developer throughput,
  3. broad compatibility,
  4. or lowest maintenance cost?
- What incidents are unacceptable versus acceptable in the next 90 days?
- Which security risks are “never-negotiable” (ex: remote execution, hook escapes, branch-protection changes)?
- Are we allowed to make changes that temporarily reduce speed to improve safety?

### 3. CI / testing strategy

- Should PR runs stay lightweight (fast feedback) with heavier **nightly** only, or can nightly also include medium-scale smoke checks?
- What is your minimum acceptable CI runtime per PR?
- Do you want required checks to fail hard on docs drift, or should some be advisory?
- Are there target platforms/environments we must test from the start (Linux/macOS/Windows)?

4. Change governance and merge discipline

- Are we enforcing **strict stage-based PR batches** (e.g., only one stage per merge window) or can stages overlap?
- How aggressively do you want to split by file count and ownership (5-file PR cap versus topic cap)?
- Is PR authoring always to be done by me, or should agents produce and merge some classes of changes directly?
- Do you want explicit owner labels per stage, or is merge-by-stage sufficient?

### 5. Scope and roadmap boundaries

- Should the roadmap prioritize:
  - repo maintainability first,
  - quality infrastructure first,
  - or feature expansion first?
- Can we retire or remove `claude`/`codex` mirror artifacts if duplicated (or keep for compatibility)?
- Is it acceptable to make breaking changes to docs commands if they improve clarity and reduce confusion?

## 2) Why I think this matters (and my default read)

- Quality drift has a bigger multiplier than any single script bug. Every agent run compounds it.
- Current docs and hooks are strong; main risk is **complexity growth without explicit compaction**.
- `do-work` queue is effectively absent, so execution direction is likely under-specified.
- Existing PR queue has three independent large changes; they should be reviewed in smaller chunks before merge.

## 3) Working assumptions I will proceed with unless corrected

1. You want the repo to remain **agent-first** and **workflow-centric**.
2. We should keep PRs small and stage-based, with strict review gates and documented intent.
3. Security posture should not be reduced for convenience.
4. Docs are part of the product surface and must be lint-clean + timestamped.
5. CI should be split into fast PR checks + nightly deeper checks.
6. Plan + PR tracking must be explicit and machine-readable.

## 4) Quick answer key (if you want defaults now)

- Repository is for personal plus transferable use.
- Priorities: security + maintainability first, then workflow throughput.
- Keep docs-driven architecture; preserve compatibility across Codex/Claude/Gemini entry points.
- CI: keep PR checks fast; run heavy matrix and mutation/security sweeps nightly.
- Keep queue system active with clear staged objectives, not ad-hoc tasks.

## 5) Planned review cadence (your requested style)

- Before coding: complete this assumptions pass and lock categories.
- PR processing: review open PRs first, each in one tight PR scope.
- After each stage: run bug/security/test-infra assessment pass again before advancing.

