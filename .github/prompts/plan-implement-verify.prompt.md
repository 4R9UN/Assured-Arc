---
name: plan-implement-verify
description: "Route a development request, implement the smallest correct change, and verify the outcome."
argument-hint: "Describe the feature, bug, refactor, or setup task"
agent: Assured Arc Orchestrator
---

Handle this task end to end: `${input:task:Describe the development outcome}`.

1. Read repository instructions and the compact skill registry.
2. Select no more than three relevant domain skills. Add the development quality gate for code changes.
3. Inspect the relevant implementation and tests.
4. Define a concise observable success condition.
5. Implement the smallest safe change.
6. Run focused verification and relevant regression checks.
7. Report changed files, validation results, and remaining uncertainty.

Do not publish or perform destructive external actions without explicit approval.
