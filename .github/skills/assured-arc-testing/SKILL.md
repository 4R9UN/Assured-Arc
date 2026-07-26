---
name: assured-arc-testing
description: "Use when designing or implementing unit, integration, end-to-end, regression, installer, or configuration validation tests."
---

# Assured Arc Testing

## Capability

Selects the cheapest test layer that proves the requested behavior and protects realistic regressions.

## Workflow

1. Define the observable behavior and failure mode.
2. Choose unit tests for pure logic, integration tests for boundaries, and end-to-end tests only for critical workflows.
3. Prefer deterministic fixtures and isolated temporary paths.
4. Test success, realistic failure, and rollback or cleanup when the operation mutates state.
5. Run focused tests first, then the relevant broader suite.

## Practical application

Use for parsers, APIs, UI behavior, installers, MCP configuration, data migrations, and bug regressions.

## Prerequisites

Existing test framework or a documented validation command. Do not add a framework when a small built-in validation is sufficient.

## Measurable benefit

Improves confidence while keeping test runtime and maintenance proportional to risk.