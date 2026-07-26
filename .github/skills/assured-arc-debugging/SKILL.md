---
name: assured-arc-debugging
description: "Use when investigating bugs, failing tests, crashes, incorrect behavior, regressions, or performance anomalies with an unknown root cause."
---

# Assured Arc Debugging

## Capability

Uses evidence and competing hypotheses to find a root cause before changing code.

## Workflow

1. Reproduce the issue or capture the exact failure signal.
2. Minimize the failing path and identify the last known good behavior.
3. List a small set of plausible causes and the observation that would distinguish each.
4. Instrument or inspect the narrowest relevant boundary.
5. Fix the confirmed cause, add regression coverage, and rerun relevant checks.

## Practical application

Use for a stack trace, flaky test, broken installer, API mismatch, startup failure, or unexplained latency.

## Prerequisites

Failure output, reproduction steps, relevant logs, tests, and code access.

## Measurable benefit

Reduces trial-and-error edits and prevents symptom fixes that leave the underlying defect intact.