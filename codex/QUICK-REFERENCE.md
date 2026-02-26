# CrossCheck Quick Reference

**Created:** 2026-02-09-16-28
**Last Updated:** 2026-02-26-00-00

Complete reference tables for daily workflow.

---

## Skill-First Protocol

When user requests these tasks, invoke the corresponding skill:

| User Request | Skill to Invoke | Why Mandatory |
|-------------|-----------------|---------------|
| "create pr", "submit pr", "open pr" | `/submit-pr` | Complete workflow: techdebt → pre-check → PR → Codex review |
| "commit", "save changes" | `/commit-smart` | Good commit messages, reviews changes |
| Complex task (>3 files) | `/plan` | Design before implementation |
| "have Codex do X" | `/codex-delegate` | Proper context injection |
| "have Gemini do X" | `/gemini-delegate` | Proper context injection |
| "get opinions", "ask other models" | `/ensemble-opinion` | Multi-model perspectives |
| "review", "Codex review" | `/pr-review` | Standard Codex review handoff |
| Every 3 PRs | `/repo-assessment` | Comprehensive Codex assessment |
| "security review" | `/security-review` | Full security audit (deps, secrets, perms) |
| "red team", "exploit" | `/redteam` | Active exploit verification of security findings |
| "fuzz", "adversarial input" | `/fuzz` | Property-based and adversarial input testing |
| "mutation test", "test quality" | `/mutation-test` | Verify test suite catches real bugs |
| "parallel work", "worktree" | `/create-worktree` | Proper worktree setup |
| "show worktrees" | `/list-worktrees` | List active worktrees |
| "cleanup worktrees" | `/cleanup-worktrees` | Remove merged worktrees |
| "delete branches" | `/cleanup-branches` | Safe batch deletion |
| Modified .md file | `/doc-timestamp` | Update timestamps |
| "setup automation" | `/setup-automation` | Install hooks + CI |
| "customize statusline" | `/setup-statusline` | Configure status bar |
| "do the work", "process tasks" | `/do-work` | Process task queue from do-work/ folder |
| "cleanup garbage" | `/garbage-collect` | Review /garbage folder |
| "usage", "tokens", "how much AI", "spending" | `/ai-usage` | Token usage, cost, and impact dashboard |
| "test webapp", "browser test", "screenshot" | `/webapp-test` | Automated Playwright-based web app testing |
| "setup plugins", "install plugins" | `/setup-plugins` | Opinionated plugin selection with CrossCheck overlap awareness |

---

## Workflow Quick Reference

| Situation | Action |
|-----------|--------|
| **New feature** | INVOKE `/plan` if complex (>3 files) |
| **Start work** | `git checkout -b feat-name` (NEVER on main) |
| **Writing code** | Tests ALONGSIDE, every function |
| **Just wrote code** | Run tests IMMEDIATELY before continuing |
| **Code "looks right"** | Don't trust - verify with tests |
| **Claim "X works"** | Show passing test results as proof |
| **Bug fix** | (1) Test reproduces (2) Verify fails (3) Fix (4) Pass (5) Commit |
| **User corrects** | Add specific rule to CODEX.md NOW |
| **Unfamiliar tech** | ASK before "fixing" (post-Jan 2025?) |
| **Post-cutoff working code** | Don't change - add `# WARNING: post-cutoff - VALID` |
| **User wants commit** | INVOKE `/commit-smart` (NEVER git commit directly) |
| **User wants PR** | INVOKE `/submit-pr` (auto-runs techdebt + pre-check) |
| **Submit PR** | `/submit-pr` handles everything (no manual steps) |
| **CI pass** | Merge on GitHub (not locally) |
| **CI fail** | Fix on feature branch, push, wait again |
| **After merge** | `git checkout main && git pull` |
| **Codex review** | Auto loop - fix issues autonomously |
| **Stuck 10+ rounds** | Ask user for input |
| **Every 3 PRs** | INVOKE `/repo-assessment` → refactor PR |
| **Delegate to Codex** | INVOKE `/codex-delegate` with context |
| **Delegate to Gemini** | INVOKE `/gemini-delegate` with context |
| **Multiple AI opinions** | INVOKE `/ensemble-opinion` |
| **Parallel work needed** | INVOKE `/create-worktree` |
| **Autonomous 30+ min** | Pre-flight checks + TODO.md scratchpad every 15min |
| **Blocker >10min** | Document in TODO.md scratchpad, try alternative |
| **Copy-paste from UI** | Find CLI/API first (`vercel`, `stripe`, etc) |
| **Code execution** | Explain first, repo only |
| **Commits** | Via `/commit-smart` only |
| **Commit to main** | Via GitHub PR only |
| **Commit history** | Keep on main forever. Feature branches: default keep, cleanup only if noise (typos/"wip") + alone on branch |
| **Modified .md file** | INVOKE `/doc-timestamp` to update timestamps |
| **Tests fail 3x** | Submit PR with note explaining |
| **Context <10%** | `/compact` (between issues) |
| **Context <40%** | `/compact` (switching branches) |
| **Delete files** | `mv file garbage/` (rm blocked) then `/garbage-collect` |

