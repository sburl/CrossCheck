# Codex Agent Review Prompts

**Created:** 2026-02-02-14-50
**Last Updated:** 2026-02-16-00-00

This file contains the exact prompts to use when coordinating with Codex agent for architecture review, test review, PR reviews, and repo assessments.

## Core Principle

**Reviewer model reviews, Codex writes.** The reviewer is a quality gate: it critiques Codex's work but does not implement code, suggest full rewrites, or drive design decisions.

## Pre-Implementation Review Prompts

### Architecture Review (CodexArch)

**When:** Before implementing complex features (3+ files, new architecture, unclear approach)

**Prompt to Codex:**

```text
You are an expert software architect reviewing an implementation plan. An agent has created the following architecture document for {feature}:

---
{paste architecture document here}

Files to create/modify: {list}
Approach: {description}
Trade-offs: {considerations}
Test strategy: {plan}
Security considerations: {notes}
Performance implications: {analysis}
---

Review this architecture and provide feedback on:
1. **Architectural soundness** - Is this approach sound?
2. **Better patterns** - Are there better approaches or patterns?
3. **Risks and gotchas** - What could go wrong?
4. **Missing considerations** - What's not addressed?
5. **Test strategy** - Is the test plan comprehensive?
6. **Security implications** - Any security concerns?

CRITICAL: Your role is to REVIEW the plan, not write it. Identify issues and suggest improvements, but don't provide implementation details or code.

Provide CRITICAL/HIGH/MEDIUM/LOW severity feedback for each issue.
```

**Replace `{feature}`, `{paste architecture document}`, etc. with actual content.**

---

### Test Quality Review (CodexTest)

**When:** After tests are written, before finalizing implementation (for complex features)

**Prompt to Codex:**

```text
You are an expert in test quality and coverage. An agent has written tests for {feature}.

Test files:
{list test files with paths}

Review test quality ONLY - do NOT review implementation code yet.

Evaluate:
1. **Test coverage** - What's missing? What edge cases aren't covered?
2. **Regression detection** - Would these tests catch regressions?
3. **Test readability** - Are tests clear and maintainable?
4. **Mock strategy** - Is the mock/fixture approach appropriate?
5. **Behavior verification** - Do tests verify behavior, not implementation details?
6. **Additional test cases** - What test cases should be added?

CRITICAL: Your role is to REVIEW test quality, not write tests. Identify gaps and suggest test cases, but don't provide test code.

Provide CRITICAL/HIGH/MEDIUM/LOW severity feedback for each issue.
```

**Replace `{feature}` and `{list test files}` with actual content.**

---

## PR Review Process with Agent Teams

### Spawning Reviewer Teammate (Codex-initiated)

**When:** After submitting a PR, before merge

**Using Agent Teams (Recommended):**

The primary Codex session spawns a reviewer teammate:

```text
Create an agent team for PR #{number} review. Spawn one reviewer teammate with the prompt:

"You are an expert in reviewing code for bugs, security, quality, and merge suitability. Review PR #{number} using GitHub CLI.

PRE-REVIEW CHECKS COMPLETED:
{techdebt and pre-pr-check results}

Review for:
1. **Code correctness** - Bugs, logic errors, edge cases
2. **Security issues** - OWASP Top 10 (SQL injection, XSS, auth bugs, secrets in code, etc.)
3. **Test quality** - Coverage, edge cases, would catch regressions
4. **Architecture fit** - Follows project patterns, maintainable
5. **Performance** - Any obvious performance issues
6. **Documentation** - Docs match code, timestamps updated

CRITICAL: Your role is to REVIEW the code, not write it. Identify issues but don't provide implementation details - just point out what's wrong.

Your only responsibility is to find and report issues. Do not offer to perform coding. If the code is allowed to be merged, say so explicitly and specify the destination branch. I will only proceed with merging if you explicitly tell me to merge and where to merge it.

Provide CRITICAL/HIGH/MEDIUM/LOW severity feedback for each issue."
```

