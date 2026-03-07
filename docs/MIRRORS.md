**Created:** 2026-03-07-00-00
**Last Updated:** 2026-03-07-00-00

# Mirror Contract

CrossCheck maintains parallel directory surfaces for Claude, Codex, and Gemini.
This document defines the source-of-truth for each artifact type and the enforcement rules.

## Source of Truth

| Artifact | Canonical Location | Mirrors | Enforcement |
|----------|-------------------|---------|-------------|
| Skills (`.md`) | `skill-sources/` | `claude/skill-sources/`, `codex/skill-sources/`, `gemini/skill-sources/`, `codex/skills/*/SKILL.md` | CI: filename parity + normalized content drift check (skill-sources only; `codex/skills/` checked by filename parity, not content drift) |
| Scripts (`.sh`) | `scripts/` | `claude/scripts/`, `codex/scripts/` | CI: `check-script-mirrors.sh` (presence + exec bit) |
| Workflow docs | `CLAUDE.md`, `CODEX.md` | `claude/CLAUDE.md`, `codex/CODEX.md`, `gemini/GEMINI.md` | **Intentional delta** — each surface customizes escalation, agent refs |
| AGENTS.md | Per-surface | `claude/AGENTS.md`, `codex/AGENTS.md` | **Intentional delta** — skill list format differs (flat vs folder) |
| Git hooks | `git-hooks/` | `claude/git-hooks/`, `codex/git-hooks/` | CI: `check-script-mirrors.sh` |
| Agents | `agents/` | `claude/agents/`, `codex/agents/` | Manual — agent descriptions are surface-specific |
| do-work | `do-work/` | `claude/do-work/`, `codex/do-work/` | Manual — task queues are independent |

## Rules

1. **Skills have intentional agent-name deltas.** The canonical copy is `skill-sources/*.md` (Claude-flavored). Mirrors may substitute agent names (`CLAUDE`→`CODEX`, `claude`→`codex`). CI normalizes agent names before comparing content hashes to detect real drift vs intentional substitution.

2. **Scripts are presence-checked.** Every script in `scripts/` must exist in `codex/scripts/` and `claude/scripts/`. Content may differ for agent-specific scripts (listed in `CLAUDE_ONLY` array in `check-script-mirrors.sh`).

3. **Workflow docs are intentional deltas.** `CLAUDE.md`, `CODEX.md`, `GEMINI.md` share structure but differ in agent references (`/claude-delegate` vs `/codex-delegate`), escalation targets, and surface-specific sections. These are NOT expected to be identical.

4. **Gemini is a partial surface.** `gemini/skill-sources/` contains only skills added after Gemini integration. It does not mirror the full skill catalog. CI checks content parity for files that exist.

## Adding a New Skill

1. Create `skill-sources/new-skill.md` (canonical)
2. Copy to `claude/skill-sources/new-skill.md`
3. Copy to `codex/skill-sources/new-skill.md`
4. Create `codex/skills/new-skill/SKILL.md` (same content)
5. Optionally copy to `gemini/skill-sources/new-skill.md`
6. Update skill counts in: `CODEX.md`, `claude/CLAUDE.md`, `codex/CODEX.md`, `gemini/GEMINI.md`, `claude/AGENTS.md`, `codex/AGENTS.md`
7. CI will catch filename mismatches and content drift

## Adding a New Script

1. Create `scripts/new-script.sh` (canonical)
2. Copy to `codex/scripts/new-script.sh`
3. Copy to `claude/scripts/new-script.sh`
4. Ensure executable bit matches
5. CI will catch missing mirrors via `check-script-mirrors.sh`
