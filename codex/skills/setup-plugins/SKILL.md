---
name: setup-plugins
description: Install and configure Codex plugins alongside CrossCheck skills
---

**Created:** 2026-02-25-00-00
**Last Updated:** 2026-02-25-00-00

# Setup Plugins for Codex Workflow

Install Codex plugins from Anthropic marketplaces, with opinionated recommendations that complement CrossCheck skills.

## EXECUTION INSTRUCTIONS FOR CODEX

When this skill is invoked, do the following:

### Step 1: Check Marketplace Registration

```bash
# Check if marketplaces are already registered
codex plugin list 2>/dev/null | head -5
```

If the `plugin` subcommand isn't available or no marketplaces are registered:

```bash
# Register the two Anthropic marketplaces
codex plugin add-marketplace https://marketplace.anthropic.com/plugins
codex plugin add-marketplace https://marketplace.anthropic.com/community-plugins
```

If registration fails, tell the user their Codex version may not support plugins yet and stop.

### Step 2: Detect Project Stack

Examine the current repo to determine what languages and frameworks are in use:

```bash
# Check for language indicators
ls package.json tsconfig.json pyproject.toml setup.py Cargo.toml go.mod *.sln *.csproj Gemfile build.gradle pom.xml Package.swift Makefile composer.json 2>/dev/null

# Check for frontend indicators
ls -d src/components src/pages src/app public static templates 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react|vue|svelte|angular|next|nuxt|astro"' | head -5
```

Build a list of detected languages and whether the project has a frontend.

### Step 3: Present Tiered Recommendations

Show the user the following tiers. Pre-check recommendations based on detected stack.

**Tell the user:**

```
Plugin recommendations for this project:

TIER 1 — Always Recommended:
  [x] security-guidance    — Passive security warnings on every file edit
  [x] hookify              — Create custom hooks from conversation patterns
  [x] playground           — Interactive HTML playgrounds
  [x] code-simplifier      — Code clarity refinement

TIER 2 — Frontend (only if frontend detected):
  [x/skip] frontend-design — Bold UI aesthetics, avoids generic AI look

TIER 3 — Complementary to CrossCheck (overlap notes):
  [x] code-review          — Multi-agent review scoring (complements /pr-review)
  [x] pr-review-toolkit    — Dimensional reviewers (complements /pr-review)

TIER 4 — Language-Specific LSP (auto-detected):
  [x/skip per language] typescript-lsp, pyright-lsp, gopls-lsp, etc.

TIER 5 — Situational (ask user):
  [ ] codex-setup               — Onboarding helpers
  [ ] codex-md-management       — CODEX.md management
  [ ] explanatory-output-style  — Verbose explanations
  [ ] learning-output-style     — Teaching mode
  [ ] ralph-wiggum / ralph-loop — Fun persona
  [ ] plugin-dev                — Build your own plugins
  [ ] skill-creator             — Create skills (overlaps /capture-skill)

TIER 6 — Skip (CrossCheck supersedes):
  [skip] commit-commands         — Superseded by /commit-smart
  [skip] feature-dev             — Superseded by /plan
  [skip] agent-sdk-dev           — Niche, install manually if needed
```

For Tier 4 LSP plugins, auto-select based on detected languages:

| Language | Plugin |
|----------|--------|
| TypeScript/JavaScript | `typescript-lsp` |
| Python | `pyright-lsp` |
| Go | `gopls-lsp` |
| Rust | `rust-analyzer-lsp` |
| Swift | `swift-lsp` |
| Kotlin | `kotlin-lsp` |
| C/C++ | `clangd-lsp` |
| C# | `csharp-lsp` |
| Java | `jdtls-lsp` |
| Lua | `lua-lsp` |
| PHP | `php-lsp` |

Ask the user: "Install recommended plugins? You can deselect any tier or individual plugin."

### Step 4: Install User-Selected Plugins

For each selected plugin:

```bash
codex plugin install <plugin-name>
```

Install them one at a time. If any fail, note the failure and continue with the rest.

### Step 5: Verify and Post-Install Summary

```bash
# List installed plugins
codex plugin list
```

**Tell the user:**

```
Plugin setup complete!

Installed: [list installed plugins]
Skipped:   [list skipped plugins with reasons]
Failed:    [list any failures]

IMPORTANT: Restart Codex for plugins to take effect:
  1. Exit: exit
  2. Restart: codex

Manage plugins anytime:
  codex plugin list          — See installed plugins
  codex plugin install <name> — Add a plugin
  codex plugin remove <name>  — Remove a plugin
  /setup-plugins              — Re-run this skill
```

---

## CrossCheck Skill vs Plugin Overlap Matrix

| CrossCheck Skill | Plugin | Relationship | Recommendation |
|-----------------|--------|--------------|----------------|
| `/security-review` | `security-guidance` | **Complementary** — skill is on-demand audit, plugin is passive warnings | Install both |
| `/pr-review` | `code-review` | **Complementary** — skill delegates to Codex, plugin adds multi-agent scoring | Install both |
| `/pr-review` | `pr-review-toolkit` | **Complementary** — skill delegates to Codex, plugin adds dimensional reviewers | Install both |
| `/commit-smart` | `commit-commands` | **Conflicting** — both control commit messages, will fight | Skip plugin |
| `/plan` | `feature-dev` | **Conflicting** — both try to orchestrate feature development | Skip plugin |
| `/capture-skill` | `skill-creator` | **Overlapping** — similar purpose, choose one | User preference |
| (none) | `hookify` | **Unique** — no CrossCheck equivalent | Install |
| (none) | `playground` | **Unique** — interactive HTML sandboxes | Install |
| (none) | `code-simplifier` | **Unique** — code clarity refinement | Install |
| (none) | `frontend-design` | **Unique** — UI aesthetics | Install if frontend |

---

## Plugins vs Skills: Why Both?

**Plugins** are passive enhancers. They auto-load into every session, adding capabilities silently (LSP intelligence, security warnings, design guidance). You don't invoke them — they just work.

**Skills** are explicit workflow orchestrators. They encode multi-step, opinionated workflows (`/submit-pr` chains techdebt + pre-check + PR creation + review). You invoke them deliberately for a specific job.

They complement each other:
- `security-guidance` plugin warns passively on every edit; `/security-review` skill runs a comprehensive on-demand audit
- `code-review` plugin adds scoring to inline reviews; `/pr-review` skill orchestrates the full Codex review handoff
- LSP plugins provide real-time intelligence; skills provide workflow automation

**Rule of thumb:** If it should happen automatically in every session, it's a plugin. If it's a deliberate workflow step, it's a skill.

---

## Managing Plugins

```bash
# List installed plugins
codex plugin list

# Install a specific plugin
codex plugin install <plugin-name>

# Remove a plugin
codex plugin remove <plugin-name>

# List available marketplaces
codex plugin list-marketplaces

# Re-run this skill for guided setup
/setup-plugins
```
