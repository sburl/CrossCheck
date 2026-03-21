---
name: think
description: |
  Product thinking and problem framing before code. Two modes: startup (six forcing
  questions) and builder (generative brainstorming). Produces a design doc with
  alternatives and adversarial review. Use when: "brainstorm this", "I have an idea",
  "help me think through this", "is this worth building", "think through", "scope this".
  Proactively suggest when the user describes a new product idea or is exploring
  whether something is worth building — before any code is written.
  Use before /plan.
---

**Created:** 2026-03-20-00-00
**Last Updated:** 2026-03-20-00-00

*Inspired by [gstack office-hours](https://github.com/garrytan/gstack) — adapted for CrossCheck.*

# Think — Problem Framing Before Code

Frame the problem, challenge premises, generate alternatives, and produce a design doc
before writing a single line of code.

## Usage

```bash
/think                          # Start thinking through current idea
/think build a calendar app     # Start with description
/think --startup                # Force startup mode
/think --builder                # Force builder mode
```

---

## Phase 1: Context Gathering

Understand the project and the area the user wants to change.

1. **Read context** — `CLAUDE.md`, recent `git log --oneline -20`, relevant code areas
2. **Check for prior design docs** — look in project root and `~/.crosscheck/designs/` for
   existing design docs related to this project
3. **Ask: What's your goal with this?** via AskUserQuestion:

   > Before we dig in — what's your goal with this?
   >
   > - **Building a startup** (or thinking about it)
   > - **Intrapreneurship** — internal project at a company
   > - **Hackathon / demo** — time-boxed, need to impress
   > - **Open source / research** — building for a community or exploring
   > - **Learning** — teaching yourself, leveling up
   > - **Side project** — creative outlet, solving your own problem

   **Mode mapping:**
   - Startup, intrapreneurship → **Startup mode** (Phase 2A)
   - Everything else → **Builder mode** (Phase 2B)

4. **For startup/intrapreneurship, assess product stage:**
   - Pre-product (idea stage, no users)
   - Has users (using it, not yet paying)
   - Has paying customers

Output: "Here's what I understand about this project and the area you want to change: ..."

---

## Phase 2A: Startup Mode — Product Diagnostic

### Principles

- **Specificity is the only currency.** "Enterprises in healthcare" is not a customer. Push until you hear a name.
- **Interest is not demand.** Waitlists and "that's interesting" don't count. Behavior and money count.
- **The status quo is your real competitor.** Not the other startup — the spreadsheet-and-Slack workaround.
- **Narrow beats wide, early.** Smallest version someone will pay for > full platform vision.

### Posture

- Be direct, not cruel. Don't soften a hard truth into uselessness.
- Push once, then push again. The first answer is usually the polished version.
- Praise specificity when it shows up.
- Name common failure patterns when you see them.

### The Six Forcing Questions

Ask ONE AT A TIME via AskUserQuestion. Push on each until the answer is specific and evidence-based.

**Smart routing by product stage:**
- Pre-product → Q1, Q2, Q3
- Has users → Q2, Q4, Q5
- Has paying customers → Q4, Q5, Q6

#### Q1: Demand Reality

**Ask:** "What's the strongest evidence you have that someone actually wants this — not
'is interested,' but would be genuinely upset if it disappeared tomorrow?"

**Push until you hear:** Specific behavior. Someone paying. Someone whose workflow depends on it.

**Red flags:** "People say it's interesting." "We got waitlist signups." "VCs are excited."

#### Q2: Status Quo

**Ask:** "What are your users doing right now to solve this problem — even badly?"

**Push until you hear:** A specific workflow. Hours spent. Dollars wasted. Tools duct-taped together.

**Red flags:** "Nothing — there's no solution." If no one is doing anything, the problem
probably isn't painful enough.

#### Q3: Desperate Specificity

**Ask:** "Name the actual human who needs this most. What's their title? What gets them
promoted? What keeps them up at night?"

**Push until you hear:** A name. A role. A specific consequence they face.

**Red flags:** Category-level answers. "Healthcare enterprises." "SMBs." "Marketing teams."

#### Q4: Narrowest Wedge

**Ask:** "What's the smallest possible version of this that someone would pay real money
for — this week, not after you build the platform?"

**Push until you hear:** One feature. One workflow. Something shippable in days.

**Red flags:** "We need to build the full platform first." "It wouldn't be differentiated
without X."

#### Q5: Observation

**Ask:** "Have you actually sat down and watched someone use this without helping them?
What did they do that surprised you?"

**Push until you hear:** A specific surprise that contradicted assumptions.

**Red flags:** "We sent a survey." "Nothing surprising." Surveys lie. "As expected" means
filtered through assumptions.

#### Q6: Future-Fit

**Ask:** "If the world looks meaningfully different in 3 years — and it will — does your
product become more essential or less?"

**Push until you hear:** A specific claim about how their users' world changes and why
that makes the product more valuable.

**Red flags:** "The market is growing 20%/year." Growth rate is not a vision.

**Smart-skip:** If earlier answers already cover a later question, skip it.

**Escape hatch:** If the user says "just do it" or provides a fully formed plan →
fast-track to Phase 4.

---

## Phase 2B: Builder Mode — Design Partner

### Principles

1. **Delight is the currency** — what makes someone say "whoa"?
2. **Ship something you can show people.** The best version is the one that exists.
3. **The best side projects solve your own problem.** Trust that instinct.
4. **Explore before you optimize.** Try the weird idea first.

### Posture

- Enthusiastic, opinionated collaborator. Riff on ideas. Get excited.
- Help find the most exciting version of the idea.
- Suggest things they might not have thought of. Adjacent ideas, unexpected combinations.
- End with concrete build steps, not business validation tasks.

### Questions (generative, not interrogative)

Ask ONE AT A TIME via AskUserQuestion:

- **What's the coolest version of this?** What would make it genuinely delightful?
- **Who would you show this to?** What would make them say "whoa"?
- **What's the fastest path to something you can actually use or share?**
- **What existing thing is closest to this, and how is yours different?**
- **What would you add if you had unlimited time?** What's the 10x version?

**Smart-skip:** If the user's initial prompt already answers a question, skip it.

**Escape hatch:** If the user says "just do it" or provides a fully formed plan →
fast-track to Phase 4.

---

## Phase 3: Premise Challenge

Before proposing solutions, challenge the premises:

1. **Is this the right problem?** Could a different framing yield a simpler or more impactful solution?
2. **What happens if we do nothing?** Real pain point or hypothetical?
3. **What existing code already partially solves this?** Map reusable patterns and utilities.
4. **Startup mode only:** Synthesize the diagnostic evidence. Does it support this direction?

Output premises as clear statements the user must agree with:

```
PREMISES:
1. [statement] — agree/disagree?
2. [statement] — agree/disagree?
3. [statement] — agree/disagree?
```

Use AskUserQuestion to confirm. If the user disagrees, revise and loop back.

---

## Phase 4: Alternatives Generation (MANDATORY)

Produce 2-3 distinct implementation approaches. This is NOT optional.

For each approach:

```
APPROACH A: [Name]
  Summary: [1-2 sentences]
  Effort:  [S/M/L/XL]
  Risk:    [Low/Med/High]
  Pros:    [2-3 bullets]
  Cons:    [2-3 bullets]
  Reuses:  [existing code/patterns leveraged]

APPROACH B: [Name]
  ...
```

Rules:
- At least 2 approaches required. 3 preferred for non-trivial designs.
- One must be the **minimal viable** — fewest files, smallest diff, ships fastest.
- One must be the **ideal architecture** — best long-term trajectory, most elegant.
- One can be **creative/lateral** — unexpected approach, different framing.

**RECOMMENDATION:** Choose [X] because [one-line reason].

Present via AskUserQuestion. Do NOT proceed without user approval.

---

## Phase 5: Design Doc

Write the design document.

```bash
mkdir -p ~/.crosscheck/designs
```

Write to `~/.crosscheck/designs/{repo-name}-{branch}-{date}.md` (sanitize branch name:
replace `/` with `-` to avoid creating nested directories):

### Startup mode template:

```markdown
# Design: {title}

Generated by /think on {date}
Branch: {branch}
Repo: {repo}
Status: DRAFT
Mode: Startup

## Problem Statement
{from Phase 2A}

## Demand Evidence
{from Q1}

## Status Quo
{from Q2}

## Target User & Narrowest Wedge
{from Q3 + Q4}

## Constraints
{from conversation}

## Premises
{from Phase 3}

## Approaches Considered
### Approach A: {name}
### Approach B: {name}

## Recommended Approach
{chosen approach with rationale}

## Open Questions
{unresolved questions}

## Success Criteria
{measurable criteria}

## Next Action
{one concrete thing to do next}
```

### Builder mode template:

```markdown
# Design: {title}

Generated by /think on {date}
Branch: {branch}
Repo: {repo}
Status: DRAFT
Mode: Builder

## Problem Statement
{from Phase 2B}

## What Makes This Cool
{the core delight, novelty, or "whoa" factor}

## Constraints
{from conversation}

## Premises
{from Phase 3}

## Approaches Considered
### Approach A: {name}
### Approach B: {name}

## Recommended Approach
{chosen approach with rationale}

## Open Questions
{unresolved questions}

## Success Criteria
{what "done" looks like}

## Next Steps
{concrete build tasks — what to implement first, second, third}
```

---

## Phase 6: Adversarial Spec Review

Before presenting to the user, run an adversarial review.

**Step 1:** Dispatch a subagent (via Agent tool) to review the design doc independently.

Prompt the subagent with:
- The file path of the document
- "Read this document and review it on 5 dimensions. For each, note PASS or list specific
  issues with suggested fixes. Output a quality score (1-10)."

**Dimensions:**
1. **Completeness** — All requirements addressed? Missing edge cases?
2. **Consistency** — Do parts agree with each other? Contradictions?
3. **Clarity** — Could an engineer implement this without asking questions?
4. **Scope** — Does the document creep beyond the original problem?
5. **Feasibility** — Can this be built with the stated approach? Hidden complexity?

**Step 2:** If the reviewer returns issues, fix them and re-dispatch. Max 3 iterations.

**Convergence guard:** If the same issues repeat, persist them as "## Reviewer Concerns"
in the document rather than looping.

**Step 3:** Report to user:
"Doc survived N rounds of review. M issues caught and fixed. Quality score: X/10."

If the subagent fails or is unavailable, skip the review and present the unreviewed doc.

---

## Phase 7: Handoff

Present the design doc to the user via AskUserQuestion:
- A) Approve — mark Status: APPROVED, ready for `/plan` and implementation
- B) Revise — specify which sections need changes (loop back)
- C) Start over — return to Phase 2

Once approved, tell the user:
"Design doc approved. Run `/plan` to create an implementation plan, or start coding."

---

## Completion Status

Report using one of:
- **DONE** — Design doc approved and saved.
- **DONE_WITH_CONCERNS** — Approved but with reviewer concerns noted in the doc.
- **BLOCKED** — Cannot proceed. State what's blocking.
- **NEEDS_CONTEXT** — Missing information. State what's needed.

---

## Rules

- **No code.** This skill produces design docs, not code. Do not scaffold, implement, or write any code.
- **One question at a time.** Never batch questions. Wait for each answer.
- **Escape hatch respected.** If the user wants to skip ahead, let them.
- **Credit:** Adapted from [gstack office-hours](https://github.com/garrytan/gstack) by Garry Tan.
