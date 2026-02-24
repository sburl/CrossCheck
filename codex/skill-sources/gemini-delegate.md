---
name: gemini-delegate
description: "Delegate a coding task to Google Gemini agent for autonomous execution"
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-16-00-00

You are delegating a coding task to Gemini CLI. Gemini will analyze and execute the task.

## Delegation Pattern (shared with /codex-delegate)

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

Please analyze this task and provide:
1. Your implementation approach
2. The code changes needed
3. Any risks or considerations
```

Rules: Include CODEX.md context directly. Be specific about requirements. Do NOT tell the model how to implement or over-constrain the solution.

## Gemini-Specific Execution

### 3. Execute Gemini

```bash
gemini <<'EOF'
YOUR_PROMPT_HERE
EOF
```

Alternative if heredoc fails:
```bash
gemini "YOUR_PROMPT_HERE"
```

### 4. Apply Changes

Unlike Codex, Gemini does NOT auto-apply changes. YOU must:
1. Review the suggested changes
2. Use Edit/Write tools to apply them
3. Run any relevant tests or builds

### 5. Report Results

```
## Delegation Report

### Task: [what was delegated]
### Context Provided: [summary of CODEX.md context included]
### What Gemini Suggested: [analysis, code changes, risks]
### Changes Applied: [files created/modified]
### Verification: [did it meet success criteria? issues?]
### Follow-up: [remaining tasks, things to review]
```

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
- Inject CODEX.md content DIRECTLY into the prompt
- Unlike Codex, Gemini doesn't auto-apply changes - YOU must apply them
- If Gemini fails, report what happened and suggest fixes
