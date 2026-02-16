---
name: codex-delegate
description: "Delegate a coding task to OpenAI Codex agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

You are delegating a coding task to a headless Codex agent. Codex will do the actual implementation work.

## Your Task

1. Identify the task from conversation context
2. Read CLAUDE.md and inject context directly into the prompt
3. Execute Codex and report results

### Step 1: Identify the Task from Context

Review the conversation history and identify:
- What coding task does the user want accomplished?
- What files/areas of the codebase are involved?
- What does "done" look like?

Restate the task clearly. If unclear, ask the user to clarify.

### Step 2: Gather Context

1. Read CLAUDE.md if it exists - extract relevant project context
2. Use Read/Grep/Glob to find relevant code patterns
3. Note any conventions or styles to follow

### Step 3: Formulate Task for Codex

Write a detailed task specification that INCLUDES the CLAUDE.md context directly:

```
# Project Context
[Paste relevant sections from CLAUDE.md here]

# Task
[Clear description based on conversation context]

# Relevant Files
[List key files Codex should know about]

# Requirements
- [specific requirement 1]
- [specific requirement 2]

# Success Criteria
- [how to know it's done correctly]
```

Do NOT:
- Tell Codex how to implement (let it decide)
- Over-constrain the solution

DO:
- Include CLAUDE.md context directly in the prompt
- Be specific about requirements
- State clear success criteria

### Step 4: Execute Codex

Run Codex with your formulated task:

```bash
codex exec --full-auto "YOUR_TASK_WITH_CONTEXT_HERE" 2>&1
```

The `--full-auto` flag enables:
- `--sandbox workspace-write` - Can modify files in the workspace
- `-a on-request` - Model decides when to ask for approval

### Step 5: Report Results

## Delegation Report

### Task Identified
[The task you identified from context]

### Context Provided
[Summary of CLAUDE.md context you included]

### What Codex Did
- Files created/modified
- Summary of changes

### Verification
- Did it meet the success criteria?
- Any issues encountered?

### Files Changed
[List with brief descriptions]

### Follow-up Needed
- [ ] Any remaining tasks
- [ ] Things to review

---

## Important

- YOU identify the task from conversation context
- Inject CLAUDE.md content DIRECTLY into the prompt (don't create AGENTS.md)
- If Codex fails, report what happened and suggest fixes
- You can run Codex multiple times with refined prompts
