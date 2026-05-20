**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-17-00-00

# Security (Boundary-Based Trust)

**Philosophy:** Feature branches = permissive. Main = requires separate identity.

## Feature branches (client-side - permissive)

- Can rebase, force-push, experiment freely
- Agents have full control
- Still block: `rm`, `git reset --hard`, sensitive file reads (`.env`, `.ssh`, `.aws`, `.pem`, `.key` via Read tool + cat/head/tail/sed/awk/grep), `sudo`, `docker`, `while read` loops, data-sending `curl` (POST/PUT/PATCH/-d/-F/-T/--json/--upload), `git config` for hooks/aliases, `git commit -n` (--no-verify short form)

## Main branch (server-side - strict)

GitHub enforces identity-based rules:

- No force-push to main
- No direct commits to main
- PR required with external approval
- Can't self-approve (account that pushed can't approve)
- Squash-only merge
- Linear history only
- **Need separate account** to approve PRs you create

## Absolute prohibitions

**NEVER bypass branch protections.** These are hard rules that no agent may violate under any circumstances:

- **NEVER use `--admin` flag** on `gh pr merge` or any `gh` command. This bypasses branch protection rules and defeats the entire trust model.
- **NEVER modify GitHub rulesets** via `gh api` or any other mechanism. Rulesets are configured once by the human via `/setup-automation` and must not be weakened, relaxed, or changed by agents.
- **NEVER modify branch protection settings** via the GitHub API. This includes changing `required_approving_review_count`, `require_last_push_approval`, `require_code_owner_review`, or any other protection parameter.
- If a PR is blocked by branch protection, **that is working as intended**. The correct response is to get a legitimate review from a separate account, not to bypass the protection.

These are enforced by deny rules in `settings.json` (`gh*--admin*`, `*--admin*`, `gh api*rulesets*`, `gh api*branches/*/protection*`, `*graphql*BranchProtection*`, `*graphql*Ruleset*`), but the prohibition is absolute regardless of settings. The `*--admin*` catch-all prevents command-prefixing bypasses (e.g. `cd . && gh pr merge --admin`). The GraphQL patterns prevent ruleset mutation via the GitHub GraphQL API.

## Required merge convention: `gh pr merge --auto`

**ALWAYS use `gh pr merge --auto`** (not bare `gh pr merge`) when merging PRs.

**Why:** Bare `gh pr merge` attempts the merge immediately. Parallel merge invocations against the same base branch race; GitHub creates the merge commit but only one fast-forward succeeds, leaving the loser reported as "MERGED" with a `mergeCommit.oid` that is **not in main's ancestry**. We hit this on 2026-05-20 — PR #2340 was reported merged but its commit never landed, and a historical audit found 3 prior occurrences (#2096, #1670, #1434).

`--auto` queues the merge to fire only when checks pass and the base is current, eliminating the race entirely. It also waits for branch-protection conditions instead of failing outright.

**Pattern:**
```bash
gh pr merge $PR_NUMBER --auto --squash --delete-branch
```

The `--squash` matches the squash-only ruleset; `--delete-branch` keeps the branch list clean; `--auto` is what prevents the lost-race class.

## Why this works

- Agents work freely on feature branches
- Main requires genuine external review
- Builder != Reviewer (different accounts required)

## Zero Trust Details

**Mindset:** Builder + Adversary simultaneously

Every change:

1. Code + tests together
2. Question assumptions
3. Run tests
4. Pass = continue

**Unfamiliar behavior?** Run tests to find out, don't assume.

## Deny List Limitations

The deny list is defense-in-depth, not a sandbox. Known limitations:

- **General-purpose runtimes bypass all deny rules.** `python3`, `node`, and similar runtimes can execute arbitrary system commands internally. The deny list only pattern-matches the top-level bash command.
- **`gh api` requires human approval** (ask list) but specific `gh` subcommands (pr, issue, run) are auto-allowed.
- **`source` requires human approval** (ask list) since sourced scripts can execute denied commands.
- **CLAUDE.md and docs/rules/ modifications require approval** (ask list) to prevent silent self-modification of agent constraints.

The real security boundary is server-side: GitHub branch protection, PR approval requirements, and the two-account model.
