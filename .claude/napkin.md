# CrossCheck Napkin

**Last Updated:** 2026-02-26

## PR Review vs GitHub Bot Comments — DO NOT CONFUSE

**The actual PR review process** is `/pr-review` which runs `codex exec --full-auto` locally.
Codex reviews the code, gives feedback, and you iterate until it explicitly approves merge.

**GitHub PR comments from bots (e.g., `chatgpt-codex-connector`)** are NOT the PR review.
These are leftover artifacts from a removed GitHub App integration. Ignore them completely.
Do not read them, do not respond to them, do not treat them as review feedback.

**The `codex-commit-reviews.log`** is a commit-level quick-check log (post-commit hook).
It is unrelated to PR reviews. It just logs commit info for optional manual review later.
The "📝 Commit logged for Codex review" message in terminal output is from this hook — it
does NOT mean a PR review happened.

**Summary:**
- PR review = `/pr-review` skill = `codex exec --full-auto` = local Codex execution
- GitHub bot comments on PRs = ignore, unrelated legacy artifact
- `codex-commit-reviews.log` = commit hook log, not PR review
