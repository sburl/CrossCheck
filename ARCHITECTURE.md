# CrossCheck System Architecture

**Created:** 2026-02-09-16-28
**Last Updated:** 2026-02-23-00-00

Deep dive into how the multi-agent development system works.

---

## The 6-Phase Development Cycle

Multi-agent collaboration with continuous quality validation.

*(Simplified view - see CODEX-PROMPTS.md for intermediate review stages)*

```
┌──────────────────────────────────────────────────────────┐
│  Phase 1: PLAN                                           │
│  User + Codex + Coach → Architecture spec               │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  Phase 2: BUILD (Feature Branch)                         │
│  Codex writes code + tests                              │
│  ├─ Commits frequently (no review friction)              │
│  ├─ Git hooks enforce quality (secrets, timestamps)      │
│  └─ Tests written alongside code (not after)             │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  Phase 3: VERIFY                                         │
│  Pre-PR automated checks                                 │
│  ├─ /techdebt - Find technical debt                      │
│  ├─ /pre-pr-check - Comprehensive checklist             │
│  └─ Pre-push hook enforces on main branch               │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────┐
│  Phase 4: REVIEW (Multi-Layer)                           │
│  ┌────────────┐  ┌────────────┐  ┌─────────────┐        │
│  │ CI Tests   │  │ Bot Review │  │ Codex Review│        │
│  │ (automated)│  │ (automated)│  │ (AI agent)  │        │
│  └─────┬──────┘  └─────┬──────┘  └──────┬──────┘        │
│        └────────────────┴────────────────┘               │
│                         │                                 │
│            ┌────────────▼────────────┐                    │
│            │  Codex: Issues Found?   │                    │
│            └─┬───────────────────┬───┘                    │
│              │ YES               │ NO                      │
│              ▼                   ▼                         │
│         Codex Fixes      Codex Approves                  │
│         (loop back)       "LGTM - merge"                  │
└──────────────┬──────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────┐
│  Phase 5: SHIP                                           │
│  Merge to main → Post-merge cleanup                      │
│  ├─ Local branch auto-deleted (remote cleanup manual)    │
│  ├─ CI status checked                                    │
│  └─ Return to roadmap                                    │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ▼ (every 3 PRs)
┌──────────────────────────────────────────────────────────┐
│  Phase 6: IMPROVE                                        │
│  Codex comprehensive repo assessment                     │
│  └─ Find workflow gaps → PR improvements → Better system │
└──────────────────────────────────────────────────────────┘
```

---

## Key Architectural Principles

### 1. Separation of Concerns

```
Codex (Builder) → Writes code, makes decisions, ships features
Codex (Reviewer) → Validates quality, catches bugs, gates merges
Automation (Enforcer) → Prevents mistakes, enforces standards
You (Orchestrator) → Set direction, make strategic decisions
```

**Why this works:**
- Each agent has clear role
- No role confusion
- Parallel work possible
- Quality multiplied through different perspectives

### 2. Continuous Validation

Quality gates at every phase prevent issues from compounding:

| Phase | Validation | Catch Rate |
|-------|------------|------------|
| **BUILD** | Git hooks (secrets, timestamps) | ~60% of issues |
| **VERIFY** | Pre-PR checks (tests, lint, techdebt) | ~25% of issues |
| **REVIEW** | Codex + CI + Bots | ~14% of issues |
| **SHIP** | Final checks, auto-cleanup | ~1% of issues |

**Swiss cheese model:** Each layer catches what previous layers missed.

### 3. Self-Improving System

```
Every 3 PRs → /repo-assessment
              ↓
         Codex analyzes:
         - Workflow friction
         - Recurring issues
         - Missing automation
              ↓
         Suggests improvements
              ↓
         PR to improve CrossCheck
              ↓
         System gets better
```

**Result:** The more you use it, the smarter it gets.

### 4. Multi-Layered Review

Different review types catch different issues:

```
┌─────────────────────────────────────────────────┐
│ CI Tests (Automated)                            │
│ ✓ Syntax errors                                 │
│ ✓ Test failures                                 │
│ ✓ Lint violations                               │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│ Bot Reviews (Automated)                         │
│ ✓ Coverage drops                                │
│ ✓ Large PR warnings                             │
│ ✓ Missing docs                                  │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│ Codex Review (AI Agent)                         │
│ ✓ Logic errors                                  │
│ ✓ Security vulnerabilities                      │
│ ✓ Architecture issues                           │
│ ✓ Edge cases                                    │
└─────────────────────────────────────────────────┘
```

