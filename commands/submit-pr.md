---
name: submit-pr
description: Automated PR submission - runs pre-checks, creates PR, and starts review
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-00-00

# Submit PR (Automated)

This command automates the entire PR submission process:
1. Pre-PR checks
2. PR creation
3. Initiate Codex review

## Usage

```bash
/submit-pr
```

## Step 1: Run Pre-PR Checks

Automatically runs quality checks:

```bash
/techdebt      # Find and fix technical debt
/pre-pr-check  # Comprehensive checklist
```

**Checks include:**
- Technical debt scan
- Code quality (lint, tests)
- Documentation updates verified
- Timestamps checked
- Coach and testing agent assessment
- Self-review prompts

**If any checks fail, process stops here.**

## Step 1.5: Document Pre-Review Results

**IMPORTANT:** Document what was checked and fixed:

```markdown
## Pre-Review Checks Completed

### /techdebt Results
- Silenced lint errors: [found X, fixed X]
- Dead code: [found X, removed X]
- Code duplication: [found X, refactored X]
- Other issues: [list]

### /pre-pr-check Results
✅ All tests passing
✅ Documentation updated with timestamps
✅ Coach agent reviewed
✅ No critical issues

### Summary for Codex
This PR has been pre-screened with /techdebt and /pre-pr-check.
All technical debt addressed, tests passing, documentation current.
```

**Save this to include with Codex review (Step 4).**

## Step 2: Create Pull Request

Automatically creates PR with:

```bash
# Get current branch
BRANCH=$(git branch --show-current)

# Auto-generate PR title from branch name
TITLE=$(echo "$BRANCH" | sed 's/-/ /g' | sed 's/^./\u&/')

# Create PR with template
gh pr create \
  --title "$TITLE" \
  --body "$(cat <<EOF
## Summary
[Auto-generated - Claude Code will fill this in]

## Changes
$(git log main..HEAD --oneline)

## Testing
- [x] All tests passing
- [x] Coach agent reviewed
- [x] Documentation updated

## Documentation Updates
**Last Updated:** $(date +"%Y-%m-%d-%H-%M")

## Checklist
- [x] Pre-PR checks completed
- [x] Code tested
- [x] Docs updated with timestamps
- [x] Ready for Codex review
EOF
)"
```

## Step 3: Get PR Number

```bash
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number')
```

## Step 4: Generate Codex Review Prompt

**Generate Codex prompt with pre-review results:**

```
You are an expert in reviewing code for bugs, usability, and merge suitability. An agent has just performed work in this repo and submitted PR ${PR_NUMBER}.

PRE-REVIEW CHECKS COMPLETED:
[Include the pre-review documentation from Step 1.5]

Please use GitHub CLI to review this PR and assess its suitability to be merged into the branch it came from or to main. Consider the pre-review checks that were already completed. You are connected directly to the agent so speak directly to it. Your only responsibility is to find and report issues so you should not offer to perform any coding on behalf of the agent. If the code is allowed to be merged please say so. The other agent will only proceed with merging the code if you explicitly tell it to merge and where to merge it.
```

## Step 5: Pause for User Action

Tell the user:

```
✅ PR #${PR_NUMBER} created successfully!

Pre-review checks completed:
[Show summary from Step 1.5]

Next steps:
1. Open new terminal in same repo
2. Run this Codex command (includes pre-review context):

[Codex prompt with pre-review results]

3. Copy Codex response and return to this session
4. I'll continue from there
```

## Step 6: Wait for Codex Feedback

When user provides Codex feedback, automatically:
1. Critically assess feedback
2. Make necessary changes
3. Push fixes and continue review loop
4. Merge when explicitly approved

## Step 7: Post-Merge Automation

After merge, the `post-merge` git hook automatically:
- Increments the PR counter (stored at `$(git rev-parse --git-common-dir)/hooks-pr-counter`)
- Displays an assessment waterfall reminder when 3 PRs have been merged
- Resets the counter after the reminder

```bash
# Just pull main -- the post-merge hook handles counter tracking
git checkout main && git pull

# If the hook says "Assessment waterfall due", run:
/repo-assessment
/bug-review
/security-review

# Return to roadmap
```

## Complete Automation Flow

```
Developer finishes feature
         ↓
    /submit-pr
         ↓
Pre-checks run automatically
         ↓
PR created automatically
         ↓
Codex review prompt provided
         ↓
[User runs Codex in new terminal]
         ↓
Claude ↔ Codex review loop
         ↓
Merge when approved
         ↓
PR counter auto-increments (post-merge hook)
         ↓
Assessment reminder if needed
         ↓
Return to roadmap
```

## Error Handling

If pre-checks fail:
- Show which checks failed
- Provide guidance to fix
- Don't create PR until resolved

If PR creation fails:
- Check if PR already exists
- Verify branch is pushed
- Show error details

If Codex review stalls:
- Timeout after 30 minutes
- Prompt user for manual intervention
- Save session state for resume

## Customization

Users can customize PR template by creating:
`.claude/pr-template.md`

This will be used instead of default template.
