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
- **CODEX.md and docs/rules/ modifications require approval** (ask list) to prevent silent self-modification of agent constraints.

The real security boundary is server-side: GitHub branch protection, PR approval requirements, and the two-account model.