**Why multiple layers?**
- Each catches different classes of bugs
- Redundancy = higher confidence
- Fast checks first, deep review last

---

## Component Interaction

### Git Hooks (Client-Side)

```
Pre-commit → Check secrets, timestamps, debug code
    ↓
Commit-msg → Enforce conventional commits format
    ↓
Post-commit → Track progress, log for Codex review
    ↓
Post-checkout → Kill orphan processes, clean environment
    ↓
Pre-push → Verify pre-PR checks (feature branches skip)
    ↓
Post-merge → Delete local branch, check CI status
```

**Philosophy:** Catch early, fix cheap.

### GitHub Protection (Server-Side)

```
Attempted push to main → GitHub checks:
    ├─ Is it a PR? (direct push blocked)
    ├─ Status checks passing?
    ├─ Required reviews present?
    ├─ From different account? (can't self-approve)
    └─ Linear history maintained?
         ↓
    All pass? → Allow merge
    Any fail? → Block with clear message
```

**Philosophy:** Server enforces what client suggests.

### Skills System

```
User request → Codex pattern matches:
    ├─ "create PR" → /submit-pr
    ├─ "commit" → /commit-smart
    ├─ "have Codex X" → /codex-delegate
    └─ Complex task → /plan
         ↓
    Skill executes:
    ├─ Injects context (CODEX.md)
    ├─ Runs pre-checks
    ├─ Performs workflow
    └─ Reports results
```

**Philosophy:** Don't reinvent workflows, invoke skills.

---

## Data Flow

### Feature Development Flow

```
1. User → Codex: "Add authentication"
         ↓
2. Codex → /plan skill → Architecture spec
         ↓
3. Codex → Creates feature branch
         ↓
4. Codex → Writes code + tests (frequent commits)
         ↓
5. Pre-commit hook → Validates each commit
         ↓
6. Codex → /submit-pr skill
         ↓
7. /submit-pr → Runs /techdebt, /pre-pr-check
         ↓
8. If pass → Creates PR, invokes Codex
         ↓
9. Codex → Reviews PR, provides feedback
         ↓
10. Codex → Fixes issues, pushes updates
         ↓
11. Loop 9-10 until Codex approves
         ↓
12. Codex → "LGTM - merge to main"
         ↓
13. User → Merges on GitHub
         ↓
14. Post-merge hook → Cleanup, return to roadmap
```

### Assessment Flow (Every 3 PRs)

```
Post-merge hook → Increments counter
         ↓
Counter >= 3? → Yes
         ↓
Codex → /repo-assessment
         ↓
Codex → Analyzes last 3 PRs:
    ├─ Common issues
    ├─ Workflow friction
    ├─ Missing automation
    └─ Improvement opportunities
         ↓
Codex → Generates improvement PR
         ↓
User → Reviews, merges improvements
         ↓
CrossCheck → Gets better for next cycle
```

---

## Security Model

### Boundary-Based Trust

```
┌────────────────────────────────────────┐
│ Feature Branches (Permissive)          │
│ ✓ Full agent control                   │
│ ✓ Can rebase, force-push, experiment   │
│ ✓ No approval needed for commits       │
│ ⚠️  Still blocks: rm, sudo, .env reads │
└────────────────────────────────────────┘
                    ↓
         GitHub enforces boundary
                    ↓
┌────────────────────────────────────────┐
│ Main Branch (Strict)                   │
│ 🔒 Separate identity required          │
│ 🔒 PR approval from different account  │
│ 🔒 Can't self-approve                  │
│ 🔒 Linear history only                 │
│ 🔒 No force-push                       │
└────────────────────────────────────────┘
```

**Why this works:**
- Agents work freely during development
- Quality gates apply at merge
- Can't bypass via CLI or web UI (same identity blocked both ways)
- Forces genuine external review

### Agent Self-Policing

Even on permissive feature branches, agents follow safety rules:

```
Before running code:
  → Check imports (warn if os/subprocess/socket)
  → Verify package names (check typosquatting)
  → Explain POST/PUT requests

Before file operations:
  → Repo only (never parent dirs)
  → No .env reads
  → mv to garbage/ instead of rm

Before loops:
  → Python/script loops OK
  → Bash while read loops blocked (infinite loop risk)
```

