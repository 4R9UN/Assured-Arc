---
name: assured-arc-architecture-design
description: "Use when designing system boundaries, data flow, APIs, deployment topology, architectural tradeoffs, or major refactors before implementation."
---

# Assured Arc Architecture Design

## Capability

Produces a minimum viable architecture grounded in the existing repository and explicit quality requirements.

## Workflow

1. **Heilmeier & Boundary Clarity**: State the plain-English objective, current limits, actors, trust boundaries, scale assumptions, risks, and falsifiable success checks before touching code.
2. **Reuse-First Inspection**: Map existing repository components and conventions before proposing any new module, service, or dependency.
3. **Alternatives & TRIZ Contradiction Check**:
   - **Alternatives Rule**: Evaluate at least one viable alternative and record the concrete technical, cost, or complexity reason it was rejected.
   - **TRIZ False-Compromise Check**: When two goals conflict (for example latency vs. safety or extensibility vs. simplicity), test whether *Segmentation*, *Extraction* (hooks/sidecars), *Preliminary Action* (pre-indexing), *Inversion* (contract rendering), or *Cheap Dispensables* (stateless subagents) resolves the conflict, and state its **Secondary Operational Liability** explicitly (or record `"No false compromise detected"`).
4. **Zero-Decision Implementation Readiness**: Define exact component responsibilities, schemas, error contracts, test cases, and an explicit **`Target Scope & File Boundary`** allowlist of repo-relative files so an implementer makes zero design guesses.
5. **Independent Goldfish Review & Artifact Delivery**: Write multi-section specs to a workspace or artifact file (never dump walls of text in chat) and stress-test high-risk designs with a fresh zero-context critic (`include-custom-instructions: false`).

## Practical application

Use for a new service, a persistent agent workflow, a database boundary, an event pipeline, or a refactor that changes module ownership.

## Prerequisites

Repository structure, current interfaces, deployment constraints, and nonfunctional requirements.

## Measurable benefit

Reduces rework by resolving boundary decisions before code is distributed across multiple files or services.