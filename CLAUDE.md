# Claude Code Workflow (Global)

**Created:** 2026-01-30-16-27
**Last Updated:** 2026-03-20-00-00

*This file is managed by CrossCheck. Do not edit directly — changes will be overwritten
on the next `/update-crosscheck`. Put personal overrides in `CLAUDE.local.md` instead.*

---

## Session Start

**If `.claude/napkin.md` exists in the current repo, read it before doing anything else.**
Apply it silently — don't announce it, just let it inform your behavior. See `/napkin`.

**Update check (silent, run once per session):**
```bash
_CC_DIR="$HOME/Documents/Developer/CrossCheck"; [ -d "$_CC_DIR/.git" ] && _CC_BEHIND=$(git -C "$_CC_DIR" rev-list HEAD..origin/main --count 2>/dev/null) && [ "${_CC_BEHIND:-0}" -gt 0 ] && echo "CrossCheck: $_CC_BEHIND update(s) available — run /update-crosscheck" || true
```
If updates are available, mention it once. Don't nag.

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
- `/plan` - Enter plan mode for complex tasks (`--scope` for scope review, `--arch` for architecture review)
- `/think` - Problem framing before code (startup/builder modes, design doc output)
- `/investigate` - Systematic debugging (root cause first, 3-strike escalation)
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
