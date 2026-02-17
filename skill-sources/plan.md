---
name: plan
description: Enter plan mode for complex tasks (pour energy into the plan for 1-shot implementation)
---

**Created:** 2026-02-02-12-00
**Last Updated:** 2026-02-11-20-00

# Plan Mode - Design Before Implementation

Enter plan mode to thoroughly design complex tasks before coding.

> "Pour your energy into the plan so Claude can 1-shot the implementation" - Claude Code team

## When to Use Plan Mode

### ✅ Always Use Plan Mode For:

1. **New features** - Any non-trivial functionality
2. **Refactors** - Touching multiple files or changing architecture
3. **Bug fixes** - When root cause is unclear
4. **Performance work** - Optimization requires measurement and strategy
5. **When things go sideways** - "The moment something goes sideways, jump to plan mode"

### ❌ Don't Need Plan Mode For:

1. **Typo fixes** - Single-line obvious changes
2. **Adding logs** - Simple debugging additions
3. **Updating docs** - Straightforward documentation updates
4. **Tiny tweaks** - Small CSS adjustments, config changes

**Rule of thumb:** If you'd normally think "let me plan this first", use plan mode.

## Usage

```bash
/plan [optional: brief description of task]
```

**Examples:**
```bash
/plan                                    # Start planning current task
/plan build authentication system        # Start with task description
/plan refactor payment processing        # Specific refactor
```

## What Happens

### Step 1: Enter Plan Mode

Automatically runs `EnterPlanMode` tool, which:
- Switches Claude to planning mindset
- Enables exploration tools (Read, Glob, Grep)
- Disables code execution tools
- Focuses on understanding and design

### Step 2: Intensive Planning Process

**With User:**
1. Clarify requirements - Ask "obvious" questions
2. Define MVP - What's the minimum viable solution?
3. Identify edge cases - What could go wrong?
4. Design approach - How to implement?
5. Consider alternatives - Other ways to do this?

**With Coach Agent (if complex):**
```bash
# In plan mode, engage coach
# "Coach agent, help me determine MVP for this feature"
```

### Step 3: Create Detailed Plan

**Plan should include:**

1. **Requirements** - What we're building (explicit, verbose)
2. **Approach** - How we'll build it (step-by-step)
3. **Files to change** - Specific files and why
4. **Tests needed** - How we'll verify it works
5. **Edge cases** - What could go wrong
6. **Alternatives considered** - Why we chose this approach

### Step 4: Exit Plan Mode

After creating thorough plan:
```bash
# Plan mode automatically prompts when ready
ExitPlanMode

# Or if using /plan wrapper:
# It handles exit when plan is complete
```

### Step 5: 1-Shot Implementation

With detailed plan:
- Claude implements in one go
- Fewer iterations needed
- Less back-and-forth
- Higher quality first draft

## Example: Building Auth System

### Without Plan Mode ❌

```
User: "Add authentication to the app"
Claude: *starts coding*
Claude: "Created login component, need API endpoint"
User: "Wait, what about OAuth?"
Claude: *refactors*
User: "What about password reset?"
Claude: *adds more*
User: "What about 2FA?"
Claude: *major refactor*

Result: 10 iterations, messy code, missing features
```

### With Plan Mode ✅

```
User: /plan build authentication system

Claude: *enters plan mode*

Claude: "Let me ask some clarifying questions:
1. What auth methods? (email/password, OAuth, magic link?)
2. Need 2FA support?
3. Password reset flow?
4. Session management approach?
5. Existing user table or new?
6. Any compliance requirements (GDPR, etc.)?"

User: *answers questions*

Claude: *explores codebase*
Claude: *designs comprehensive plan*

Claude: "Here's the plan:

## Authentication System Design

### Requirements
- Email/password auth with bcrypt
- OAuth (Google, GitHub)
- 2FA with TOTP
- Password reset via email
- Session tokens (JWT)
- GDPR-compliant user data handling

### Approach
[detailed step-by-step plan]

### Files to Create/Modify
- src/auth/login.ts (new)
- src/auth/oauth.ts (new)
- src/auth/session.ts (modify existing)
- tests/auth.test.ts (new)
[etc.]

### Edge Cases
- Concurrent logins
- Expired tokens
- Invalid OAuth states
[etc.]

Ready to implement?"

User: "Yes, looks good!"

Claude: *exits plan mode*
Claude: *implements entire system in one go*

Result: 1-2 iterations, clean code, complete features
```

## Two-Claude Planning (Advanced)

> "One Claude writes the plan, then they spin up a second Claude to review it as a staff engineer"

### Setup

**Terminal 1: Planning Claude**
```bash
cd your-repo
/plan build payment system
# Creates detailed plan
# Saves to plan.md
```

**Terminal 2: Review Claude**
```bash
cd your-repo  # Same repo, different session
# Read the plan
cat plan.md

# Prompt:
"You are a staff engineer reviewing this implementation plan.
Be critical. Find holes, edge cases, and potential issues.
Challenge assumptions. Suggest improvements."
```

**Back to Terminal 1:**
```bash
# Read review Claude's feedback
# Refine plan based on feedback
# Exit plan mode
# Implement refined plan
```

