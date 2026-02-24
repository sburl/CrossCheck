# AGENTS.md for `codex/`

Use this section as a Codex-native workspace.

## Core Files
- Primary workflow: `codex/CODEX.md`
- Prompt patterns: `codex/CODEX-PROMPTS.md`
- Skill catalog: `codex/skills/`

## Skills (Codex Format)
Each skill is a folder with `SKILL.md`.

- `codex/skills/ai-usage/SKILL.md`
- `codex/skills/bug-review/SKILL.md`
- `codex/skills/cleanup-branches/SKILL.md`
- `codex/skills/cleanup-worktrees/SKILL.md`
- `codex/skills/codex-delegate/SKILL.md`
- `codex/skills/commit-smart/SKILL.md`
- `codex/skills/create-worktree/SKILL.md`
- `codex/skills/do-work/SKILL.md`
- `codex/skills/doc-timestamp/SKILL.md`
- `codex/skills/ensemble-opinion/SKILL.md`
- `codex/skills/garbage-collect/SKILL.md`
- `codex/skills/gemini-delegate/SKILL.md`
- `codex/skills/list-worktrees/SKILL.md`
- `codex/skills/plan/SKILL.md`
- `codex/skills/pr-review/SKILL.md`
- `codex/skills/pre-pr-check/SKILL.md`
- `codex/skills/repo-assessment/SKILL.md`
- `codex/skills/security-review/SKILL.md`
- `codex/skills/setup-automation/SKILL.md`
- `codex/skills/setup-statusline/SKILL.md`
- `codex/skills/submit-pr/SKILL.md`
- `codex/skills/techdebt/SKILL.md`

## Skill Usage Rules
- If a task clearly matches a skill, use that skill.
- If the user names a skill, use that skill directly.
- Open only the specific `SKILL.md` files needed for the task.
- Keep skill instructions in sync with scripts/hooks referenced by the skill.

## Legacy Notes
- `codex/skill-sources/` is retained as legacy source material.
- `codex/skills/` is the canonical Codex format for this section.
