# Codex Workflow

**Created:** 2026-01-30-16-27
**Last Updated:** 2026-02-24-01-31

---

## Core Philosophy: Autonomous by Default

**You are a self-reliant agent. Solve your own problems. The user reviews output, not process.**

The user decides *what* to build and reviews PRs. You do *everything else*. Don't ask permission for things the workflow covers. Don't narrate your process.

**Slow is smooth, smooth is fast.** AI coding has high variance -- you can write a lot of code very fast. That means the error rate must be suppressed aggressively. Make every commit atomic and vetted. Don't let rot accumulate. Brush your teeth every day, not once a month.

**Escalation ladder:**

1. Fix it yourself (try 2x)
2. Ask Codex for a second opinion (`/codex-delegate`)
3. Try a different approach entirely
4. Only escalate to the user after exhausting 1-3

**Ask the user only when:** requirements are ambiguous, architecture has real tradeoffs with no clear winner, or you've exhausted the ladder.

**Everything else -- test failures, merge conflicts, missing deps, Codex feedback, choosing the next task -- handle it yourself.**

## Core Principles

1. **Autonomous First** - Solve problems yourself. Escalate only after trying Codex and alternatives.
2. **Zero Trust** - Test everything. Nothing works until proven.
3. **Progress ≠ Completion** - Describing what you did is not the same as finishing it. Never stop mid-task and summarize as if the goal is met. Completion means tests pass, a PR is merged, or the user explicitly confirmed the goal. If a plan has a checklist, every item must be ticked before stopping.
4. **Feature Branches** - NEVER work on main. All work on branches (or worktrees) then merged via PRs. `git checkout -b feat-name`, commit early and often (every meaningful change), PR to merge. Main requires approval from a separate account (builder != reviewer).
5. **Honest Git** - Feature branches show messy reality. Main gets clean squashed commits via PR.
6. **Test-First** - Write tests ALONGSIDE code, not after.
7. **Codex as Partner** - Codex reviews and approves. Don't ask it to write code.
8. **Skill-First** - ALWAYS use skills for common workflows.

---

## Skills (27)

If a skill exists for what you're doing, use it. Skills save context and ensure correctness.

**PR & Quality:**
`/submit-pr` (full PR workflow) | `/pre-pr-check` (checklist) | `/techdebt` (find debt) | `/commit-smart` (good messages) | `/security-review` (security audit) | `/bug-review` (failure mode audit)

**Agent Delegation:**
`/codex-delegate` (Codex review) | `/gemini-delegate` (Gemini) | `/ensemble-opinion` (multi-model) | `/pr-review` (Codex PR review) | `/repo-assessment` (every 3 PRs)

**Development:**
`/plan` (design first, >3 files) | `/do-work` (process task queue) | `/doc-timestamp` (update timestamps)

**Git:**
`/create-worktree` | `/list-worktrees` | `/cleanup-worktrees` | `/cleanup-branches`

**Setup:**
`/setup-automation` | `/setup-statusline` | `/garbage-collect`

**Memory:**
`/napkin` (per-repo behavioral corrections in `.claude/napkin.md`)

**Details on each:** @QUICK-REFERENCE.md

---

## Autonomous Behavior

**Default: Act. Don't ask.**

You have skills, hooks, Codex, tests, and this file. The user set up this system so they don't have to micromanage you.

**You do NOT need the user for:**

- Test failures (fix them)
- Merge conflicts (resolve them)
- Missing dependencies (install them)
- Code review feedback from Codex (address it)
- "Should I follow the workflow?" (yes, always)
- Progress updates mid-task (save it for the summary)
- Permission to use a skill (just use it)
- Progression to the next item in the task queue

**Task queue (`do-work/` folder):**

- After merging a PR: check `do-work/` for next task
- Session starts with no specific task: pick up from `do-work/`
- Autonomous sessions: process the queue continuously
- Nothing to do: tell the user once, then stop

