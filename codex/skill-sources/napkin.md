---
name: napkin
description: |
  Per-repo behavioral memory stored in .claude/napkin.md. Use to initialize or
  update the napkin for any project. Tracks repo-specific mistakes, user corrections,
  and surprising gotchas that recur across sessions. Read silently at session start
  if the file exists. Write during work. Curate aggressively. Complement to MEMORY.md
  (which is cross-project and user-scoped); napkin is repo-scoped and committable.
date: 2026-02-24
source: adapted from https://github.com/blader/napkin by @blader (MIT)
---

**Created:** 2026-02-24-01-31
**Last Updated:** 2026-02-24-12-53

# Napkin

Per-repo behavioral memory that travels with the codebase.

Inspired by [napkin](https://github.com/blader/napkin) by [@blader](https://github.com/blader).

## Usage

```bash
/napkin          # Initialize napkin for this repo (or show current contents)
/napkin --update # Write a new entry from this session
/napkin --curate # Run curation pass: merge dupes, drop stale, enforce 10-item cap
```

---

## What Napkin Is (and Isn't)

**Napkin** is a curated runbook of repo-specific behavioral corrections.

| | Napkin (`.claude/napkin.md`) | Auto-memory (`~/.claude/projects/.../MEMORY.md`) |
|---|---|---|
| Scope | This repo only | Cross-project, user-level |
| Location | Inside the repo | In `~/.claude/projects/` |
| Committable | Yes — share with contributors | No — personal |
| Content | Behavioral corrections ("do X not Y") | Stable patterns, architectural decisions |
| Format | Categorized, 10-item cap | Semantic topics, 10-item cap |

---

## Session Protocol

**At session start:** If `.claude/napkin.md` exists in this repo, read it before
doing anything else. Apply it silently — don't announce it, just let it inform your
behavior.

**During work:** When you make a mistake, get corrected, or encounter a surprising
gotcha, add an entry. Don't wait for the end of the session.

**During curation (same session or next):** Re-prioritize entries. Merge duplicates.
Remove stale entries (haven't come up in 3+ sessions). Enforce the 10-item cap per
category.

---

## Entry Format

Each entry requires three things:

```
[YYYY-MM-DD] Rule title → Do X instead of Y
```

**Examples:**

```
[2026-02-23] Prisma in CI → Run `prisma generate` before tests or migration check fails
[2026-02-23] Branch naming → Use feat- prefix, not feature- (hooks enforce this)
[2026-02-23] Env file → Never read .env directly; use process.env in app code only
```

---

## File Format

```markdown
# Napkin — [Repo Name]

Last curated: YYYY-MM-DD

## Execution & Validation
- [YYYY-MM-DD] ...
- [YYYY-MM-DD] ...

## Shell & Command Reliability
- [YYYY-MM-DD] ...

## Domain Behavior Guardrails
- [YYYY-MM-DD] ...

## User Directives
- [YYYY-MM-DD] ...
```

**Rules:**
- Max 10 items per category. When at capacity, drop the oldest or least-recurring entry.
- 4 suggested categories (add repo-specific ones as needed, keep total categories ≤ 6)
- Entries must have an explicit action ("do X" or "never do Y") — no vague notes
- No one-off workarounds, verbose postmortems, or timeline notes

---

## Initialization

If `.claude/napkin.md` does not exist, create it:

```bash
mkdir -p .claude
cat > .claude/napkin.md << 'EOF'
# Napkin — [REPO NAME]

Last curated: YYYY-MM-DD

## Execution & Validation

## Shell & Command Reliability

## Domain Behavior Guardrails

## User Directives
EOF
```

Then add it to your `.gitignore` (keep it personal) **or** commit it (share with
contributors). Committing is recommended for shared repos where multiple agents
work on the same codebase.

---

## What Qualifies

**Add to napkin:**
- Mistakes you made in this repo that you made more than once
- User corrections that affect repeated behavior
- Surprising tool/environment behavior specific to this repo
- Non-obvious tactics that reliably work here

**Don't add to napkin:**
- One-off timeline notes ("had to fix X on 2026-02-23")
- Things that belong in MEMORY.md (cross-project patterns)
- Verbose postmortems without a clear "do X" action
- Information the docs already cover

---

## Curation Pass

Run a curation pass at the start of any session where the napkin feels noisy:

1. Re-prioritize: highest-frequency entries first within each category
2. Merge overlapping entries into one specific rule
3. Drop entries that haven't fired in 3+ sessions (they're probably stale)
4. Enforce 10-item cap: if over, drop the least-recurring entry
5. Update "Last curated" date
