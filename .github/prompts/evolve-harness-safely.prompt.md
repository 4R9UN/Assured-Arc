---
name: evolve-harness-safely
description: "Analyze repeated sanitized run evidence and draft a falsifiable harness change without promoting it globally."
argument-hint: "Describe the recurring failure evidence and evaluation scenarios"
agent: Assured Arc Orchestrator
---

Use the research-only harness evolution workflow for `${input:failure:Recurring failure pattern}`.

1. Read `assured-arc-harness-evolution` and the local harness policy.
2. Require repeated sanitized evidence and a reproducible evaluation scenario.
3. Separate evaluation, root-cause analysis, proposal, verification, and promotion roles.
4. Draft one narrow change contract: component, evidence, root cause, targeted fix, predicted benefit, regression risk, and verification plan.
5. Apply changes only if the user provided an isolated worktree and disposable profile. Otherwise return a patch plan only.
6. Run baseline and regression checks. Do not trust self-attribution or promote automatically.
7. Return a keep, revise, or revert recommendation for human review.

Never modify installed global agents, skills, hooks, settings, or installer state from this workflow.
