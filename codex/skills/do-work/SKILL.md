---
name: do-work
description: Process autonomous task queue from do-work/ folder
---

**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-11-00-00

# Do Work - Autonomous Task Queue Processing

Process tasks from the `do-work/` folder, executing them in priority order with full branch workflow. Auto-triggers after PR merges, on session start with no task, and during autonomous sessions.

## Usage

```bash
/do-work                    # Process next available task
/do-work --all              # Process all tasks in order
/do-work --dry-run          # Preview what would be processed
```

## How It Works

### Step 1: Scan the Task Queue

Read all `.md` files from the `do-work/` folder, sorted by filename (use numeric prefixes for priority):

```text
do-work/
├── 001-add-rate-limiting.md       ← Highest priority
├── 002-refactor-auth-module.md
├── 003-write-api-docs.md
├── 010-nice-to-have-cleanup.md    ← Lower priority
```

**Skip files that start with `DONE-` or `SKIP-` prefix.**

**Numbering convention:**

- **001-099**: Reserved for human-created tasks (user sets priorities)
- **100+**: Agent-created tasks (when the agent discovers follow-up work)
- **NEVER reuse a number.** Check existing files (including DONE-/SKIP-) before assigning.
- When creating a task, use the next available number above 100.

### Step 2: Read the Task File

Each task file should contain:

```markdown
# Task Title

## Context
What this task is about and why it matters.

## Requirements
- Specific requirement 1
- Specific requirement 2
- Acceptance criteria

## Scope
Files/areas that should be touched.

## Notes
Any gotchas, constraints, or preferences.
```

**Minimum:** A task file needs at least a title and one clear requirement. More context = better results.

### Step 3: Execute the Task

For each task:

1. **Create feature branch:** `git checkout -b feat/{task-slug}`
2. **Enter plan mode if complex** (>3 files or unclear approach)
3. **Implement the task** following all CODEX.md conventions
4. **Write tests alongside code** (zero trust)
5. **Run tests** - must pass before proceeding
6. **Submit PR:** INVOKE `/submit-pr`
7. **Mark task done:** Rename file to `DONE-{original-name}.md`
8. **Return to main:** `git checkout main && git pull`
9. **Move to next task**

### Step 4: Report Results

After processing, output a summary:

```markdown
## /do-work Summary

### Completed
- ✅ 001-add-rate-limiting.md → PR #12
- ✅ 002-refactor-auth-module.md → PR #13

### Skipped
- ⏭️ 003-write-api-docs.md (SKIP- prefix)

### Failed
- ❌ 010-nice-to-have-cleanup.md (tests failed after 3 attempts)

### Remaining
- 📋 015-update-ci-pipeline.md
```

## Task File Examples

### Simple Task

```markdown
# Add health check endpoint

## Requirements
- GET /health returns 200 with { "status": "ok", "timestamp": "..." }
- Include version from package.json
- Add test
```

### Complex Task

```markdown
# Refactor authentication to use JWT

## Context
Currently using session cookies. Need stateless auth for mobile app support.

## Requirements
- Replace session-based auth with JWT tokens
- Access token: 15min expiry
- Refresh token: 7 day expiry, stored in httpOnly cookie
- All existing tests must still pass
- Add new tests for token refresh flow

## Scope
- src/auth/ (main changes)
- src/middleware/auth.ts (update)
- tests/auth/ (update + new)

## Notes
- Don't change the user model
- Keep backward compat with existing API consumers for 1 release
- See docs/auth-rfc.md for the design doc
```

## Rules

1. **One task = one branch = one PR.** Never batch multiple tasks into one PR.
2. **If a task is unclear, SKIP it.** Rename to `SKIP-{name}.md` and add a comment at the top explaining what's unclear. Don't guess.
3. **If a task fails 3 times, SKIP it.** Rename to `SKIP-{name}.md` with error details at the top.
4. **Respect the `user-content/` directory.** Never modify files in `user-content/` even if a task mentions it.
5. **Follow all CODEX.md conventions.** do-work doesn't bypass any quality gates.
6. **Don't create the do-work/ folder automatically.** If it doesn't exist, tell the user.
7. **Numbering: 001-099 = human, 100+ = agent.** Never reuse a number. Check existing files first.

## Setting Up the Task Queue

```bash
# Create the folder in your project
mkdir -p do-work

# Add a task
cat > do-work/001-my-first-task.md << 'EOF'
# My First Task

## Requirements
- Do the thing
- Test the thing
EOF
```

## Integration with Autonomous Sessions

For long autonomous sessions, combine with the 15-minute status update rule from CODEX.md:

```text
Every 15min: Update TODO.md with:
- Which task is currently being processed
- Current status (planning/coding/testing/PR)
- Any blockers
```

## Related Commands

- `/plan` - Used automatically for complex tasks
- `/submit-pr` - Used to submit each completed task
- `/commit-smart` - Used for commits within each task
- `/techdebt` - Run as part of `/submit-pr`
