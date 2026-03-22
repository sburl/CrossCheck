# Claude Code Workflow (Global)

**Created:** 2026-01-30-16-27
**Last Updated:** 2026-02-24-12-53

*This file is managed by CrossCheck. Do not edit directly — changes will be overwritten
on the next `/update-crosscheck`. Put personal overrides in `CLAUDE.local.md` instead.*

---

## Session Start

**If `.claude/napkin.md` exists in the current repo, read it before doing anything else.**
Apply it silently — don't announce it, just let it inform your behavior. See `/napkin`.

---

## Quick Principles

1. **Autonomous First** - Fix it yourself → try Codex → try alternatives → escalate to user
2. **Zero Trust** - Test everything. Nothing works until proven.
3. **Feature Branches** - NEVER work on main. Branch → PR → merge.
4. **Test-First** - Write tests ALONGSIDE code, not after.
5. **Skill-First** - Use skills for common workflows (see CrossCheck/QUICK-REFERENCE.md)
6. **Clean Up After Yourself** - Delete worktrees, temp branches, and scratch directories when done.
7. **Hard Cutover** - Never implement backward compatibility. Make the breaking change directly.
8. **Exec, Don't Instruct** - When told to involve Codex/Gemini/Claude, run the tool yourself. NEVER tell the user to run another agent manually or give CLI commands to copy-paste.
9. **Merge Gating** - NEVER merge without review approval. Run `/pr-review` first. No exceptions.
10. **Test-Fix Loops** - When tests fail, fix and re-run up to 5x before escalating. Don't stop after one attempt.
11. **Intent Check for Sprawling Work** - Before multi-file refactors, new automation, or recurring-process work, answer: `why am i working on this?`, `what outcome would make this a win?`, `what would make me stop?`

---

## Detailed Workflow

- **Primary workflow:** `CrossCheck/codex/CODEX.md`
- **Skills reference:** `CrossCheck/QUICK-REFERENCE.md`
- **Rules:** `CrossCheck/docs/rules/` (trust-model.md, git-history.md, autonomous-sessions.md, memory.md)

---

## Common Skills

Always available via `~/.claude/commands/` (source: `CrossCheck/skill-sources/`):

- `/submit-pr` - Full PR workflow (techdebt → pre-check → create PR → review)
- `/commit-smart` - Good commit messages
- `/codex-delegate` - Delegate to Codex with full context
- `/plan` - Enter plan mode for complex tasks
- `/create-worktree` - Parallel development
- `/napkin` - Per-repo behavioral memory in `.claude/napkin.md`

See `CrossCheck/QUICK-REFERENCE.md` for all skills.

---

## Project-Specific Overrides

Each project can have its own `CLAUDE.md` with project-specific instructions.
These supplement (not replace) this global workflow.

---

## Quick Reference

| Situation | Action |
|-----------|--------|
| **Detailed workflow** | Read `CrossCheck/codex/CODEX.md` |
| **Skill details** | Read `CrossCheck/QUICK-REFERENCE.md` |
| **Trust model** | Read `CrossCheck/docs/rules/trust-model.md` |
| **Git history rules** | Read `CrossCheck/docs/rules/git-history.md` |
| **Memory curation** | Read `CrossCheck/docs/rules/memory.md` |
| **Need a skill** | Invoke from CrossCheck skills |
| **Project-specific** | Check current project's CLAUDE.md (if exists) |
