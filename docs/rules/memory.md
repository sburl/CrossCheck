# Memory Curation Rules

**Created:** 2026-02-24
**Last Updated:** 2026-02-24-01-31

Two memory systems operate in parallel. This file defines the curation rules for both.

---

## System 1: Auto-memory (`MEMORY.md`)

**Location:** `~/.claude/projects/[project]/memory/MEMORY.md`
**Scope:** User-level, cross-project patterns
**Auto-loaded:** Yes — always injected into session context (truncated at 200 lines)

### Curation Rules

**10-item cap per category.** When a category hits 10 items, drop the oldest or
least-recurring entry before adding a new one. Never let any category exceed 10 lines.

**50-line total cap.** If MEMORY.md exceeds 50 lines, it's too noisy. Merge
overlapping entries, remove anything that hasn't been relevant in 3+ sessions,
and consolidate categories.

**Prefer specific over general.**

| Good | Bad |
|------|-----|
| `Never use git reset --hard on shared branches` | `Be careful with git` |
| `Always run prisma generate before migrations in CI` | `Remember Prisma` |
| `Use bun, not npm or yarn, in all projects` | `Check package manager` |

**Format:** Semantic topics, not chronological logs. Organize by theme, not date.

**Write when:** A pattern has fired in 2+ projects or sessions. Not for one-offs.

---

## System 2: Per-repo Napkin (`.claude/napkin.md`)

**Location:** `.claude/napkin.md` inside the repo
**Scope:** This repo only — repo-specific behavioral corrections
**Committable:** Yes. Commit to share with contributors; add to `.gitignore` to keep personal.

### When to Use Napkin vs MEMORY.md

Use **napkin** for:
- Mistakes specific to this repo (e.g., "always run `prisma generate` before tests")
- User corrections that affect behavior in this repo only
- Surprising tool behavior rooted in this repo's config or conventions
- Non-obvious tactics that reliably work here but may not generalize

Use **MEMORY.md** for:
- Stable patterns across 2+ projects (e.g., "use bun not npm")
- Architectural decisions that apply broadly
- User preferences that should persist everywhere

### Session Protocol

**At session start:** If `.claude/napkin.md` exists, read it before doing anything.
Apply silently — don't announce it, just let it inform behavior.

```bash
# Check at session start (run mentally, not literally)
[ -f .claude/napkin.md ] && cat .claude/napkin.md
```

**During work:** Add entries as mistakes or corrections happen. Don't wait for end of session.

**Curation:** Same rules as MEMORY.md — 10-item cap per category, drop stale entries,
merge overlaps. Run `/napkin --curate` or curate manually.

### Entry Format

```
[YYYY-MM-DD] Rule title → Do X instead of Y
```

### Curation Rules (same as MEMORY.md)

- **10-item cap per category** — drop oldest or least-recurring at capacity
- **No timeline notes** — entries must have an explicit "do X" or "never do Y" action
- **Drop if stale** — hasn't come up in 3+ sessions? Remove it
- **Merge overlaps** — two entries about the same behavior → one specific rule

### Initialization

See `/napkin` skill for initialization steps and file format.

---

## Quick Reference

| Rule | MEMORY.md | napkin.md |
|------|-----------|-----------|
| Max items per category | 10 | 10 |
| Max total lines | 50 | No hard limit, but keep it lean |
| Scope | Cross-project | This repo only |
| Auto-loaded | Yes | Yes, if file exists (read at session start) |
| Committable | No | Yes (or gitignore — your choice) |
| Skill | (auto) | `/napkin` |
