---
name: review-current-change
description: "Review the current diff for correctness, regression, security, tests, rollback, and unnecessary complexity."
argument-hint: "Optional: provide the originating requirement or focus area"
agent: Assured Arc QA
---

Review the current change against `${input:requirement:The intended outcome or requirement}`.

1. Inspect the diff and repository instructions.
2. Trace changed inputs, state transitions, outputs, failures, cleanup, and rollback.
3. Check tests for realistic behavior and regression coverage.
4. Report only evidence-backed findings, ordered as blocking, important, then advisory.
5. For each finding include location, impact, evidence, and the smallest practical fix.

If no actionable findings exist, state that clearly and list what was verified.
