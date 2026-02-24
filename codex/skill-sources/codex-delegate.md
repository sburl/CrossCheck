---
name: codex-delegate
description: "Delegate a coding task to OpenAI Codex agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-16-00-00

You are delegating a coding task to a headless Codex agent. Codex will do the actual implementation work.

## Delegation Pattern (shared with /gemini-delegate)

### 1. Identify Task

Review conversation context. Restate the task clearly: what to do, which files, what "done" looks like. If unclear, ask the user.

### 2. Gather Context & Formulate Prompt

Read CODEX.md and relevant code. Build ONE prompt with this structure:

```
# Project Context
[Relevant sections from CODEX.md]

# Task
[Clear description from conversation context]

# Relevant Files
[Key files the model should know about]

# Requirements
- [specific requirements]

# Success Criteria
- [how to verify it's done correctly]
```

Rules: Include CODEX.md context directly. Be specific about requirements. Do NOT tell the model how to implement or over-constrain the solution.

## Codex-Specific Execution

### 3. Execute Codex

```bash
codex exec --full-auto "YOUR_PROMPT_HERE" 2>&1
```

`--full-auto` enables `--sandbox workspace-write` and `-a on-request` (model decides when to ask for approval). Codex auto-applies changes to the workspace.

### 4. Report Results

```
## Delegation Report

### Task: [what was delegated]
### Context Provided: [summary of CODEX.md context included]
### What Codex Did: [files created/modified, summary of changes]
### Verification: [did it meet success criteria? issues?]
### Follow-up: [remaining tasks, things to review]
```

## Important

- YOU identify the task from conversation context
- Inject CODEX.md content DIRECTLY into the prompt (don't create AGENTS.md)
- If Codex fails, report what happened and suggest fixes
- You can run Codex multiple times with refined prompts
