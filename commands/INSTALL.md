# Installing Claude Code Skills

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-10-00-00

This directory contains all custom skills for Claude Code.

## Installation

### On a new computer:

```bash
# 1. Clone the CrossCheck repo to ~/.claude/CrossCheck
cd ~/.claude
git clone https://github.com/sburl/CrossCheck.git CrossCheck

# 2. Copy commands to ~/.claude/commands/
mkdir -p ~/.claude/commands
cp ~/.claude/CrossCheck/commands/*.md ~/.claude/commands/

# 3. Verify installation
ls ~/.claude/commands/
```

### Quick install script:

```bash
# Run this one-liner:
mkdir -p ~/.claude/commands && cp ~/.claude/CrossCheck/commands/*.md ~/.claude/commands/
```

## Available Skills (21 total)

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

### Setup (3)
- `/setup-automation` - Install all automation for new repo
- `/setup-statusline` - Customize Claude Code statusline
- `/garbage-collect` - Manage /garbage folder

## Maintenance

To update skills from this computer to the repo:

```bash
# Copy changes back to repo
cp ~/.claude/commands/*.md ~/Documents/Developer/CrossCheck/commands/

# Commit and push
cd ~/Documents/Developer/CrossCheck
git add commands/
git commit -m "docs: update skills"
git push
```

## Architecture

```
~/.claude/
├── commands/              ← Active skills (copied from CrossCheck/commands/)
│   └── *.md              ← 21 skill files
├── CrossCheck/               ← Git repo (source of truth)
│   ├── commands/         ← Source for skills
│   ├── CLAUDE.md        ← Workflow rules
│   └── CODEX-PROMPTS.md ← Codex templates
└── settings.json         ← Global permissions
```

**Why two locations?**
- `~/.claude/CrossCheck/commands/` - Version controlled source (git repo)
- `~/.claude/commands/` - Active skills Claude Code loads

The repo is the source of truth. Copy to `~/.claude/commands/` to activate.
