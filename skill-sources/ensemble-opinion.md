---
name: ensemble-opinion
description: 'Get multi-model opinions on a problem (Claude + Gemini + Codex)'
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

You are orchestrating an ensemble of AI models to analyze a problem from multiple angles.

## Your Task

1. Identify the problem from conversation context
2. Run ALL THREE models in PARALLEL using the Task tool
3. Synthesize their responses

### Step 1: Identify the Problem from Context

Review the conversation history and identify:

- What problem or decision is the user facing?
- What's the relevant context (codebase, constraints, goals)?

Restate the problem clearly and factually in 2-3 sentences. This exact problem statement will be sent to ALL models to ensure consistency.

If CLAUDE.md exists, read it and include relevant context in the problem statement.

### Step 2: Formulate the Unbiased Prompt

Create ONE prompt that will be sent to all models. Structure:

```
Problem: [factual description - same for all models]
Context: [relevant codebase/project details from CLAUDE.md if exists]
Constraints: [any limitations]

Analyze this problem. Provide:
1. Your assessment of the situation
2. Risks and failure modes
3. Alternative approaches
4. Your recommendation

Be direct and critical. Identify blind spots.
```

### Step 3: Run All Three Models in PARALLEL

Use the Task tool to spawn THREE agents simultaneously in a SINGLE message:

1. **Claude Critic** (subagent_type: claude_critic)

   - Pass: the unbiased prompt
   - Ask for: critical analysis, risks, blind spots, alternatives

2. **Gemini Agent** (subagent_type: general-purpose)

   - Prompt: "Run this command and return the output: `echo '<UNBIASED_PROMPT>' | gemini 2>&1`. If Gemini fails due to auth, return the error message."

3. **Codex Agent** (subagent_type: general-purpose)
   - Prompt: "Run this command and return the output: `codex exec '<UNBIASED_PROMPT>' 2>&1 | tail -50`. Return the model's response, stripping metadata headers."

IMPORTANT: Launch all three Task tools in a SINGLE response so they run in parallel.

### Step 4: Synthesize

Once all three return, synthesize:

## Ensemble Synthesis

### Problem Analyzed

[The problem you identified]

### Panel Responses

- **Claude**: [key points from claude_critic]
- **Gemini**: [key points, or "unavailable" if auth failed]
- **Codex**: [key points from codex response]

### Consensus

What do multiple models agree on?

### Disagreements

Where did they differ? Why?

### Blind Spots

What did none address?

### Recommendation

Your integrated recommendation.

### Next Actions

- [ ] Actionable steps

---

## Error Handling

- If Gemini fails (auth): note it, continue with Claude + Codex
- If Codex fails (timeout): note it, continue with available responses
- If only one model responds: still provide that opinion, note limitations
- Always report which models succeeded/failed

## Important

- Use the SAME prompt for all models (consistency)
- Launch all 3 in PARALLEL (single message with 3 Task calls)
- Inject CLAUDE.md context directly into prompt (don't rely on AGENTS.md)
- Do NOT pre-bias external models with your opinions
- Your job is synthesis, not validation
