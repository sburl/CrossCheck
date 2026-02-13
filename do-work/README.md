**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-11-00-00

# Task Queue

Drop `.md` files here for the agent to process with `/do-work`.

## Format

Name files with numeric prefixes for priority ordering:

```text
001-highest-priority-task.md      ← Human-created (001-099)
002-next-task.md
100-discovered-tech-debt.md       ← Agent-created (100+)
101-add-missing-tests.md
```

**Numbering rules:**

- **001-099**: Reserved for humans. You set priorities here.
- **100+**: Agents create tasks here when they discover follow-up work.
- **Never reuse a number**, even after DONE-/SKIP- renaming.

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

- Active tasks: `001-my-task.md`
- Completed: renamed to `DONE-001-my-task.md`
- Skipped (unclear/failed): renamed to `SKIP-001-my-task.md`

See `/do-work` skill for full details.
