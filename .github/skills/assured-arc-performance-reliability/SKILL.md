---
name: assured-arc-performance-reliability
description: "Use when diagnosing latency, throughput, memory, availability, retries, timeouts, concurrency, resilience, or operational reliability problems."
---

# Assured Arc Performance and Reliability

## Capability

Improves measured bottlenecks and realistic failure handling without premature optimization.

## Workflow

1. Define the metric, baseline, target, workload, and failure budget.
2. Measure before changing code and identify the dominant bottleneck.
3. Optimize the narrowest hot path or resource boundary.
4. Add bounded timeouts, retries only for transient idempotent work, and cleanup for partial failure.
5. Re-measure the target metric and check correctness and resource regressions.

## Practical application

Use for slow APIs, memory growth, queue backlogs, concurrent workers, flaky integrations, and startup time.

## Prerequisites

Representative workload, profiling or metrics, and a measurable target.

## Measurable benefit

Produces evidence-based improvements and avoids complexity that does not improve user-visible performance or reliability.