---

## Git Workflow Patterns

### Starting Feature

```bash
# Create feature branch
git checkout -b feat/user-authentication

# Work freely (no review friction)
git commit -m "feat: add login form"
git commit -m "feat: add validation"
git commit -m "test: add auth tests"
```

### Submitting PR

```bash
# Let skills handle it
/submit-pr

# Or manually (not recommended):
git push -u origin feat/user-authentication
gh pr create
```

### After PR Merged

```bash
# Return to main
git checkout main
git pull

# Feature branch auto-deleted by post-merge hook
# Remote branch auto-deleted by GitHub (if enabled)
```

### Parallel Work (Worktrees)

```bash
# Create worktree for parallel work
/create-worktree hotfix main

# Or manually:
git worktree add ../CrossCheck-hotfix main

# Work in separate directory
cd ../CrossCheck-hotfix
# Independent working tree, same .git
```

---

## Common Patterns

### Test-Driven Development

```python
# 1. Write test first
def test_authenticate_user():
    user = User("test@example.com", "password123")
    assert authenticate(user) == True

# 2. Run test (should fail)
pytest test_auth.py::test_authenticate_user
# ❌ FAIL: authenticate not defined

# 3. Write minimal code
def authenticate(user):
    return user.password == "password123"

# 4. Run test (should pass)
pytest test_auth.py::test_authenticate_user
# ✅ PASS

# 5. Refactor if needed
# 6. Commit both test + code together
/commit-smart
```

### Bug Fix Pattern

```bash
# 1. Write test that reproduces bug
git commit -m "test: reproduce auth bug"

# 2. Verify test fails
pytest test_auth.py
# ❌ FAIL: Expected True, got False

# 3. Fix the bug
git commit -m "fix: correct password validation"

# 4. Verify test passes
pytest test_auth.py
# ✅ PASS

# 5. Submit PR
/submit-pr
```

### Context Management

```bash
# When context feels full or between tasks:
/compact

# Start fresh if needed:
exit  # Ctrl+D
codex  # New session
```

---

## File Operation Patterns

### Safe File Deletion

```bash
# NEVER use rm (blocked)
# ❌ rm old-file.js

# Instead, move to garbage
mv old-file.js garbage/

# Periodically review garbage
/garbage-collect

# Garbage folder reviewed, can delete confirmed files
```

### Documentation Updates

```bash
# After editing .md file
/doc-timestamp

# Updates "Last Updated:" field automatically
# Pre-push hook verifies timestamps on modified docs
```

---

## Skills Reference

