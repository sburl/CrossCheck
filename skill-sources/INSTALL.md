# Installing Codex Skills

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-11-23-15-54

This directory contains legacy flat Markdown command sources. Codex-native
skills live under `codex/skills/` and install as
`~/.codex/skills/<name>/SKILL.md`.

Use the Codex-native skills for Codex and the Claude mirror for Claude Code.

## Installation

### On a new computer:

```bash
# 1. Clone the CrossCheck repo to ~/.crosscheck
git clone https://github.com/sburl/CrossCheck.git ~/.crosscheck

# 2. Install Codex-native skills and Claude commands
mkdir -p ~/.codex/skills ~/.claude/commands
cp -R ~/.crosscheck/codex/skills/* ~/.codex/skills/
cp ~/.crosscheck/claude/skill-sources/*.md ~/.claude/commands/

# 3. Verify installation
find ~/.codex/skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l
```

### Quick install script:

```bash
# Run this one-liner (native Codex skills plus Claude commands):
mkdir -p ~/.codex/skills ~/.claude/commands && \
  cp -R ~/.crosscheck/codex/skills/* ~/.codex/skills/ && \
  cp ~/.crosscheck/claude/skill-sources/*.md ~/.claude/commands/
```

## Available Skills (34 total)

### PR Workflow (9)
- `/submit-pr` - Automated PR submission with checks
- `/pre-pr-check` - Comprehensive pre-PR checklist (runs tests, linting, timestamps)
- `/techdebt` - Find and eliminate technical debt (runs automated checks)
- `/security-review` - Comprehensive security audit (dependencies, secrets, permissions)
- `/bug-review` - Systematic failure mode audit (AI patterns, concurrency, memory, etc.)
- `/redteam` - Active exploit verification (writes throwaway exploit tests)
- `/fuzz` - Property-based and adversarial input testing
- `/mutation-test` - Mutation testing for test suite quality
- `/webapp-test` - Automated Playwright-based web app testing (screenshot, interact, visual regression)

### Agent Delegation (5)
- `/codex-delegate` - Delegate task to Codex agent
- `/gemini-delegate` - Delegate task to Gemini agent
- `/ensemble-opinion` - Get multi-model opinions (Codex + Gemini + Critic)
- `/pr-review` - Initiate autonomous PR review with Codex
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

### Repo Operations (2)
- `/drain-repo` - Drain review-approved PRs via integration-branch process (acorn|firehose|thriftfit|switchyard)
- `/triage-repo` - Autonomous Linear intake triage and queue allocation for a target repo (acorn|firehose|thriftfit|switchyard)

### Knowledge Capture (1)
- `/capture-skill` - Distill session discoveries into reusable skills (auto-installs to Claude + Codex)

### Analytics (1)
- `/ai-usage` - Track token usage, costs, and environmental impact across Claude/Codex/Gemini

### Setup (4)
- `/setup-automation` - Install all automation for new repo
- `/setup-plugins` - Install Claude Code plugins alongside CrossCheck
- `/setup-statusline` - Customize Codex statusline
- `/garbage-collect` - Manage /garbage folder

### CrossCheck Maintenance (2)
- `/napkin` - Read and update per-repo behavioral memory
- `/update-crosscheck` - Pull the latest CrossCheck workflow and sync installed skills and agents

## Opting Out of Skills

Don't want a specific skill? Add its name to `~/.crosscheck/skip-skills` (one per line):

```bash
# Create skip list
mkdir -p ~/.crosscheck
echo "ai-usage" >> ~/.crosscheck/skip-skills

# Remove an existing native Codex install
rm -rf ~/.codex/skills/ai-usage
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
# Copy changes back to repo (use ~/.claude/commands/ as the source of truth)
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
├── commands/              ← Active skills for Claude Code
│   └── *.md              ← 34 skill files

~/.codex/
├── commands/              ← Active skills for Codex
│   └── *.md              ← 34 skill files
└── settings.json         ← Global permissions

~/.crosscheck/                 ← Git repo (source of truth, traditional install)
├── skill-sources/         ← Source for skills (not scanned by Codex)
├── CODEX.md             ← Workflow rules
└── CODEX-PROMPTS.md      ← Codex templates
```

**Why multiple locations?**
- `~/.crosscheck/skill-sources/` - Version controlled source (traditional install)
- `~/Documents/Developer/CrossCheck/skill-sources/` - Version controlled source (multi-project install)
- `~/.claude/commands/` - Active skills Claude Code loads
- `~/.codex/skills/<name>/SKILL.md` - Active native skills Codex loads

The repo is the source of truth. Copy Codex skills from `codex/skills/` to
`~/.codex/skills/`; install Claude commands from `claude/skill-sources/` to
`~/.claude/commands/`.

**Important:** The CrossCheck repo must NOT be inside `~/.codex/`. Codex scans
`~/.codex/` for commands, which would cause duplicate skill registrations.
