---
name: claude-delegate
description: "Delegate a coding task to OpenAI Claude agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-11-22-22-15

You are delegating a coding task to a headless Claude agent. Claude will do the actual implementation work.

## Delegation Pattern (shared with /gemini-delegate)

### 1. Identify Task

Review conversation context. Restate the task clearly: what to do, which files, what "done" looks like. If unclear, ask the user.

### 2. Gather Context & Formulate Prompt

Read CLAUDE.md and relevant code. Build ONE prompt with this structure:

```
# Project Context
[Relevant sections from CLAUDE.md]

# Task
[Clear description from conversation context]

# Relevant Files
[Key files the model should know about]

# Requirements
- [specific requirements]

# Success Criteria
- [how to verify it's done correctly]
```

Rules: Include CLAUDE.md context directly. Be specific about requirements. Do NOT tell the model how to implement or over-constrain the solution.

## Claude-Specific Execution

### 3. Execute Claude

```bash
claude exec --full-auto "YOUR_PROMPT_HERE" 2>&1
```

`--full-auto` enables `--sandbox workspace-write` and `-a on-request` (model decides when to ask for approval). Claude auto-applies changes to the workspace.

### 4. Report Results

```
## Delegation Report

### Task: [what was delegated]
### Context Provided: [summary of CLAUDE.md context included]
### What Claude Did: [files created/modified, summary of changes]
### Verification: [did it meet success criteria? issues?]
### Follow-up: [remaining tasks, things to review]
```

## Important

- YOU identify the task from conversation context
- Inject CLAUDE.md content DIRECTLY into the prompt (don't create AGENTS.md)
- If Claude fails, report what happened and suggest fixes
- You can run Claude multiple times with refined prompts

## Orchestrator Diff Verification

An agent's green checks are necessary, not sufficient. Before reporting a delegated change as done, inspect the diff yourself; do not substitute another test run for this review.

- Confirm every changed file is within the task's intended scope. Investigate unexpected files.
- Inspect removed or weakened assertions. Decide from the surrounding behavior whether each change strengthens coverage or drops it.
- Audit suppression markers and their justifications against the exact code they cite; check whether each justification matches what the code proves (for example, a claimed non-empty guard must inspect the same collection the loop uses).
- Treat a high suppression-to-fix ratio as a reason to read more closely, not as an automatic failure or approval.
- For pure-movement refactors, compare the moved source before and after to verify behavior did not change.
- If a guard fails, treat it as a possible real bug. Do not suppress or weaken the guard; leave it failing and report the evidence.
