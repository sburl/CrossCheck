---
description: "Delegate a coding task to Google Gemini agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

You are delegating a coding task to Gemini CLI. Gemini will analyze and execute the task.

## Your Task

1. Identify the task from conversation context
2. Read CLAUDE.md and inject context directly into the prompt
3. Execute Gemini and report results

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

### Step 3: Formulate Task for Gemini

Write a detailed task specification that INCLUDES the CLAUDE.md context directly:

```
# Project Context
[Paste relevant sections from CLAUDE.md here]

# Task
[Clear description based on conversation context]

# Relevant Files
[List key files Gemini should know about]

# Requirements
- [specific requirement 1]
- [specific requirement 2]

# Success Criteria
- [how to know it's done correctly]

Please analyze this task and provide:
1. Your implementation approach
2. The code changes needed
3. Any risks or considerations
```

Do NOT:
- Tell Gemini how to implement (let it decide)
- Over-constrain the solution

DO:
- Include CLAUDE.md context directly in the prompt
- Be specific about requirements
- State clear success criteria

### Step 4: Execute Gemini

Run Gemini with your formulated task using a heredoc for shell safety:

```bash
gemini <<'EOF'
YOUR_TASK_WITH_CONTEXT_HERE
EOF
```

Alternative if heredoc fails:
```bash
gemini "YOUR_TASK_WITH_CONTEXT_HERE"
```

### Step 5: Apply Changes (if applicable)

If Gemini provides code changes:
1. Review the suggested changes
2. Use Edit/Write tools to apply them
3. Run any relevant tests or builds

### Step 6: Report Results

## Delegation Report

### Task Identified
[The task you identified from context]

### Context Provided
[Summary of CLAUDE.md context you included]

### What Gemini Suggested
- Analysis/approach
- Code changes proposed
- Risks identified

### Changes Applied
- Files created/modified
- Summary of changes

### Verification
- Did it meet the success criteria?
- Any issues encountered?

### Follow-up Needed
- [ ] Any remaining tasks
- [ ] Things to review

---

## Error Handling

If Gemini fails with auth error:
```
Please set GEMINI_API_KEY in your environment:
  export GEMINI_API_KEY="your-key-here"
  # Add to ~/.zshrc for persistence
```

If Gemini times out or returns partial output, report what was received and suggest retry.

## Important

- YOU identify the task from conversation context
- Inject CLAUDE.md content DIRECTLY into the prompt
- Unlike Codex, Gemini doesn't auto-apply changes - YOU must apply them
- If Gemini fails, report what happened and suggest fixes
