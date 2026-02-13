**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-11-00-00

# Security (Boundary-Based Trust)

**Philosophy:** Feature branches = permissive. Main = requires separate identity.

## Feature branches (client-side - permissive)

- Can rebase, force-push, experiment freely
- Agents have full control
- Still block: `rm`, `git reset --hard`, `.env` reads, `sudo`, `docker`, `while read` loops

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
