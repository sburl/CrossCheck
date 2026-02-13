**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-12-12-00

# Git History

## Honest Git History

**On main/master (NEVER touch):**

- NEVER rebase, squash, amend, force-push, reset --hard
- Keep complete, honest history forever

**On feature branches (pragmatic cleanup OK):**

- **Default: Keep messy commits** (shows real work)
- **CAN clean up IF:** alone on branch AND truly just noise
- **When updating from main:** prefer `git merge main` over rebase
- **ALLOWED:** `branch -d` for cleanup (use `/cleanup-branches`)

**What counts as "noise" (OK to clean):**

- `wip`, `temp`, `debug: added console.log`
- Three commits fixing same syntax error
- Typos in commit messages

**What counts as "learning" (KEEP):**

- `refactor: codex feedback` (shows review iteration)
- `fix: tests failing` (shows TDD process)
- `feat: try approach A` then `feat: switch to approach B`

**Default to keeping history unless genuinely just noise.**

For parallel development with worktrees, see the "Parallel Development" section in CLAUDE.md and the `/create-worktree` skill.
