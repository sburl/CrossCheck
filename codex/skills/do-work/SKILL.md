---
name: do-work
description: Process autonomous task queue from do-work/ folder
---

**Created:** 2026-02-11-00-00
**Last Updated:** 2026-04-10-00-00

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
├── 0-001-critical-hotfix.md       ← Top priority (rare)
├── 1-002-add-rate-limiting.md     ← High priority
├── 1-003-refactor-auth-module.md  ← High priority
├── 2-004-write-api-docs.md        ← Medium priority
├── 3-005-nice-to-have-cleanup.md  ← Low priority
├── 4-006-cosmetic-tweaks.md       ← Least priority
```

**Skip files in `do-work/done/` — those are completed or skipped tasks.**

**Numbering convention: `{priority}-{id}-{slug}.md`**

- **Priority** (first digit): 0 = top (rare), 1 = high, 2 = medium, 3 = low, 4 = least
- **ID** (3-digit): Globally unique across all priorities. This lets you reprioritize items by renaming just the priority prefix.
- **001-499**: Reserved for human-created tasks
- **500+**: Agent-created tasks (when the agent discovers follow-up work)
- **NEVER reuse an ID.** Check existing files (including done/) before assigning.
- When creating a task, use the next available ID above 500.
- To reprioritize: rename the priority prefix only (e.g. `2-084-foo.md` → `1-084-foo.md`). The ID stays the same.

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
7. **Mark task done:** Move file to `do-work/done/` (e.g. `mv do-work/1-002-foo.md do-work/done/`)
8. **Return to main:** `git checkout main && git pull`
9. **Move to next task**

### Step 4: Report Results

After processing, output a summary:

```markdown
## /do-work Summary

### Completed
- ✅ 1-002-add-rate-limiting.md → PR #12
- ✅ 1-003-refactor-auth-module.md → PR #13

### Skipped
- ⏭️ 2-004-write-api-docs.md (moved to done/SKIP-2-004-write-api-docs.md)

### Failed
- ❌ 3-005-nice-to-have-cleanup.md (tests failed after 3 attempts)

### Remaining
- 📋 2-006-update-ci-pipeline.md
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
2. **If a task is unclear, SKIP it.** Move to `do-work/done/SKIP-{name}.md` and add a comment at the top explaining what's unclear. Don't guess.
3. **If a task fails 3 times, SKIP it.** Move to `do-work/done/SKIP-{name}.md` with error details at the top.
4. **Respect the `user-content/` directory.** Never modify files in `user-content/` even if a task mentions it.
5. **Follow all CODEX.md conventions.** do-work doesn't bypass any quality gates.
6. **Don't create the do-work/ folder automatically.** If it doesn't exist, tell the user.
7. **Numbering: `{priority}-{id}-slug.md`.** Priority 0-4, ID 001-499 = human, 500+ = agent. Never reuse an ID.

## Setting Up the Task Queue

```bash
# Create the folder in your project
mkdir -p do-work

# Add a task (priority 2 = medium, ID 001)
cat > do-work/2-001-my-first-task.md << 'EOF'
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
