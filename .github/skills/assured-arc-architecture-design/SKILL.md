---
name: assured-arc-architecture-design
description: "Use when designing system boundaries, data flow, APIs, deployment topology, architectural tradeoffs, or major refactors before implementation."
---

# Assured Arc Architecture Design

## Capability

Produces a minimum viable architecture grounded in the existing repository and explicit quality requirements.

## Workflow

1. Identify actors, outcomes, constraints, trust boundaries, and scale assumptions.
2. Inspect existing components and conventions before proposing new ones.
3. Define component responsibilities, data flow, failure boundaries, and public interfaces.
4. Compare the simplest viable approach with one meaningful alternative.
5. Record decisions, risks, verification strategy, and deferred concerns.

## Practical application

Use for a new service, a persistent agent workflow, a database boundary, an event pipeline, or a refactor that changes module ownership.

## Prerequisites

Repository structure, current interfaces, deployment constraints, and nonfunctional requirements.

## Measurable benefit

Reduces rework by resolving boundary decisions before code is distributed across multiple files or services.