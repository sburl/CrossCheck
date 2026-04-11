**Created:** 2026-02-11-00-00
**Last Updated:** 2026-04-10-00-00

# Task Queue

Drop `.md` files here for the agent to process with `/do-work`.

## Format

Name files as `{priority}-{id}-{slug}.md`:

```text
0-001-critical-hotfix.md          ← Top priority (rare)
1-002-add-rate-limiting.md        ← High priority
2-003-write-api-docs.md           ← Medium priority
3-004-nice-to-have-cleanup.md     ← Low priority
2-500-discovered-tech-debt.md     ← Agent-created (ID 500+)
```

**Priority levels:** 0 = top (rare), 1 = high, 2 = medium, 3 = low, 4 = least

**Numbering rules:**

- **ID is globally unique** across all priorities. Reprioritize by renaming the prefix only.
- **001-499**: Reserved for humans. You set priorities here.
- **500+**: Agents create tasks here when they discover follow-up work.
- **Never reuse an ID**, even after moving to done/.

## Task File Template

```markdown
# Task Title

## Context
What this task is about and why it matters.

## Requirements
- Specific requirement 1
- Specific requirement 2

## Scope
Files/areas to touch.

## Notes
Gotchas or constraints.
```

## Lifecycle

- **Active tasks**: files in `do-work/`
- **Completed**: move to `do-work/done/` (e.g. `mv 1-002-foo.md done/`)
- **Skipped** (unclear/failed): move to `do-work/done/` with `SKIP-` prefix (e.g. `mv 1-002-foo.md done/SKIP-1-002-foo.md`)
- To see what's left: `ls do-work/*.md` (excludes README)
- To see what's done: `ls do-work/done/`
- Git history preserves the full timeline of when tasks were completed

See `/do-work` skill for full details.
