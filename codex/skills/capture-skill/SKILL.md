---
name: capture-skill
description: |
  Extract and persist a non-obvious discovery from the current session as a reusable skill.
  Use after: debugging a non-obvious error, finding a workaround through trial-and-error,
  resolving an environment/config/dependency issue the docs didn't cover, discovering a
  project-specific pattern through investigation, or completing any task where the solution
  required genuine discovery rather than straightforward documentation lookup.
---

**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-23-00-00

*Inspired by [Claudeception](https://github.com/blader/Claudeception) by [@blader](https://github.com/blader).*

# Capture Skill

Distill a non-obvious discovery from this session into a reusable skill file, persisted to
`~/.claude/commands/` and `~/.codex/commands/` so it auto-loads in future sessions when
the trigger conditions match.

## Usage

```bash
/capture-skill                  # Evaluate session and extract if warranted
/capture-skill --force          # Skip quality gate, go straight to extraction
/capture-skill --dry-run        # Show what would be extracted without writing
```

---

## Step 1: Apply Quality Gate

Before extracting anything, answer all four questions. If any answer is **No**, stop — the
knowledge doesn't meet the bar for a skill.

| # | Question | Required answer |
|---|----------|-----------------|
| 1 | Did solving this require actual discovery, not just reading docs or obvious reasoning? | Yes |
| 2 | Could this come up again in a different project or session? | Yes |
| 3 | Are there clear, specific trigger conditions (error messages, symptoms, scenarios)? | Yes |
| 4 | Was the solution verified to actually work (not just hypothesized)? | Yes |

If `--force` was passed, skip this gate and proceed.

If all four are Yes: continue to Step 2.
If not: respond with a brief explanation of which gate(s) failed, and stop.

---

## Step 2: Draft the Skill

Gather the following before writing:

**Skill name** — kebab-case, specific, searchable. Prefer error names or tool names over
generic descriptions. Examples:
- `prisma-connection-pool-serverless` ✓
- `database-fix` ✗

**Description** — This is the most important field. Claude and Codex load it at startup and
match it against context. Make it specific enough to fire on the right problems:
- Name exact error messages, codes, or symptoms
- Name the tools, frameworks, or environments involved
- State the scenario in plain language
- Keep it under 6 lines

**Trigger conditions** — The exact circumstances that should activate this skill:
exact error text, environment, file types, config state, etc.

**Solution** — Step-by-step. Include the exact commands, code, or config changes.
No hand-waving.

**Verification** — How to confirm the fix worked.

---

## Step 3: Write the Skill File

Choose a slug: `<slug>` (kebab-case)

Write the file to a temporary path first, then install:

```bash
# Determine today's date
DATE=$(date +%Y-%m-%d)
SLUG="<slug>"
```

**File content** (fill in all fields):

```markdown
---
name: <slug>
description: |
  <Specific description — name exact errors, tools, and trigger scenarios.
  This text is matched semantically against session context at load time.
  Vague descriptions won't match. Specific ones will.>
author: Codex
version: 1.0.0
date: <YYYY-MM-DD>
source: captured via /capture-skill (CrossCheck)
---

**Created:** <YYYY-MM-DD>
**Last Updated:** <YYYY-MM-DD>

# <Title>

## Problem

<What went wrong or what needed to be discovered>

## Trigger Conditions

<Exact error messages, symptoms, environment details, or scenarios that indicate
this skill is relevant. Be specific — these are what enable future retrieval.>

## Solution

<Step-by-step fix. Include exact commands, config, or code.>

## Verification

<How to confirm the fix worked>

## Notes

<Optional: edge cases, related issues, when NOT to use this>
```

---

## Step 4: Install the Skill

Write the file and install it to both Codex and Claude command directories:

```bash
SLUG="<slug>"
FILE_PATH="$HOME/.codex/commands/${SLUG}.md"

# Write the skill file (use the content from Step 3)
# Then install to Claude commands if present
if [ -d "$HOME/.claude/commands" ]; then
  cp "$FILE_PATH" "$HOME/.claude/commands/${SLUG}.md"
  echo "Installed to ~/.claude/commands/${SLUG}.md"
fi

echo "Installed to ~/.codex/commands/${SLUG}.md"
echo ""
echo "The skill will auto-load in future sessions when trigger conditions match."
echo "To add it to CrossCheck: cp ~/.codex/commands/${SLUG}.md ~/Documents/Developer/CrossCheck/skill-sources/"
```

If `--dry-run` was passed, print the full file content and the install commands but do not
write any files.

---

## Quality Signals

**Good skills:**
- Describe a specific error name, library, or environment (not "a bug")
- Could be handed to another developer as a runbook
- The trigger conditions would uniquely identify when this is relevant
- The solution is exact and reproducible

**Bad skills (don't extract these):**
- "Use the correct API parameter" — too obvious
- "Check the docs" — not a discovery
- One-time workaround for a misconfigured local environment
- Something that only applies to one specific file in one specific project

---

## Examples of Good Skill Names and Descriptions

```yaml
name: nextjs-server-component-errors-not-in-browser
description: |
  Fix for Next.js server component errors that appear in terminal but not browser DevTools.
  Use when: errors visible in Next.js dev server output but browser console is silent,
  client-side debugging yields nothing, error stack trace mentions 'RSC' or 'server action'.
```

```yaml
name: zsh-path-not-inherited-by-launchd
description: |
  Fix for CLI tools available in terminal but not found when run by launchd services or
  GUI apps on macOS. Symptoms: 'command not found' in logs despite tool being installed,
  works in zsh but fails in cron/launchd, PATH differs between `env` and shell.
```

