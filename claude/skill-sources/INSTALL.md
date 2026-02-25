# Installing Claude Skills

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-25-00-00

This directory contains all custom skill sources for Claude.

**Note:** This folder is named `skill-sources/` (not `commands/`) so that Claude doesn't load these as project-level commands when working inside the CrossCheck repo. The bootstrap script copies them to `~/.claude/commands/` where Claude picks them up globally.

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

## Available Skills (28 total)

### PR Workflow (5)
- `/submit-pr` - Automated PR submission with checks
- `/pre-pr-check` - Comprehensive pre-PR checklist (runs tests, linting, timestamps)
- `/techdebt` - Find and eliminate technical debt (runs automated checks)
- `/security-review` - Comprehensive security audit (dependencies, secrets, permissions)
- `/bug-review` - Systematic failure mode audit (AI patterns, concurrency, memory, etc.)

### Agent Delegation (5)
- `/claude-delegate` - Delegate task to Claude agent
- `/gemini-delegate` - Delegate task to Gemini agent
- `/ensemble-opinion` - Get multi-model opinions (Claude + Gemini + Critic)
- `/pr-review` - Initiate autonomous PR review with Claude
- `/repo-assessment` - Run comprehensive repo assessment (every 3 PRs)

### Git Cleanup (6)
- `/create-worktree` - Create new git worktree for parallel development
- `/list-worktrees` - List all active git worktrees
- `/cleanup-worktrees` - Remove merged/abandoned worktrees
- `/cleanup-branches` - Batch git branch cleanup script
- `/cleanup-stashes` - Review and selectively drop stashes (orphaned, superseded, stale)
- `/cleanup-all` - Full cleanup sequence: worktrees → branches → stashes

### Development (4)
- `/plan` - Enter plan mode for complex tasks
- `/do-work` - Process autonomous task queue from do-work/ folder
- `/commit-smart` - Atomic Git Commit
- `/doc-timestamp` - Add/update timestamps in docs

### Memory (2)
- `/napkin` - Per-repo behavioral memory in `.claude/napkin.md` (corrections, gotchas)
- `/capture-skill` - Extract a non-obvious discovery from this session as a reusable skill

### Analytics (1)
- `/ai-usage` - Track token usage, costs, and environmental impact across Claude/Codex/Gemini

### Setup (5)
- `/setup-automation` - Install all automation for new repo
- `/setup-plugins` - Install Claude Code plugins alongside CrossCheck
- `/setup-statusline` - Customize Claude statusline
- `/garbage-collect` - Manage /garbage folder
- `/update-crosscheck` - Update CrossCheck to the latest version

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
│   └── *.md              ← 28 skill files
└── settings.json         ← Global permissions

~/.crosscheck/                 ← Git repo (source of truth, traditional install)
├── skill-sources/         ← Source for skills (not scanned by Claude)
├── CLAUDE.md             ← Workflow rules
└── CLAUDE-PROMPTS.md      ← Claude templates
```

**Why two locations?**
- `~/.crosscheck/skill-sources/` - Version controlled source (traditional install)
- `~/Documents/Developer/CrossCheck/skill-sources/` - Version controlled source (multi-project install)
- `~/.claude/commands/` - Active skills Claude loads

The repo is the source of truth. Copy to `~/.claude/commands/` to activate.

**Important:** The CrossCheck repo must NOT be inside `~/.claude/`. Claude scans
`~/.claude/` for commands, which would cause duplicate skill registrations.
