# CrossCheck Gemini Quick Reference

**Created:** 2026-03-01-00-00
**Last Updated:** 2026-03-01-00-00

Complete reference tables for daily workflow with Gemini CLI.

---

## Skill-First Protocol (Gemini)

When user requests these tasks, invoke the corresponding skill (subagent):

| User Request | Skill to Invoke | Why Mandatory |
|-------------|-----------------|---------------|
| "create pr", "submit pr", "open pr" | `/submit-pr` | Complete workflow: techdebt → pre-check → PR → Review |
| "commit", "save changes" | `/commit-smart` | Good commit messages, reviews changes |
| Complex task (>3 files) | `/plan` | Design before implementation |
| "have Claude do X" | `/claude-delegate` | Proper context injection |
| "have Gemini do X" | `/gemini-delegate` | Proper context injection |
| "get opinions", "ask other models" | `/ensemble-opinion` | Multi-model perspectives |
| "review", "Gemini review" | `/pr-review` | Standard review handoff |
| Every 3 PRs | `/repo-assessment` | Comprehensive assessment |
| "security review" | `/security-review` | Full security audit (deps, secrets, perms) |
| "red team", "exploit" | `/redteam` | Active exploit verification of security findings |
| "parallel work", "worktree" | `/create-worktree` | Proper worktree setup |
| "show worktrees" | `/list-worktrees` | List active worktrees |
| "cleanup worktrees" | `/cleanup-worktrees` | Remove merged worktrees |
| Modified .md file | `/doc-timestamp` | Update timestamps |
| "setup automation" | `/setup-automation` | Install hooks + CI |
| "do the work", "process tasks" | `/do-work` | Process task queue from do-work/ folder |
| "cleanup garbage" | `/garbage-collect` | Review /garbage folder |
| "usage", "tokens", "spending" | `/ai-usage` | Token usage, cost, and impact dashboard |

---

## Gemini Native Tools

| Tool | When to Use |
|------|-------------|
| `codebase_investigator` | Deep research, architectural mapping, cross-file analysis |
| `google_web_search` | Finding documentation, solving obscure library issues |
| `web_fetch` | Analyzing content from specific URLs |
| `cli_help` | Questions about Gemini CLI configuration or features |

---

## Workflow Quick Reference

| Situation | Action |
|-----------|--------|
| **New feature** | INVOKE `/plan` if complex (>3 files) |
| **Start work** | `git checkout -b feat-name` (NEVER on main) |
| **Writing code** | Tests ALONGSIDE, every function |
| **Just wrote code** | Run tests IMMEDIATELY before continuing |
| **Bug fix** | (1) Test reproduces (2) Verify fails (3) Fix (4) Pass (5) Commit |
| **User wants commit** | INVOKE `/commit-smart` (NEVER git commit directly) |
| **User wants PR** | INVOKE `/submit-pr` (auto-runs techdebt + pre-check) |
| **CI pass** | Merge on GitHub (not locally) |
| **After merge** | `git checkout main && git pull` |
| **Gemini review** | Auto loop - fix issues autonomously |
| **Every 3 PRs** | INVOKE `/repo-assessment` → refactor PR |
| **Delegate to Gemini** | INVOKE `/gemini-delegate` with context |
| **Parallel work needed** | INVOKE `/create-worktree` |
| **Delete files** | `mv file garbage/` then `/garbage-collect` |

---

## Related Documentation

- **[GEMINI.md](GEMINI.md)** - Core Gemini CLI workflow.
- **[README.md](README.md)** - Gemini integration overview.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Gemini-centric system design.