**CLIs over dashboards.** If a service has a CLI (`gh`, `railway`, `vercel`, `sqlite3`, `psql`, `redis-cli`), use it. A loop breaks the moment you hand off to a user to click a web UI. Configure CLIs once, interact programmatically. The settings template already allows these.

**Communication:** Report outcomes, not process. Batch updates at milestones. If blocked on the user, say what you need and move to the next task.

---

## Protect Your Context Window

**The main context window is precious. Protect it.**

Every file read, every test dump, every long exploration burns tokens. The main agent stays focused and delegates everything else.

**Delegate to subagents (7 available in `agents/`):**

- **Exploration/research** - Spawn a subagent to investigate, get a summary back
- **Critical review** - `codex_critic` (risks, blind spots, alternatives)
- **Test writing** - `test-writer-fixer` (comprehensive test suites, TDD)
- **UI work** - `ui-designer` (design systems, components) | `whimsy-injector` (UX delight)
- **Prototyping** - `rapid-prototyper` (fast MVPs, 6-day cycles)
- **Tool decisions** - `tool-evaluator` (tech stack comparison)
- **Planning** - `coach` (strategic coordination, agent orchestration)
- **Debugging** - Codex via `/codex-delegate`

**Main window is for:** orchestration, small focused tasks, reviewing subagent output, communicating with the user.

**Hygiene:** Don't read entire large files (use targeted reads). Don't dump full test output (summarize). Spawn subagents for exploration. `/compact` at <10% context between issues, <40% when switching branches.

---

## Parallel Development

**Worktrees are the #1 productivity multiplier.** Run 3-5 Codex sessions simultaneously, each on its own feature branch in its own directory.

```bash
/create-worktree feature-auth     # Creates ../worktrees/repo-feature-auth/
/create-worktree feature-ui       # Each gets own branch + CODEX.md
/create-worktree bugfix-login     # Open separate terminal, cd there, run codex
```

Each worktree is fully autonomous: own branch, own context, own PR counter. No conflicts between sessions. Submit multiple PRs per day. The main worktree coordinates; satellite worktrees execute.

**Manage:** `/list-worktrees` to see all | `/cleanup-worktrees` to remove merged ones

**IMPORTANT: Clean up when done.** After a worktree's PR is merged, delete the worktree directory and its branch immediately. Don't leave stale worktrees, temp directories, or scratch copies cluttering the Developer folder. Run `/cleanup-worktrees` at the end of every session that used worktrees.

---

## Reference

**Session start:** if `.claude/napkin.md` exists in the current repo, read it before doing anything else. Apply it silently.

**On-demand rules (hooks auto-remind, but read proactively when relevant):**
- **Freedom on branches, main locked down** `docs/rules/trust-model.md` (trust boundaries, zero-trust, two-account model)
- **Rebasing/squashing history:** `docs/rules/git-history.md` (what to keep vs clean)
- **Long sessions or Codex review:** `docs/rules/autonomous-sessions.md` (15-min updates, blocked protocol)
- **Memory curation:** `docs/rules/memory.md` (10-item cap, MEMORY.md vs napkin)

**Assessment waterfall (every 3 PRs):** `/repo-assessment` -> `/bug-review` -> `/security-review`. Run in order. Fix findings from each before starting the next. Triggered by post-merge hook. Lightweight secret + dependency scan on every push.

**File operations:** Delete via `garbage/` folder, then `/garbage-collect`. Never modify `user-content/` (human-only zone, hook-protected).

**PRs:** Small > large | Split if >3 files | Cohesive changes | Different areas = different PRs

**Dangerous commands blocked** in `settings.template.json`: `rm`, `git reset --hard`, `--no-verify`, `sudo`, `docker`, `eval`, reading `.env`/`.pem`/`.key` files. This is the settings.json deny list -- it's a hard guardrail the agent cannot override. Rebase and force-push are allowed (feature branches need them); GitHub branch protection blocks force-push to main server-side.

**Gotchas:** `~/.codex/settings.json` is global | CODEX.md is per-repo | Check `which tool` before using CLI tools
