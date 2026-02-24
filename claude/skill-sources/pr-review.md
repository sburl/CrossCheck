---
name: pr-review
description: Initiate autonomous PR review process with Claude agent
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-16-00-00

# PR Review with Claude Agent

This command automates the multi-agent PR review process between Claude and Claude.

## Step 1: Pre-Review Checklist

Before starting the review:

1. **Verify code assessment completed**
   - Worked with coach and testing agents?
   - All code tested?
   - If tests failed 3x, is there a note in the PR?

2. **Verify documentation updated**
   - All relevant docs updated?
   - Stale docs deleted?
   - Timestamps updated on all modified docs?

3. **Get PR number**
   ```bash
   gh pr list --head $(git branch --show-current)
   ```

If checklist incomplete, stop and complete it first.

## Step 2: Initiate Claude Review

Open a new terminal session for Claude agent:

```bash
# In new terminal, same repo directory
claude "You are an expert in reviewing code for bugs, usability, and merge suitability. An agent has just performed work in this repo and submitted PR {PR_NUMBER}. Please use GitHub CLI to review this PR and assess its suitability to be merged into the branch it came from or to main. You are connected directly to the agent so speak directly to it. Your only responsibility is to find and report issues so you should not offer to perform any coding on behalf of the agent. If the code is allowed to be merged please say so. The other agent will only proceed with merging the code if you explicitly tell it to merge and where to merge it."
```

Replace {PR_NUMBER} with actual PR number from Step 1.

## Step 3: Wait for Claude Response

Copy the complete Claude response when ready.

## Step 4: Claude Self-Assessment

Tell the user:
```
A review agent shared the below feedback. I will now critically assess this feedback and change things as needed. I will only merge when explicitly told the PR can be merged and where to merge it.

Claude Feedback:
{paste complete Claude response here}
```

Then:
1. Critically assess the feedback
2. Make changes if you agree
3. If you disagree, explain why
4. DO NOT merge unless Claude explicitly said to merge and specified destination

## Step 5: If Changes Made - Claude Follow-up

If you made changes based on Claude feedback, provide this prompt to Claude:

```bash
claude "The other agent made updates based on your feedback and shared the following comments. Please evaluate if the code actually resolves the issues you shared. The other agent also shared the below comments which may provide context on their decisions. If the code is allowed to be merged please say so. The other agent will only proceed with merging the code if you explicitly tell it to merge and where to merge it. Response: {your complete response explaining changes}"
```

## Step 6: Continue Loop Until Approval

Repeat Steps 3-5 until Claude explicitly approves merge with destination.

## Step 7: Merge

When Claude explicitly approves:
```bash
gh pr merge {PR_NUMBER} --squash  # GitHub ruleset enforces squash-only merges
```

## Step 8: Return to Roadmap

After merge, return to the roadmap/priorities and continue with next feature.

## Relationship with /submit-pr

`/submit-pr` is the full workflow: techdebt → pre-check → create PR → **this skill** (review loop).
Use `/submit-pr` when starting from scratch. Use `/pr-review` directly when a PR already exists and just needs review.

## Automation Notes

This process can be enhanced with:
- Script to automatically pass messages between Claude and Claude sessions
- WebSocket or file-based communication between terminals
- Automated merge when specific approval phrase detected
