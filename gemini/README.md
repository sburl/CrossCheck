# CrossCheck - Gemini CLI Workflow

**Created:** 2026-03-01-00-00
**Last Updated:** 2026-03-01-00-00

**Build autonomous loops. Ship production-quality software with Gemini.**

Gemini writes. Peer model reviews. Hooks enforce. You orchestrate.

---

## The Idea

**The problem:** AI coding without structure is entropy. Code works but conventions drift, tests thin out, architecture rots.

**The solution:** Build autonomous loops with structural enforcement using the Gemini CLI.

```
Define task → Gemini builds on branch → Hooks enforce quality
    ↑                                        ↓
    └── Review PR ← Gemini reviews ← Tests verify
```

---

## The Swiss Cheese Model for Gemini

```
  Settings Deny List    Git Hooks        Tests         Gemini Review    Branch Protection
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

---

## Why Gemini CLI?

**Gemini CLI (`gemini`) offers unique advantages for autonomous development:**

1. **Massive Context Window:** 1M+ tokens allows for reading entire codebases and complex documentation without losing focus.
2. **Native Tool Integration:** Powerful tools like `codebase_investigator` for deep analysis and `google_web_search` for solving obscure problems.
3. **Structured Execution:** Clear workflows and skill-based expansion.

---

## The Autonomous Loop with Gemini

**1. Plan** - Use `codebase_investigator` to map the architecture and design the approach.
**2. Build** - Gemini writes code + tests on a feature branch, committing early and often.
**3. Verify** - Hooks catch secrets, enforce format, run tests.
**4. Review** - A different model (e.g., Claude or a separate Gemini session) reviews.
**5. Ship** - PR merge with separate-identity approval.
**6. Improve** - Periodic repo assessments to identify gaps.

---

## Quick Start

**Prerequisites:**
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- Gemini API Key
- Git + GitHub CLI (`gh`)

**Installation (5 minutes):**

1. Run the CrossCheck bootstrap script:
```bash
cd CrossCheck
./scripts/bootstrap-crosscheck.sh
```

2. Enable CrossCheck for your project:
```bash
cd ../YourProject
../CrossCheck/scripts/install-git-hooks.sh
```

3. Start Gemini:
```bash
gemini
```

---

## Documentation

- **[GEMINI.md](GEMINI.md)** - Core Gemini CLI workflow instructions.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design for Gemini-centric development.
- **[QUICK-REFERENCE.md](../QUICK-REFERENCE.md)** - Complete command tables.
