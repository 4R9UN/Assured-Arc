---
name: assured-arc-error-handling
description: "Use when designing exceptions, result types, validation failures, retries, partial failure handling, cleanup, user-facing errors, or API error contracts."
---

# Assured Arc Error Handling

## Capability

Makes failures explicit, actionable, and safe at the correct abstraction boundary.

## Workflow

1. Classify failures as invalid input, expected domain outcome, transient dependency failure, permanent dependency failure, or programmer defect.
2. Handle a failure where enough context exists to recover, translate, or add useful information.
3. Preserve the original cause and avoid broad catch-and-ignore behavior.
4. Keep user-facing messages safe while logs retain diagnostic context without secrets.
5. Test cleanup, partial state, retry boundaries, and error contract stability.

## Practical application

Use for APIs, CLIs, installers, batch processing, background jobs, and external service calls.

## Prerequisites

Existing error conventions, logging strategy, and failure requirements.

## Measurable benefit

Reduces hidden corruption, meaningless errors, unsafe retries, and difficult production diagnosis.