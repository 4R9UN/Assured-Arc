---
name: assured-arc-code-review
description: "Use when reviewing a diff, pull request, patch, or proposed change for correctness, regressions, security, maintainability, and unnecessary complexity."
---

# Assured Arc Code Review

## Capability

Reviews changed behavior against the request and repository conventions without rewriting the implementation.

## Workflow

1. Identify the requested outcome and changed files.
2. Trace each changed path through inputs, state changes, outputs, failures, and cleanup.
3. Check tests for behavior, realistic failure, and regression coverage.
4. Flag correctness and security issues before style concerns.
5. Report concise findings with location, impact, evidence, and a practical fix.

## Severity

- Blocking: data loss, security exposure, broken behavior, or unsafe rollback.
- Important: likely regression, missing validation, compatibility break, or significant complexity.
- Advisory: maintainability or documentation improvement with low immediate risk.

## Prerequisites

Diff, originating request or specification, and relevant repository instructions.

## Measurable benefit

Finds defects before merge while avoiding review noise and preference-only feedback.