### Benefits of Two-Claude Planning

✅ Higher quality plans - Two perspectives
✅ Catches issues early - Before coding
✅ Better edge case coverage - Critical review finds gaps
✅ More robust implementation - Plan already battle-tested

## Plan Mode Workflow Integration

### In Global Workflow

**Phase 1: Planning** (BEFORE any coding)
```bash
# Every complex task starts here
/plan

# Intensive planning with user + coach agent
# Create overly verbose, explicit spec
# Get user approval

# Only then: exit plan mode and code
```

### End-of-Session Planning

```bash
# Finished feature A
# Before starting feature B

/plan feature B

# Plan tomorrow's work today
# Start tomorrow with clear direction
```

### When Things Go Sideways

```bash
# Implementation getting messy
# Bugs appearing
# Lost direction

/plan

# Stop coding, start planning
# Figure out what went wrong
# Design better approach
# Resume with clarity
```

## Plan Mode Best Practices

### 1. Pour Energy Into the Plan

**Don't rush planning to "get to coding"**

Spend 30-60 minutes on thorough plan:
- Ask all the "obvious" questions
- Explore codebase thoroughly
- Consider alternatives
- Think through edge cases

**Result:** 1-shot implementation saves hours

### 2. Make Plans Explicit and Verbose

**Bad plan:**
```
- Add auth
- Update routes
- Test it
```

**Good plan:**
```
## Authentication Implementation Plan

### Step 1: Database Schema
Create users table with:
- id (uuid, primary key)
- email (unique, indexed)
- password_hash (bcrypt with salt rounds = 10)
- created_at, updated_at
- email_verified (boolean, default false)

Migration file: migrations/001_create_users.sql
Rollback: Drop table and indexes

### Step 2: Auth Service
File: src/auth/service.ts

Functions:
- hashPassword(password: string): Promise<string>
  Uses bcrypt.hash with SALT_ROUNDS from env
  Validates password strength first (min 8 chars, complexity)

[etc. - extremely detailed]
```

### 3. Document Alternatives Considered

**Why this matters:**

Future you (or other devs) will wonder "why did we do it this way?"

**In plan:**
```
## Approach Considered

### Option A: JWT in localStorage (CHOSEN)
Pros: Simple, works across tabs
Cons: XSS vulnerability
Mitigation: Strict CSP, short expiry

### Option B: HttpOnly cookies
Pros: XSS-safe
Cons: CSRF risk, harder with mobile apps
Mitigation: Would need CSRF tokens

Decision: Option A with aggressive CSP
```

### 4. Update Plan During Implementation

If you discover issues during implementation:

```bash
# Don't just fix and continue
# Update the plan first

# Re-enter plan mode
/plan

# Update plan with new findings
# Then resume implementation

# Plan stays accurate
# Documents decisions
```

## Plan File Structure

Save plans as files for reference:

```markdown
# Feature Name - Implementation Plan

**Created:** 2026-02-02-12-00
**Last Updated:** 2026-02-02-14-30

## Requirements
[What we're building - explicit, verbose]

## Approach
[How we'll build it - step-by-step]

## Files to Create/Modify
- path/to/file.ts (new) - Purpose
- path/to/other.ts (modify) - Changes needed

## Tests
- Test case 1: Description
- Test case 2: Description

## Edge Cases
- Edge case 1: How we'll handle
- Edge case 2: How we'll handle

## Alternatives Considered
- Option A: Description, pros/cons
- Option B: Description, pros/cons
- Decision: Why we chose X

## Implementation Checklist
- [ ] Step 1
- [ ] Step 2
[etc.]

## Questions for User
1. Question 1?
2. Question 2?
```

## Plan Mode Triggers

**Automatically suggest plan mode when:**

1. User says "build", "implement", "add" + complex feature
2. Multiple files will be affected (>3)
3. Architectural decision needed
4. Previous approach failed
5. User says "I'm not sure how to..."

**Example:**

```
User: "Add real-time notifications to the app"

Claude: "This is a complex feature involving WebSockets,
database changes, and UI updates. Let me enter plan mode
to design a comprehensive approach.

/plan
```

## Team Tips from Boris

> **Tip #2:** "Start every complex task in plan mode. Pour your energy into the plan so Claude can 1-shot the implementation."

> **Advanced:** "One person has one Claude write the plan, then they spin up a second Claude to review it as a staff engineer."

> **When stuck:** "The moment something goes sideways, they jump to plan mode, write a 1-pager on what went wrong, and ask Claude to propose 3 alternative approaches."

## Related Commands

- `CLAUDE.md` - Global workflow (auto-loaded, includes planning guidance)
- `/submit-pr` - After implementation (should reference plan)
- Create worktree for planning: `/create-worktree plan-feature-name`

## Implementation

When you run `/plan`:

1. Check if task is complex enough for plan mode
2. If yes: `EnterPlanMode`
3. Guide through planning process
4. Engage coach agent if needed
5. Create detailed plan document
6. Get user approval
7. `ExitPlanMode` when ready
8. Proceed with 1-shot implementation

**Result:** Higher quality, fewer iterations, clearer thinking.
