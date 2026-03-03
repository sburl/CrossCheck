**Created:** 2026-03-03-16-00
**Last Updated:** 2026-03-03-17-00

# User Questions and Assumptions Log

## 0) Executive understanding

- This repo is an **AI-native workflow engine** used by multiple contributors (open-source), not a single-person scratchpad.
- Non-negotiable constraints: keep PR gates, avoid behavior-breaking automation, and preserve compatibility across CLAUDE/CODEX/GEMINI surfaces.
- Highest-value risk remains **process drift** (large PRs + mirrored docs + hidden conventions).

## 1) Clarified answers to the initial discovery questions

## 1A) Purpose and audience

- The repo is public and used by others. Stability is required for all merged changes.
- Primary maintainer should remain this repo’s maintainer flow, but changes should be stable for downstream users.
- Claude is primary today, while Codex and Gemini should remain first-class and equally supported for compatibility.
- `/do-work` should stay a **strict execution cue** and stage-driven queue.

## 1B) Risk posture

- Throughput is important, but PR sanctity is explicitly non-negotiable.
- PR review and separate-account gate remain mandatory; no shortcuts for branch protection.
- There should be a clear install-time choice around elevated permissions:
  - default secure posture,
  - explicit opt-in to high-permission modes with clear warnings.
- A second GitHub account for review/submission should be strongly encouraged.
- Fast throughput can be pursued, but not at the cost of branch integrity.

## 1C) CI / testing strategy

- CI credits are constrained; nightly checks should absorb heavier work.
- PR CI should be lightweight and fast to support many PRs.
- Required checks on PRs should stay strict enough to prevent regression, but non-essential gates should be moved to nightly.
- Initial priority is Linux/macOS; Windows can be added when workflow impact is justified.

## 1D) Governance / process

- Stage gates should be explicit and conservative.
- PR authoring can be by agents from any supported model.
- Repo assessment should happen between stages.

## 1E) Scope and roadmap

- Quality infrastructure first, then maintainability, then feature expansion.
- Keep all three agent surfaces (`codex`, `claude`, `gemini`) and reduce drift where possible, rather than deleting compatible surfaces.
- Breaking doc/command changes can be done only with migration guidance and compatibility notes.

## 2) Final assumptions to run with

1. Keep agent-first, cross-model workflow.
2. Maintain strict, atomic PRs with explicit intent and review trail.
3. Preserve PR safety and branch protection as hard limits.
4. Use staged execution; re-assess after each stage.
5. CI is split: fast PR checks + nightly deeper checks.
6. Keep docs and do-work queue machine-actionable.

## 3) Explicit implementation implications from this pass

- Do not ship permissive execution shortcuts as defaults.
- Add clear install-time consent language around dangerous permission choices.
- Add clear guidance that PR review is user gatekeeping, not optional.
- Keep `do-work` as a strict queue with stage-based execution cadence.
- Apply Stage 1 with tiny PRs only and loop with review after each unit.