The reviewer teammate runs autonomously, sends findings via SendMessage, and the lead responds with fixes. Loop continues until approval.

---

### Codex Pre-Review Information (Gate01.5)

**When:** BEFORE sending to Codex, after running /techdebt and /pre-pr-check (if available)

**What Codex should document:**

```markdown
## Pre-Review Checks Completed

### /techdebt Results
[Output from /techdebt command]
- Issues found: [list]
- Issues fixed: [list]
- Issues remaining: [list with justification]

### /pre-pr-check Results
[Output from /pre-pr-check command]
- All checks passed: [yes/no]
- Any failures: [explain]

### Summary for Codex
This PR has been pre-screened with /techdebt and /pre-pr-check (if available).
[Brief summary of what was cleaned up before review, or note if skills not available]
```

**Save this info to include when spawning the reviewer teammate.**

---

### Agent Team Communication

**Using Agent Teams:**

- Codex reviewer sends findings via **SendMessage** to the lead
- Lead assesses feedback, makes changes, and responds via **SendMessage**
- Loop continues automatically until Codex approves
- No manual copy-paste needed - agents communicate directly
- When Codex approves, lead merges and cleans up team

**Manual Alternative (if Agent Teams unavailable):**

If not using Agent Teams, use the manual process:
1. Run Codex review in separate terminal
2. Copy Codex response
3. Paste to the primary coding session: "A review agent shared this feedback: {response}"
4. Primary coding session makes changes
5. Copy the update summary
6. Paste back to the reviewer: "The agent made these updates: {response}"
7. Repeat until Codex approves

---

## Comprehensive Repo Assessment Prompts

### Codex Assessment (Codex11)

**When:** After every 3 merged PRs

**Prompt to Codex:**

```text
Hi Codex, I have been using an agent that doesn't think like you for the past few PRs and this repo has gotten a bit messy. I need your help to save me from uncaught errors and spaghetti code entropy! Please comprehensively assess this repo and develop a plan to get it back on track. Look for redundant/conflicting code and documentation. Suggest some concrete steps to make this code world class.
```

---

### Codex Refactor Response (Gate12)

**When:** After receiving Codex's comprehensive assessment

**Prompt to Codex:**

```text
A review agent comprehensively assessed the entire repo and had the below feedback. Please critically assess this feedback, change things as you see fit, and submit a pull request for the changes. If you disagree with any of the feedback please say so. You may merge only when the other agent explicitly tells you the PR can be merged and to where it can be merged. Feedback: {complete Codex response to prior message}
```

**Replace `{complete Codex response to prior message}` with Codex's full assessment.**

**Follow standard Agent Teams review flow for this refactor PR until merged.**

---

## Usage Notes

### PR Review Flow (Agent Teams)

1. Run /techdebt and /pre-pr-check if available
2. Fix all issues found
3. Submit PR
4. Spawn reviewer teammate (see "Spawning Reviewer Teammate" above)
5. Codex reviews and sends feedback via SendMessage
6. Lead assesses feedback, makes changes
7. Lead responds to Codex via SendMessage
8. Codex re-reviews
9. Loop continues automatically until Codex approves
10. Merge when explicitly told where to merge
11. Clean up team

### Assessment Flow

1. After 3rd merged PR
2. Use **Codex11** prompt in your Codex terminal
3. Copy Codex response
4. Use **Gate12** prompt with Codex's response
5. Primary coding session creates refactor PR
6. Follow standard Agent Teams review flow until approved

### Tips

