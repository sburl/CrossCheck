---
name: investigate
description: |
  Systematic debugging with root cause investigation. Four phases: investigate, analyze,
  hypothesize, implement. Iron Law: no fixes without root cause. 3-strike escalation.
  Use when: "debug this", "fix this bug", "why is this broken", "investigate this error",
  "root cause analysis", "this stopped working".
  Proactively suggest when the user reports errors, unexpected behavior, or is
  troubleshooting why something stopped working.
---

**Created:** 2026-03-20-00-00
**Last Updated:** 2026-03-20-00-00

*Inspired by [gstack investigate](https://github.com/garrytan/gstack) — adapted for CrossCheck.*

# Investigate — Systematic Root Cause Debugging

Find the root cause before writing a fix. No guessing. No shotgun debugging.

## Usage

```bash
/investigate                         # Start investigating current issue
/investigate tests are failing       # Start with symptom description
/investigate --scope src/auth/       # Restrict edits to a directory
```

---

## The Iron Law

**No fixes without root cause.** Do not patch symptoms. Do not guess. Do not apply
Stack Overflow fixes without understanding why they work.

If you cannot identify the root cause after Phase 2, escalate. Bad fixes are worse
than no fixes.

## The 3-Strike Rule

After 3 failed fix attempts, STOP and escalate to the user. Do not keep trying.

```
STATUS: BLOCKED
REASON: [1-2 sentences]
ATTEMPTED: [what you tried, 3 items]
RECOMMENDATION: [what the user should do next]
```

---

## Scope Lock

If `--scope <dir>` is provided, or if the user specifies a directory to focus on:

**Only edit files within the specified directory.** This prevents the classic agent failure
of "fixing" unrelated code while debugging. Read anything, but write only within scope.

If no scope is specified, ask the user:

> "Which part of the codebase is this bug likely in? I'll restrict my edits to that area
> to avoid accidentally changing unrelated code."

If the user says "anywhere" or declines to scope, proceed without restriction but
prefer minimal, targeted edits.

---

## Phase 1: Investigate — Reproduce and Observe

**Goal:** See the bug happen. Collect raw evidence.

1. **Reproduce the bug.** Run the failing command, test, or flow. Capture the exact error.
   If you cannot reproduce, ask the user for reproduction steps.

2. **Read the error carefully.** The error message, stack trace, and line numbers are evidence.
   Do not skip them.

3. **Map the data flow.** Starting from the error location, trace backwards:
   - What function called this?
   - What data did it receive?
   - Where did that data come from?

4. **Check recent changes.** Run `git log --oneline -10` and `git diff HEAD~3` to see
   what changed recently. The bug often lives in the diff.

5. **Check logs.** Look for relevant log output, error logs, or diagnostic information.

**Output:** A factual summary of what you observed. No theories yet.

```
INVESTIGATION:
  Symptom: [what the user reported]
  Reproduced: [yes/no + exact command/steps]
  Error: [exact error message]
  Location: [file:line where error occurs]
  Data flow: [A calls B calls C, C receives X but expects Y]
  Recent changes: [relevant commits or none]
```

---

## Phase 2: Analyze — Form Hypotheses

**Goal:** Generate ranked hypotheses about root cause.

Based on the evidence from Phase 1, form 2-4 hypotheses:

```
HYPOTHESES (ranked by likelihood):
  H1: [most likely cause] — Evidence: [what supports this]
  H2: [second most likely] — Evidence: [what supports this]
  H3: [less likely but possible] — Evidence: [what supports this]
```

For each hypothesis, identify what evidence would confirm or eliminate it.

**Do not skip this step.** Writing hypotheses forces clear thinking. Jumping straight
to fixes is how you waste hours.

---

## Phase 3: Hypothesize — Test and Confirm

**Goal:** Confirm or eliminate the top hypothesis.

1. **Test H1 first.** Add a targeted diagnostic (log statement, assertion, print) to
   confirm whether H1 is the cause. Run the failing case again.

2. **If H1 confirmed:** Move to Phase 4.

3. **If H1 eliminated:** Update evidence, test H2. Repeat.

4. **If all hypotheses eliminated:** Return to Phase 1 with new information. Generate
   new hypotheses.

**Key rules:**
- One hypothesis at a time. Do not test multiple simultaneously.
- Each test should be disposable — a log line or assertion, not a code change.
- Remove diagnostics after confirming. They are tools, not fixes.

---

## Phase 4: Implement — Fix the Confirmed Root Cause

**Goal:** Write a minimal, targeted fix for the confirmed root cause.

1. **Fix only the root cause.** Do not refactor surrounding code. Do not improve
   error handling elsewhere. Do not clean up nearby code.

2. **Verify the fix.** Run the original failing case. It must pass.

3. **Check for regressions.** Run the full test suite (or relevant subset). Nothing
   else should break.

4. **Write a regression test** (if one doesn't exist) that fails without the fix and
   passes with it.

5. **Remove any diagnostic code** added during investigation.

---

## Completion Status

Report using one of:

- **FIXED** — Root cause identified and fixed. Include:
  ```
  ROOT CAUSE: [1-2 sentences]
  FIX: [what was changed]
  VERIFIED: [test command and result]
  REGRESSION TEST: [added/existed/skipped with reason]
  ```

- **BLOCKED** — Cannot identify root cause or fix keeps failing. Include:
  ```
  STATUS: BLOCKED
  SYMPTOM: [what's happening]
  INVESTIGATED: [what was checked]
  HYPOTHESES TESTED: [H1: eliminated because..., H2: ...]
  ATTEMPTED FIXES: [up to 3]
  RECOMMENDATION: [what the user should try]
  ```

- **NEEDS_CONTEXT** — Missing information to proceed. State exactly what's needed.

---

## Anti-Patterns (DO NOT DO)

- **Shotgun debugging** — changing multiple things at once to "see what sticks"
- **Cargo cult fixes** — copying a fix from Stack Overflow without understanding why it works
- **Scope creep** — "while I'm here, let me also fix this unrelated thing"
- **Symptom patching** — wrapping the error in a try/catch instead of fixing the cause
- **Infinite loops** — trying the same fix with minor variations. After 3 attempts, stop.

---

## Rules

- **Iron Law: no fixes without root cause.** No exceptions.
- **3-strike rule:** 3 failed fixes → stop and escalate.
- **Scope lock:** Respect the `--scope` boundary. Read anything, edit only within scope.
- **Minimal changes:** Fix the bug, nothing more.
- **Credit:** Adapted from [gstack investigate](https://github.com/garrytan/gstack) by Garry Tan.
