---
name: codex-delegate
description: "Delegate a coding task to OpenAI Claude agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-11-23-23-20

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
claude -p --permission-mode acceptEdits "YOUR_PROMPT_HERE" 2>&1
```

`-p` runs a non-interactive session and `acceptEdits` allows workspace edits while retaining the CLI's other permission checks.

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