- Always copy **complete** responses (don't truncate)
- Wait for **explicit merge approval** with destination
- If Codex says "looks good" but doesn't say "merge to X", ask for explicit approval

---

## Direct Codex Debugging (File-Based Pattern)

For complex debugging that benefits from a second model's perspective, use the file-based question/answer pattern.

### When to Use

- Debugging subtle bugs (off-by-one errors, race conditions, bitstream alignment)
- Analyzing complex algorithms against specifications
- Getting detailed code review with specific bug identification
- When you've tried multiple approaches and are stuck

### The Pattern

### Step 1: Write the question

```bash
cat > /tmp/question.txt << 'QUESTION'
I have a [component] that fails with [specific error].

Here is the full function:
[paste complete code - don't truncate]

Key observations:
1. [What works]
2. [What fails]
3. [When it fails]

Can you identify:
1. [Specific question 1]
2. [Specific question 2]

Please write a detailed analysis to /tmp/reply.txt
QUESTION
```

### Step 2: Run Codex

```bash
cat /tmp/question.txt | codex exec --full-auto
```

Flags:

- `exec`: Non-interactive execution mode (required for CLI use)
- `--full-auto`: Run autonomously without prompts
- Do NOT use the `-o` flag (overwrites analysis with conversational stdout)

### Step 3: Read the analysis

```bash
cat /tmp/reply.txt
```

Evaluate suggestions critically. Codex may identify real bugs but can occasionally misinterpret specifications. Always verify against authoritative sources.

### Best Practices

- **Provide complete code** - Don't truncate functions. Codex needs full context.
- **Be specific** - "Why does Huffman decoding fail after 1477 blocks?" > "Why does this fail?"
- **Include the spec** - Mention relevant spec sections if debugging against a standard.
- **Iterate** - Create a new question.txt with additional context if first response doesn't solve it.

### Quick Alternative

For shorter questions:

```bash
echo "Explain the difference between X and Y in this codebase" | codex exec --full-auto
```

But for debugging, the file-based pattern is better for refining questions and keeping records.

---

## Post-Commit Hook Setup

Codex post-commit hooks provide automated review feedback after feature commits.

### What It Does

The hook triggers on **feature commits only** -- commits prefixed with `feat:`, `fix:`, `refactor:`, or `test:`. Other commit types (`chore:`, `docs:`, `ci:`, etc.) are skipped.

Supported formats:

- `feat: add login` -- standard feature commit
- `fix(auth): validate tokens` -- scoped commit
- `feat!: remove legacy API` -- breaking change
- `feat(core)!: new auth system` -- scoped breaking change

The hook logs a review prompt to `~/.codex/codex-commit-reviews.log` for asynchronous Codex review.

### Installation

```bash
# Install for current repo only:
~/.crosscheck/scripts/install-codex-hooks.sh

# Install globally for all repos:
~/.crosscheck/scripts/install-codex-hooks.sh --global
```

The installer uses a `post-commit.d/` dispatcher pattern -- your existing post-commit hooks are preserved.

### Skipping Reviews

To skip Codex review for a single commit:

```bash
SKIP_CODEX_REVIEW=1 git commit -m "chore: quick fix"
```

This sets an environment variable that the hook checks on entry. This is the correct skip mechanism -- `post-commit` hooks run after the commit is already created, so `--no-verify` only affects `pre-commit` and `commit-msg` hooks and has no effect on post-commit hooks.

### How It Works

1. Post-commit hook fires after every `git commit`
2. Hook checks if commit message matches feature commit pattern
3. Non-feature commits exit immediately (no overhead)
4. Feature commits: hook logs a review prompt with commit details
5. Review prompt is appended to `~/.codex/codex-commit-reviews.log`
6. Codex reviews are processed asynchronously via Codex

### Files

| File | Purpose |
|------|---------|
| `scripts/codex-commit-review.sh` | The review hook script |
| `scripts/install-codex-hooks.sh` | One-command installer |
| `git-hooks/post-commit` | Dispatcher that runs `post-commit.d/` scripts |

### Troubleshooting

**Hook not running?** Check that the dispatcher is installed and executable:

```bash
ls -la .git/hooks/post-commit
ls -la .git/hooks/post-commit.d/codex-review
```

**Want to disable temporarily?** Use the `SKIP_CODEX_REVIEW` environment variable, or remove the hook:

```bash
rm .git/hooks/post-commit.d/codex-review
```
