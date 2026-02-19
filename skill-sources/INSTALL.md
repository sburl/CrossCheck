# Installing Claude Code Skills

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-19-00-00

This directory contains all custom skill sources for Claude Code.

**Note:** This folder is named `skill-sources/` (not `commands/`) so that Claude Code doesn't load these as project-level commands when working inside the CrossCheck repo. The bootstrap script copies them to `~/.claude/commands/` where Claude Code picks them up globally.

## Installation

### On a new computer:

```bash
# 1. Clone the CrossCheck repo to ~/.crosscheck
git clone https://github.com/sburl/CrossCheck.git ~/.crosscheck

# 2. Copy skills to ~/.claude/commands/
mkdir -p ~/.claude/commands
cp ~/.crosscheck/skill-sources/*.md ~/.claude/commands/

# 3. Verify installation
ls ~/.claude/commands/
```

### Quick install script:

```bash
# Run this one-liner:
mkdir -p ~/.claude/commands && cp ~/.crosscheck/skill-sources/*.md ~/.claude/commands/
```

## Available Skills (22 total)

### PR Workflow (5)
- `/submit-pr` - Automated PR submission with checks
- `/pre-pr-check` - Comprehensive pre-PR checklist (runs tests, linting, timestamps)
- `/techdebt` - Find and eliminate technical debt (runs automated checks)
- `/security-review` - Comprehensive security audit (dependencies, secrets, permissions)
- `/bug-review` - Systematic failure mode audit (AI patterns, concurrency, memory, etc.)

### Agent Delegation (5)
- `/codex-delegate` - Delegate task to Codex agent
- `/gemini-delegate` - Delegate task to Gemini agent
- `/ensemble-opinion` - Get multi-model opinions (Claude + Gemini + Codex)
- `/pr-review` - Initiate autonomous PR review with Codex
- `/repo-assessment` - Run comprehensive repo assessment (every 3 PRs)

### Git Worktrees (4)
- `/create-worktree` - Create new git worktree for parallel development
- `/list-worktrees` - List all active git worktrees
- `/cleanup-worktrees` - Remove merged/abandoned worktrees
- `/cleanup-branches` - Batch git branch cleanup script

### Development (4)
- `/plan` - Enter plan mode for complex tasks
- `/do-work` - Process autonomous task queue from do-work/ folder
- `/commit-smart` - Atomic Git Commit
- `/doc-timestamp` - Add/update timestamps in docs

### Analytics (1)
- `/ai-usage` - Track token usage, costs, and environmental impact across Claude/Codex/Gemini

### Setup (3)
- `/setup-automation` - Install all automation for new repo
- `/setup-statusline` - Customize Claude Code statusline
- `/garbage-collect` - Manage /garbage folder

## Opting Out of Skills

Don't want a specific skill? Add its name to `~/.crosscheck/skip-skills` (one per line):

```bash
# Create skip list
echo "ai-usage" >> ~/.crosscheck/skip-skills

# Remove it locally if already installed
rm ~/.claude/commands/ai-usage.md
```

The bootstrap script will skip any skills listed in this file. Lines starting with `#` are ignored.

## TokenPrint (powers /ai-usage)

The `/ai-usage` skill is powered by [TokenPrint](https://github.com/sburl/TokenPrint), which is cloned by the bootstrap script by default. If you skipped it during bootstrap, `/ai-usage` won't work until you install it.

**Install later:**
```bash
git clone https://github.com/sburl/TokenPrint.git ~/.tokenprint
```

**Update:**
```bash
cd ~/.tokenprint && git pull
```

**Remove:**
```bash
rm -rf ~/.tokenprint   # or ~/Documents/Developer/TokenPrint for multi-project mode
```

Without TokenPrint installed, `/ai-usage` will prompt you to install it.

## Maintenance

To update skills from this computer to the repo:

```bash
# Copy changes back to repo
cp ~/.claude/commands/*.md ~/Documents/Developer/CrossCheck/skill-sources/

# Commit and push
cd ~/Documents/Developer/CrossCheck
git add skill-sources/
git commit -m "docs: update skills"
git push
```

## Architecture

```
~/.claude/
├── commands/              ← Active skills (copied from CrossCheck/skill-sources/)
│   └── *.md              ← 21 skill files
└── settings.json         ← Global permissions

~/.crosscheck/                 ← Git repo (source of truth, traditional install)
├── skill-sources/         ← Source for skills (not scanned by Claude Code)
├── CLAUDE.md             ← Workflow rules
└── CODEX-PROMPTS.md      ← Codex templates
```

**Why two locations?**
- `~/.crosscheck/skill-sources/` - Version controlled source (traditional install)
- `~/Documents/Developer/CrossCheck/skill-sources/` - Version controlled source (multi-project install)
- `~/.claude/commands/` - Active skills Claude Code loads

The repo is the source of truth. Copy to `~/.claude/commands/` to activate.

**Important:** The CrossCheck repo must NOT be inside `~/.claude/`. Claude Code scans
`~/.claude/` for commands, which would cause duplicate skill registrations.
