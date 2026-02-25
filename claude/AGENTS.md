# AGENTS.md for `claude/`

**Created:** 2026-02-24-15-00
**Last Updated:** 2026-02-24-15-00

Use this section as a Claude-native workspace.

## Core Files
- Primary workflow: `claude/CLAUDE.md`
- Prompt patterns: `claude/CLAUDE-PROMPTS.md`
- Skill catalog: `claude/skill-sources/`

## Skills (Flat Format) — 27 total
Each skill is a `.md` file in `claude/skill-sources/`.

- `claude/skill-sources/ai-usage.md`
- `claude/skill-sources/bug-review.md`
- `claude/skill-sources/capture-skill.md`
- `claude/skill-sources/cleanup-all.md`
- `claude/skill-sources/cleanup-branches.md`
- `claude/skill-sources/cleanup-stashes.md`
- `claude/skill-sources/cleanup-worktrees.md`
- `claude/skill-sources/codex-delegate.md`
- `claude/skill-sources/commit-smart.md`
- `claude/skill-sources/create-worktree.md`
- `claude/skill-sources/do-work.md`
- `claude/skill-sources/doc-timestamp.md`
- `claude/skill-sources/ensemble-opinion.md`
- `claude/skill-sources/garbage-collect.md`
- `claude/skill-sources/gemini-delegate.md`
- `claude/skill-sources/list-worktrees.md`
- `claude/skill-sources/napkin.md`
- `claude/skill-sources/plan.md`
- `claude/skill-sources/pr-review.md`
- `claude/skill-sources/pre-pr-check.md`
- `claude/skill-sources/repo-assessment.md`
- `claude/skill-sources/security-review.md`
- `claude/skill-sources/setup-automation.md`
- `claude/skill-sources/setup-statusline.md`
- `claude/skill-sources/submit-pr.md`
- `claude/skill-sources/techdebt.md`
- `claude/skill-sources/update-crosscheck.md`

## Skill Usage Rules
- If a task clearly matches a skill, use that skill.
- If the user names a skill, use that skill directly.
- Open only the specific skill files needed for the task.
- Keep skill instructions in sync with scripts/hooks referenced by the skill.

## Legacy Notes
- `claude/skill-sources/` contains flat `.md` skill files.
- Skills are symlinked from `~/.claude/commands/` in multi-project mode.
