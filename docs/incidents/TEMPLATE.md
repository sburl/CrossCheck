**Created:** 2026-02-23-00-00
**Last Updated:** 2026-02-23-00-00

# Incident: [Short Description]

> This memo is about learning, not blame. Decision quality is evaluated against
> what we knew at the time, not what we know now.

---

## Intent

What were we trying to achieve? State the original goal — the problem being solved,
not the feature that was built.

> Example: "Speed up the checkout flow to reduce drop-off at the payment step."

---

## What Happened

Objective facts only. What did we observe? What broke, failed, or missed the goal?

> Example: "Deployed payment refactor on 2026-02-20. Error rates spiked 40% for
> 18 minutes. Rolled back at 14:32 UTC."

---

## Why It Diverged

Where did reality depart from the plan? Analyze the system, not individuals.

- What assumption turned out to be wrong?
- What signal arrived too late?
- What was missing from the plan?

---

## Weaknesses in Intent

Where was the spec itself unclear, incomplete, or wrong? This is distinct from
assumptions about facts — this is about the plan itself.

If you had re-run the same work with perfect execution but the same intent, would you
have hit the same problem? If yes, the intent was the root cause.

- Success criteria were not specific enough to catch X
- Constraints didn't mention Y, so the agent optimised for the wrong thing
- The escalation condition for Z was missing

---

## Assumptions That Were Wrong

List the specific beliefs held at decision time that turned out to be false.
These are facts about the world, not weaknesses in the plan.

- "The new Stripe SDK was backward-compatible with our existing webhook handler" ← false
- "Load testing at 2x traffic would be sufficient" ← production was 5x that day

---

## What Changes

Concrete, owned follow-ups. Not vague intentions.

| Change | Owner | Linked PR/Issue |
|--------|-------|-----------------|
| Add webhook compatibility test to CI | - | - |
| Load test at 10x baseline before payment deploys | - | - |