### PR Workflow

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/submit-pr` | User wants PR | Runs techdebt + pre-check + creates PR + starts Codex review |
| `/pre-pr-check` | Before PR (auto-invoked) | Runs tests, linting, checks timestamps, verifies branch |
| `/techdebt` | Before PR (auto-invoked) | Finds silenced errors, debug code, TODO comments |

### Agent Delegation

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/codex-delegate` | User says "have Codex X" | Injects CODEX.md context, runs Codex autonomously |
| `/gemini-delegate` | User says "have Gemini X" | Injects CODEX.md context, runs Gemini autonomously |
| `/ensemble-opinion` | Need multiple AI opinions | Gets opinions from Codex + Claude + Gemini |
| `/pr-review` | Manual PR review needed | Standard Codex review handoff workflow |
| `/repo-assessment` | Every 3 PRs | Comprehensive Codex analysis of repo state |
| `/security-review` | Every 3 PRs (waterfall) or on demand | Dependency audit, secrets scan, trust model check |
| `/bug-review` | On demand or before major release | AI code patterns, concurrency, memory leaks, error handling |
| `/redteam` | After `/security-review` or standalone | Active exploit verification (writes throwaway exploit tests) |
| `/fuzz` | On demand for specific modules | Property-based and adversarial input testing |
| `/mutation-test` | On demand to verify test quality | Mutation testing — checks if tests catch real bugs |
| `/webapp-test` | Test running web app | Playwright-based screenshot, interaction, and visual regression testing |

### Git Operations

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/create-worktree` | Need parallel work | Creates git worktree for simultaneous sessions |
| `/list-worktrees` | Check active worktrees | Shows all worktrees with status |
| `/cleanup-worktrees` | Remove old worktrees | Deletes merged/abandoned worktrees |
| `/cleanup-branches` | Delete old branches | Generates batch script for safe branch deletion |
| `/commit-smart` | User wants commit | Creates good commit message, reviews changes |

### Development

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/plan` | Complex task (>3 files) | Enters plan mode, designs before implementation |
| `/do-work` | Process task queue | Reads do-work/ folder, executes tasks autonomously |
| `/doc-timestamp` | Modified .md file | Updates "Last Updated:" timestamp |

### Analytics

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/ai-usage` | Track AI token usage and costs | Dashboard: daily/cumulative tokens, costs, energy, CO2 across Claude/Codex/Gemini |

### Setup

| Skill | When to Use | What It Does |
|-------|-------------|--------------|
| `/setup-automation` | New repo setup | Installs git hooks + GitHub Actions |
| `/setup-statusline` | Customize status bar | Configures Claude Code statusline |
| `/setup-plugins` | Install Claude Code plugins | Registers marketplaces, recommends plugins by tier, detects stack, warns about overlaps |
| `/garbage-collect` | Review deleted files | Shows garbage/ folder contents for cleanup |

---

## Pre-Commit Hook Checks

Runs on every commit:

```bash
✓ Secrets detection (API keys, tokens)
✓ Debug code check (console.log, debugger, pdb)
✓ Doc timestamp verification
✓ Test coverage check (if applicable)
```

Blocked commits:
- API keys or secrets detected
- Modifying files in `user-content/` (human-only zone)

Warnings (non-blocking):
- Missing timestamps on modified .md files
- Debug statements (console.log, debugger, pdb)

---

## Pre-Push Hook Checks

Runs before **every push** (all branches):

```bash
✓ Doc timestamp metadata present (Last Updated field exists)
✓ Development markers checked (TODO, FIXME)
✓ Merge conflict markers checked
✓ Security checks (secrets scan, dependency audit)
```

**Main/master only** (skipped on feature branches):
```bash
✓ Pre-PR quality checks (/techdebt + /pre-pr-check)
```

Blocked pushes:
- Missing timestamp metadata on any .md file (no `Last Updated` field)
- Merge conflict markers present
- Pushing to main without running /techdebt and /pre-pr-check

Feature branches skip pre-PR quality checks for fast iteration.

---

## GitHub Protection Rules

Server-side enforcement:

```bash
✓ PR required (no direct commits to main)
✓ Linear history (squash merge only)
✓ External approval (can't self-approve)
✓ Status checks (CI must pass)
✓ Force-push blocked
✓ Branch deletion blocked
```

These cannot be bypassed - enforced by GitHub regardless of local hooks.

---

## Related Documentation

- **[CODEX.md](CODEX.md)** - Core workflow (condensed version)
- **[README.md](README.md)** - Project overview
- **[README.md](README.md#detailed-setup)** - Setup guide
- **[ADVANCED.md](../ADVANCED.md)** - Customization and multi-agent workflows
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - When things break
