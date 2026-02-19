# CrossCheck - AI-Reviewed Code, Human-Level Quality

**Created:** 2026-01-30-16-27
**Last Updated:** 2026-02-19-00-00

**Build autonomous loops. Ship production-quality software.**

**[Read the blog post](https://spencerburleigh.com/blog/2026/02/13/crosscheck/)** | Claude Code writes. Codex reviews. Hooks enforce. You orchestrate.

---

## The Idea

**The problem:** AI coding without structure is entropy. Code works but conventions drift, tests thin out, architecture rots. AI is excellent at the big picture and terrible at the last mile.

**The solution:** Build autonomous loops with structural enforcement.

```
Define task → Agent builds on branch → Hooks enforce quality
    ↑                                        ↓
    └── Review PR ← Codex reviews ← Tests verify
```

**An autonomous loop** is a cycle where the agent works, the system validates, and the output improves -- without human intervention at each step. You define the loop and review the output. Everything in between is automated.

The key insight: **git hooks make compliance the path of least resistance.** The agent doesn't need to "remember" your conventions. The hooks enforce them structurally. Zero trust, not zero hope.

---

## The Swiss Cheese Model of Accident Causation

This is the same principle that made aviation the safest form of transport. Every safety layer has holes. No single layer is perfect. But stack enough layers with *uncorrelated* holes and the probability of a failure passing through all of them drops to near zero.

```
  Settings Deny List    Git Hooks        Tests         Codex Review    Branch Protection
  ┌──────────────┐   ┌──────────────┐  ┌──────────┐  ┌──────────────┐  ┌──────────────┐
  │   ██  █      │   │ █   ██       │  │    █  █  │  │ █      ██   │  │      █      █│
  │      █       │ → │       █      │→ │ ██      █│→ │    █        │→ │  ██         █│
  │  █       ██  │   │  ██      █   │  │      ██  │  │      █   █  │  │        █    █│
  └──────────────┘   └──────────────┘  └──────────┘  └──────────────┘  └──────────────┘
  Blocks rm, sudo,    Secrets scan,     Code must     Different model   Separate identity
  hard-reset, .env    conventional      pass tests    reviews with      must approve.
  reads at the        commits, content  before PR.    different blind   Can't self-merge.
  permission level.   protection.                     spots.
```

Each layer is a different *type* of check:
- **Settings deny list** -- Permission-level blocks the agent can't override
- **Git hooks** -- Structural enforcement at commit/push/merge boundaries
- **Tests** -- Behavioral verification of correctness
- **Multi-model review** -- Independent assessment by a model from a different lab
- **Branch protection** -- Identity-based server-side enforcement

The holes in each layer are *uncorrelated* because they use different mechanisms. A bug that slips past tests won't necessarily slip past Codex review. A secret that bypasses a hook won't bypass the settings deny list. **The agent can't bypass any layer.**

---

## Layered Enforcement

```
┌─────────────────┐
│ Git Hooks       │ Zero-trust gates at every commit, push, merge
├─────────────────┤
│ Quality Checks  │ /security-review (10 threat categories)
│                 │ /bug-review (10 failure mode categories)
├─────────────────┤
│ Multi-Model     │ Claude writes, Codex reviews, different blind spots
├─────────────────┤
│ GitHub Rules    │ Separate-identity approval, squash-only, CODEOWNERS
└─────────────────┘
```

**6 git hooks catch issues before they reach GitHub:**

| Hook | When | Catches |
|------|------|---------|
| **pre-commit** | Before commit | Secrets, debug code, timestamps |
| **commit-msg** | After message | Enforces conventional commits |
| **post-commit** | After commit | Logs for Codex review |
| **post-checkout** | Branch switch | Kills orphan processes |
| **pre-push** | Before every push | Timestamps, markers, conflicts (+ /techdebt + /pre-pr-check on main) |
| **post-merge** | After merge | Auto-deletes local branch |

---

## Why Codex?

**I've tested multiple reviewers. Codex is more precise.**

But here's the key: **Use an agent from a different lab than your developer agent.**

```
Claude (Anthropic) writes → Codex (OpenAI) reviews
└─ Different training → Different blind spots → Better coverage
```

Each AI has blind spots. When those blind spots come from different training data and architectures, they're less correlated. One agent's weakness is another's strength. This is another application of the swiss cheese model -- and why multi-agent review catches more than single-agent development.

---

## The Autonomous Loop

**1. Plan** - Design the approach (automatic for complex tasks)
**2. Build** - Agent writes code + tests on a feature branch, committing early and often
**3. Verify** - Hooks catch secrets, enforce format, run tests. Failures block progress.
**4. Review** - A different model reviews. Agent addresses feedback. Repeat until approved.
**5. Ship** - PR merge with separate-identity approval. Branch auto-deleted.
**6. Improve** - Periodic self-assessment identifies gaps. System gets better over time.

**Feature branches = freedom.** No review friction during development.
**Main branch = fortress.** Hooks + branch protection + identity separation protect production.

---

## Core Principles

**1. Autonomous by Default** - The agent solves its own problems. Escalate only after exhausting alternatives.

**2. Zero Trust** - Test everything. Nothing works until proven. Hooks enforce, not remind.

**3. Autonomous Loops** - Every workflow is a loop: build -> validate -> review -> improve. Structural enforcement at every step.

**4. Feature Branches = Freedom, Main = Fortress** - All work on branches. Main requires separate-identity PR approval. Agent can't commit to main.

**5. Multi-Model Review** - Claude writes, Codex reviews. Different training = different blind spots = better coverage.

**6. Self-Improving** - Every 3 PRs: repo assessment -> bug review -> security review waterfall. The system audits itself.

---

## Results

**Before CrossCheck:**
- You write, you review, you fix, you ship → **You're the bottleneck**

**After CrossCheck:**
- Claude writes → Codex reviews → Claude fixes → Auto-validation → **Ship with confidence**

**The difference:**
- Secrets caught before commit
- Tests written alongside code (not after)
- Codex reviews in minutes (not days)
- You orchestrate, AIs execute

---

## Quick Start

**Prerequisites:**
- [Claude Code CLI](https://code.claude.com)
- Codex access (for reviews)
- Git + GitHub CLI (`gh`)

**Installation (5 minutes):**

CrossCheck is designed to manage **multiple projects** from a single installation. Install it once alongside your projects, then enable it per-project.

### 1. Clone CrossCheck Alongside Your Projects

```bash
# Navigate to your projects folder
cd ~/Documents/Developer  # Or wherever you keep projects

# Clone CrossCheck at the same level as your other projects
git clone https://github.com/sburl/CrossCheck.git

# Your structure should look like:
# ~/Documents/Developer/
#   ├── CrossCheck/        (workflow repository)
#   ├── MyApp/            (your project)
#   ├── MyOtherApp/       (another project)
#   └── ...
```

### 2. Run Bootstrap Script

```bash
cd CrossCheck
./scripts/bootstrap-crosscheck.sh
```

This installs:
- Skills to `~/.claude/commands/` (available in all projects)
- Global `CLAUDE.md` in your projects folder (full workflow)
- Claude Code settings with proper permissions
- [TokenPrint](https://github.com/sburl/TokenPrint) for the `/ai-usage` dashboard (prompted, can skip)

### 3. Enable CrossCheck for Your Project(s)

```bash
# Go to any project where you want the workflow
cd ../MyApp

# Install git hooks (use relative path from CrossCheck)
../CrossCheck/scripts/install-git-hooks.sh
```

### 4. Start Building

```bash
claude "Build user authentication"
# Claude creates feature branch, writes code + tests, gets Codex review, ships
```

**That's it!** All 22 skills are now available in every project. The full workflow is available globally, with supporting docs in CrossCheck/.

---

## Detailed Setup

### Multi-Project Installation Model

CrossCheck uses a **single source of truth** pattern:

```
~/Documents/Developer/          # Your projects folder
├── CLAUDE.md                  # Full workflow (copied from CrossCheck)
│
├── CrossCheck/                # 🎯 Source repository
│   ├── CLAUDE.md             # Source of truth for workflow
│   ├── QUICK-REFERENCE.md    # Supporting reference (22 skills, tables)
│   ├── docs/rules/           # Supporting docs (trust-model, git-history)
│   ├── skill-sources/        # 22 skills (copied to ~/.claude/commands/)
│   └── scripts/              # Installation scripts
│
└── YourProject/              # Your projects
    ├── CLAUDE.md (optional)  # Project-specific overrides
    └── .git/hooks/           # Installed per-project
```

**Key insight:** Global CLAUDE.md = full workflow. Supporting docs (QUICK-REFERENCE.md, rules/) stay in CrossCheck. Skills install globally (`~/.claude/commands/`), hooks install per-project.

### GitHub Branch Protection Setup

#### Option A: Import Ruleset (Recommended - 2 minutes)

1. Go to your repo -> **Settings** -> **Rules** -> **Rulesets**
2. Click **"Import a ruleset"**
3. Upload: `.github/rulesets/protect-main.json` from this repo
4. Click **"Create"**
5. Go to **Settings** -> **General** -> **Pull Requests**
6. Enable **"Automatically delete head branches"**

Verify it works:

```bash
~/.crosscheck/scripts/validate-github-protection.sh
```

#### Option B: Manual Setup (10 minutes)

1. Go to your repo -> **Settings** -> **Rules** -> **Rulesets**
2. Click **"New ruleset"** -> **"New branch ruleset"**
3. Name: **`protect-main`**
4. Enforcement: **Active**
5. Target: **Default branch**

**Add these rules:**
- **Restrict deletions**
- **Require linear history**
- **Require pull request before merging**
  - Required approvals: **1**
  - Dismiss stale approvals when new commits pushed
  - Require approval of most recent push
  - Require conversation resolution
  - Allowed merge methods: **Squash only**
- **Block force pushes**

**Important:** Do NOT configure any "Bypass list" -- rules must apply to everyone.

6. Click **"Create ruleset"**
7. Go to **Settings** -> **General** -> **Pull Requests**
8. Enable **"Automatically delete head branches"**

### Verify Installation

#### Test 1: Hooks Work

```bash
cd ~/your-project

# Test conventional commits enforcement
git commit -m "bad commit message"
# Should fail: "must follow conventional commits format"

git commit -m "docs: good commit message"
# Should pass

# Test secrets detection
echo 'API_KEY="sk_live_1234567890"' >> test.txt
git add test.txt && git commit -m "test: add secret"
# Should fail: "Possible secret detected"

git reset HEAD test.txt && rm test.txt
```

#### Test 2: Skills Work

```bash
# Check skills installed
ls ~/.claude/commands/ | wc -l
# Should show: 23 (22 skills + INSTALL.md)

# Start Claude Code
claude

# Try a skill
User: "Plan a new feature"
# Claude should invoke /plan skill
```

#### Test 3: Pre-Push Check Works

```bash
# Try pushing to main without pre-checks
git checkout main
git push
# Should block with message:
# "BLOCKED: Pre-push quality checks required"
# "Run: /techdebt && /pre-pr-check"
```

---

## Requirements

- **[Claude Code CLI](https://code.claude.com)** -- The development agent
- **Codex access** -- The review agent (or another model from a different lab)
- **Git + GitHub CLI** (`gh`)
- **[TokenPrint](https://github.com/sburl/TokenPrint)** -- AI usage dashboard (installed by bootstrap, optional)

The core idea is two AI models from different labs: one writes, one reviews. This repo ships with Claude + Codex, but the architecture works with any pair. Different training data = different blind spots = better coverage.

---

## Next Steps / What We're Thinking About

**Persistent memory:** CLAUDE.md is static -- it doesn't know what the agent did last session, what's blocked, or what patterns have been learned. The missing piece is dynamic state that persists across sessions: task graphs, dependency tracking, learned patterns. Something like [Beads](https://github.com/steveyegge/beads) for dependency-aware task graphs, or a lightweight session log the agent can query on startup.

**Multi-channel agents:** [OpenClaw](https://openclaw.ai) as a gateway layer -- message tasks from your phone, agent works in a worktree, sends PR notification when done.

**Third model at merge gate:** Currently Claude writes and Codex reviews, but merge-to-main only has branch protection. Adding a third model (Gemini, Kimi, or another lab) as a final reviewer at the merge step would add another uncorrelated layer to the swiss cheese model -- a completely independent assessment of the full changeset before it hits production. The open question: does a third model add meaningful coverage, or are we into diminishing returns?

**Safer CLI access:** CLIs (Railway, Vercel, `gh`, databases) are what keep loops autonomous -- the agent deploys without a human clicking a dashboard. But giving agents CLI access to production infrastructure is an unsolved trust problem. There's no granular permission layer between "full access" and "no access." Scoped tokens, dry-run defaults, approval gates for destructive operations. Necessary for truly autonomous deployment loops.

**Agent permissions:** Finer-grained control over which parts of the repo different agents can touch during parallel development. Right now worktrees provide isolation at the branch level, but within a worktree the agent has access to everything. Per-agent read/write boundaries on directories or files would reduce blast radius.

**UI iteration loop:** The one autonomous loop we haven't cracked. Backend has clear loops (write -> test -> verify). UI needs visual evaluation -- does this component look right? Is the layout balanced? Screenshot-based feedback exists but AI's visual judgment is unreliable. This limits current applications to CLIs and simple landing pages. This is the frontier.

**Read the full story:** [spencerburleigh.com/blog/crosscheck](https://spencerburleigh.com/blog/crosscheck)

---

## Documentation

**Core workflow:**
- **[CLAUDE.md](CLAUDE.md)** - What Claude reads (workflow reference)
- **[QUICK-REFERENCE.md](QUICK-REFERENCE.md)** - Complete command tables
- **[CODEX-PROMPTS.md](CODEX-PROMPTS.md)** - How to invoke Codex

**When things break:**
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Debug hooks, CI, permissions
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md#hook-error-reference)** - Hook-specific debugging

**Deep dives:**
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design, data flow
- **[ADVANCED.md](ADVANCED.md)** - Customization, multi-agent workflows
- **[The Full Story](https://spencerburleigh.com/blog/crosscheck)** - Philosophy and story behind CrossCheck

---

## Contributing

Found a better workflow? Submit a PR. This improves through community feedback.

Both humans and AI agents can contribute.

**For CrossCheck developers:** Install hooks in your local CrossCheck repo to eat your own dog food:

```bash
cd ~/path/to/CrossCheck
./scripts/install-git-hooks.sh
```

---

**Links:**
- [GitHub](https://github.com/sburl/CrossCheck)
- [Issues](https://github.com/sburl/CrossCheck/issues)
- [Discussions](https://github.com/sburl/CrossCheck/discussions)

**License:** MIT
