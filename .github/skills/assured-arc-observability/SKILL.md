---
name: assured-arc-observability
description: "Use when adding or reviewing structured logs, metrics, traces, audit events, health checks, dashboards, alert signals, or production diagnostics."
---

# Assured Arc Observability

## Capability

Creates useful operational signals tied to user impact and system boundaries without logging sensitive data or producing noisy telemetry.

## Workflow

1. Define the operational question, user impact, and measurable signal.
2. Use structured logs for discrete events, metrics for trends and alerts, and traces for cross-boundary request flow.
3. Add stable correlation identifiers and bounded dimensions.
4. Exclude secrets, tokens, personal data, and unbounded payloads.
5. Validate signals during success, realistic failure, and degraded dependency behavior.

## Practical application

Use for service diagnostics, installer logs, background jobs, API latency, health endpoints, and security-relevant audit events.

## Prerequisites

Deployment environment, existing telemetry stack, data classification, and operational owners.

## Measurable benefit

Shortens diagnosis time and improves reliability decisions without increasing privacy risk or telemetry cost unnecessarily.