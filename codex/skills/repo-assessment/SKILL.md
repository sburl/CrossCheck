---
name: repo-assessment
description: Run comprehensive repo assessment with Codex (every 3 PRs)
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-23-00-00

# Comprehensive Repo Assessment (Every 3 PRs)

This command should be run after every 3 merged pull requests to keep the repo clean and world-class.

## Step 1: Check PR Counter

First, check how many PRs have been merged since last assessment:

```bash
# Check recent merged PRs
gh pr list --state merged --limit 10

# Or check the counter managed by the post-merge hook
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE" 2>/dev/null || echo "0"
```

If < 3 PRs since last assessment, skip this process.

## Step 2: Check for Recent Incident Memos

Before running the assessment, check if any incident memos were written since the last
assessment. These capture known failures and their root causes — Codex should factor
them into the analysis.

```bash
# List incident memos, newest first
ls -t docs/incidents/*.md 2>/dev/null | grep -v TEMPLATE | grep -v README || echo "No incident memos found"
```

If memos exist, read them and include a summary in the Step 3 prompt (see below).

## Step 3: Initiate Codex Assessment

Open a new terminal session for Codex agent:

```bash
# In new terminal, same repo directory
codex "Hi Codex, I have been using an inferior agent to you for the past few days and this repo has gotten a bit messy. I need your help to save me from spaghetti code! Please comprehensively assess this repo and develop a plan to get it back on track. Look for redundant/conflicting code and documentation. Suggest some concrete steps to make this repo world class."
```

If incident memos were found in Step 2, append to the prompt:

```
Also, the following incidents occurred since the last assessment. Factor their root
causes and follow-up items into your analysis:

[paste relevant memo content here]
```

## Step 4: Wait for Codex Comprehensive Assessment

Copy the complete Codex response when ready.

## Step 5: Codex Refactor Planning

Tell the user:
```
A review agent comprehensively assessed the entire repo. I will now critically assess this feedback, make changes as I see fit, and submit a pull request for the improvements.

Codex Assessment:
{paste complete Codex response here}
```

Then:
1. Critically assess the feedback
2. Create a new branch for refactoring: `git checkout -b refactor-codex-$(date +%Y%m%d)`
3. Make changes you agree with
4. If you disagree with feedback, explain why
5. Submit PR for the refactor

## Step 6: Follow Standard PR Review Process

Once refactor PR is submitted, follow the standard `/pr-review` process:
- Codex reviews the refactor PR
- Back-and-forth until approval
- Merge when explicitly approved

## Step 7: Reset PR Counter

After refactor is merged, the post-merge hook automatically resets the counter when it reaches 3.
To manually reset:

```bash
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
echo "0" > "$COUNTER_FILE"
echo "Last assessment: $(date +%Y-%m-%d-%H-%M)" >> .codex/assessment-history.txt
```

## Step 8: Run Full Cleanup

After the refactor is merged, clean up local git state that accumulated during the
assessment and refactor cycle:

```bash
/cleanup-all
```

This reviews worktrees, branches, and stashes in sequence. Review and approve any
generated scripts before running them.

## Step 9: Return to Roadmap

Return to roadmap/priorities and continue development.

## Tracking PRs

PR tracking is fully automated by the `post-merge` git hook. The counter is stored at
`$(git rev-parse --git-common-dir)/hooks-pr-counter` and incremented automatically on
every `git pull` that includes a merge. When the count reaches 3, the hook prints the
assessment waterfall reminder and resets the counter to 0.

**Manual check:**
```bash
COUNTER_FILE="$(git rev-parse --git-common-dir)/hooks-pr-counter"
cat "$COUNTER_FILE" 2>/dev/null || echo "0 (counter not yet initialized)"
```

No separate script or GitHub Action is needed -- the git hook handles everything.
