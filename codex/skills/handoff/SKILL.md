---
name: handoff
description: Generate a structured session handoff document from current state. Captures branch, commits, open PRs, failing tests, and next steps for seamless session-to-session or agent-to-agent continuity.
---

**Created:** 2026-03-07-00-00
**Last Updated:** 2026-03-07-00-00

# Session Handoff

Generate a structured handoff document so another session or agent can pick up exactly where you left off.

## Step 1: Gather Current State

Run these commands and capture output:

```bash
# Branch and recent work
BRANCH=$(git branch --show-current)
echo "Branch: $BRANCH"
git log --oneline -10

# Uncommitted changes
git status --short

# Open PRs from this branch
gh pr list --head "$BRANCH" --json number,title,state,url 2>/dev/null || echo "No PRs"

# Check for failing tests (quick — skip if no test runner detected)
# Auto-detect: package.json (npm test), pytest, cargo test, go test
if [ -f "package.json" ]; then
    npm test --silent 2>&1 | tail -5
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -d "tests" ]; then
    python -m pytest --tb=line -q 2>&1 | tail -10
fi
```

## Step 2: Build Handoff Document

Create `do-work/handoff.md` with this structure:

```markdown
# Session Handoff

**Generated:** {timestamp}
**Branch:** {branch}
**Repo:** {repo name}

## What Was Done
- {summary of completed work from recent commits}

## Current State
- **Uncommitted changes:** {yes/no + summary}
- **Open PRs:** {PR numbers and titles}
- **Test status:** {passing/failing + failure summary}

## What's Left
- {remaining items from any plan, TODO.md, or do-work/ tasks}

## Key Files Modified
- {list of files changed in this session's commits}

## Blockers / Notes
- {anything the next session needs to know}
- {decisions made and why}
- {things that were tried but didn't work}
```

## Step 3: Targeted Handoff (Optional)

If the user specifies a target agent, tailor the handoff:

- **For Codex:** Focus on what to review, test commands, PR number
- **For Gemini:** Focus on architectural context, codebase overview
- **For another Claude session:** Focus on conversation state, decisions made, what was tried

## Step 4: Confirm

Tell the user:
```
Handoff written to do-work/handoff.md. Next session can pick up with /do-work or by reading the handoff directly.
```

## When to Use

- End of a session before closing
- Switching to a different agent mid-task
- Handing work to a parallel worktree session
- Before a long break from a project