---

## Scalability

### Horizontal: Multiple Repos

```
~/.codex/
  ├─ commands/ (skills, loaded at startup)
  ├─ settings.json (global, shared)
  └─ git-hooks/ (global, shared)

~/.crosscheck/ (source of truth, traditional install)

Each repo gets:
  ├─ CODEX.md (repo-specific workflow)
  ├─ .github/workflows/ (repo-specific CI)
  └─ Inherits global hooks + settings
```

### Vertical: Team Growth

```
Solo developer:
  ├─ One Codex session
  ├─ Codex reviews via terminal
  └─ Manual merge on GitHub

Small team (2-5):
  ├─ Shared CODEX.md
  ├─ Separate accounts (builder ≠ reviewer)
  └─ Codex reviews via prompt handoff

Larger team (6+):
  ├─ Repo-specific CODEX.md
  ├─ Dedicated reviewer accounts
  ├─ CI + Bots + Codex (multi-layer)
  └─ Scheduled /repo-assessment
```

---

## Performance Characteristics

### Build Phase (Feature Branch)
- **Speed:** Fast (no review friction)
- **Quality:** Basic (git hooks only)
- **Risk:** Low (feature branch isolated)

### Verify Phase (Pre-PR)
- **Speed:** 2-5 minutes (/techdebt + /pre-pr-check)
- **Quality:** High (comprehensive checks)
- **Risk:** Low (blocks before PR if fails)

### Review Phase (Codex)
- **Speed:** 10-30 minutes (thorough analysis)
- **Quality:** Very high (AI review)
- **Risk:** Medium (might miss edge cases)

### Ship Phase (Merge)
- **Speed:** Instant (automated cleanup)
- **Quality:** Very high (passed all gates)
- **Risk:** Very low (multiple validation layers)

---

## Future Architecture

### Planned Enhancements

**1. Multi-Agent PR Review**
```
Codex writes → Commit reviews (Codex)
              ↓
         PR review layer 1 (Codex)
              ↓
         PR review layer 2 (Gemini)
              ↓
         PR review layer 3 (Codex Opus)
              ↓
         Consensus required → Merge
```

**2. Automated Fix Attempts**
```
Codex finds issue → Suggests fix
                  ↓
             Codex attempts fix
                  ↓
             Tests pass? → Auto-commit
                       ↓
             Tests fail? → Ask user
```

**3. Predictive Quality Gates**
```
Analyze past PRs → Identify patterns
                  ↓
             "This PR similar to #42"
                  ↓
             "Watch for X, Y, Z"
                  ↓
             Targeted review focus
```

---

## Inspirations

Projects and ideas that shaped this system:

**[randallb/AAR & Intent Template](https://gist.github.com/randallb/ac0fd027276665c846cf1b13c0218604)**
A military-style After Action Review framework applied to software projects. Introduced the idea of capturing intent at decision time (not hindsight), and separating decision quality from outcome quality. Influenced: the Intent/Success Criteria/Key Assumptions fields in `/plan` output, and the `docs/incidents/` convention for post-incident retrospectives.

**[randallb — Build Less, Ship More: The Three Pillars](https://randallb.com/p/build-less-ship-more-the-three-pillars)**
A full "product command" workflow: collaboratively build an INTENT.md, hand it to the agent for autonomous execution, then run an AAR to improve the intent for next time. Introduced two ideas not in the AAR gist: the 80% threshold (≥80% match to intent → ship; <80% → trash the work, fix the intent, re-run), and "weaknesses in intent" as a distinct AAR section separate from factual assumptions. Influenced: Step 6 (Verify Against Intent) in the `/plan` skill, and the "Weaknesses in Intent" section in `docs/incidents/TEMPLATE.md`.

**[blader/taskmaster](https://github.com/blader/taskmaster)**
A completion enforcement layer for AI coding agents built on the insight that "progress is not completion" — agents have a failure mode where they make partial progress, write a convincing summary, and stop without finishing. Influenced: the "Progress ≠ Completion" principle (#3 in Core Principles in both CODEX.md and CLAUDE.md), and the stop hook that warns about pending do-work tasks and unchecked plan items when a session ends.
