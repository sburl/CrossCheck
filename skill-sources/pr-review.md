---
name: pr-review
description: Initiate autonomous PR review process with Codex agent
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-23-00-00

# PR Review with Codex Agent

This command automates the multi-agent PR review process between Codex and Codex.

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

## IMPORTANT: What "Codex Review" Means

**PR review = running `codex exec --full-auto` locally (this skill).**

Do NOT treat GitHub PR comments from bots (e.g., `chatgpt-codex-connector`) as the PR review.
Those are legacy artifacts from a removed integration — completely unrelated to this process.
Similarly, the `codex-commit-reviews.log` (post-commit hook) is a commit-level log, not a PR review.

**The only valid Codex review is the `codex exec` output from Step 2 below.**

## Step 2: Initiate Codex Review

Run Codex directly — no separate terminal needed:

```bash
codex exec --full-auto "You are an expert in reviewing code for bugs, usability, and merge suitability. An agent has just performed work in this repo and submitted PR {PR_NUMBER}. Please use GitHub CLI to review this PR and assess its suitability to be merged into the branch it came from or to main. You are connected directly to the agent so speak directly to it. Your only responsibility is to find and report issues so you should not offer to perform any coding on behalf of the agent. If the code is allowed to be merged please say so. The other agent will only proceed with merging the code if you explicitly tell it to merge and where to merge it." 2>&1
```

Replace {PR_NUMBER} with actual PR number from Step 1. Capture the full output.

## Step 3: Self-Assessment of Codex Feedback

Tell the user:
```
A review agent completed its pass. I will now critically assess the feedback and make changes as needed. I will only merge when explicitly told the PR can be merged and where to merge it.
```

Then review the Codex output and:
1. Critically assess each finding
2. Make changes if you agree
3. If you disagree, explain why
4. DO NOT merge unless Codex explicitly said to merge and specified destination

## Step 4: If Changes Made - Codex Follow-up

If you made changes based on Codex feedback, run another Codex pass:

```bash
codex exec --full-auto "The other agent made updates based on your feedback and shared the following comments. Please evaluate if the code actually resolves the issues you shared. The other agent also shared the below comments which may provide context on their decisions. If the code is allowed to be merged please say so. The other agent will only proceed with merging the code if you explicitly tell it to merge and where to merge it. Response: {your complete response explaining changes}" 2>&1
```

## Step 5: Continue Loop Until Approval

Repeat Steps 3-4 until Codex explicitly approves merge with destination.

## Step 6: Merge

When Codex explicitly approves:
```bash
gh pr merge {PR_NUMBER} --squash  # GitHub ruleset enforces squash-only merges
```

## Step 7: Return to Roadmap

After merge, return to the roadmap/priorities and continue with next feature.

## Relationship with /submit-pr

`/submit-pr` is the full workflow: techdebt → pre-check → create PR → **this skill** (review loop).
Use `/submit-pr` when starting from scratch. Use `/pr-review` directly when a PR already exists and just needs review.

## Automation Notes

This process can be enhanced with:
- Automated merge when specific approval phrase detected in Codex output
- Parsing Codex output to extract findings and apply them automatically
