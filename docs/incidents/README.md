**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-24-12-53

# Incident Memos

Lightweight after-action records for significant events: production incidents, failed
migrations, security findings, or any situation where something went meaningfully sideways.

## When to write one

- A deployment caused user-facing breakage
- A security issue was found (in code review or in production)
- A refactor created unexpected regressions
- An architectural decision turned out to be wrong
- A feature shipped but missed the actual goal

**Don't** write one for routine bugs caught in code review or normal PR iteration.

## Naming convention

```
YYYY-MM-DD-short-description.md
```

Examples:
```
2026-02-23-auth-migration-rollback.md
2026-03-01-rate-limiter-memory-leak.md
2026-03-15-wrong-success-criteria-search-feature.md
```

## How it integrates

During `/repo-assessment` Step 2, you list memos written since the last assessment,
read them, and paste relevant content into the Codex prompt. The skill guides you through
this — it is a manual read step, not automatic.

## Template

See `TEMPLATE.md` for the five-field format.
