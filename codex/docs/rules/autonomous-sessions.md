**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-11-00-00

# Autonomous & Long-Running Sessions

## Autonomous Sessions (30+ min)

**Pre-flight (before any code execution):**

```bash
# Verify imports resolve
python -c "import module_name"
pip list | grep module_name

# Verify dependencies installed
npm ls --depth=0 | grep missing

# Only THEN run tests
```

**Every 15min:** Update TODO.md (session scratchpad) with status, done, next, blockers. Task backlog lives in `do-work/` folder -- see `/do-work` skill.

**If blocked >10min:**

1. Document blocker in TODO.md (scratchpad)
2. Try different approach
3. Move to different task
4. NEVER spin on same error >3 attempts

## Codex Review Autonomy

**Core Principle:** Codex works autonomously. Don't interrupt unless non-responsive.

**Monitoring:**

- Every 5min: Heartbeat check-in
- Every 30min: Update user on progress
- Every 60min: Check if should continue

**What counts as "stuck":**

- No response to 2+ heartbeats (10+ min silent)
- Same command loop 50+ times
- Error messages repeating without progress

**What does NOT count as "stuck":**

- Taking 10-30 minutes (thorough reviews take time)
- Running many file inspections
- Generating detailed analysis

**Trust Codex autonomy. Don't impose arbitrary timeouts.**

See @CODEX-PROMPTS.md for complete Codex integration details.
