---
name: assured-arc-documentation-quality
description: "Use when writing README files, tutorials, API references, architecture docs, runbooks, changelogs, or auditing spec-to-code and documentation drift."
---

# Assured Arc Documentation Quality

## Capability

Creates task-oriented documentation and performs rigorous spec-to-code drift detection so checked-in docs and implemented code stay synchronized.

## Workflow

1. Identify the reader, task, prerequisites, and expected outcome; write long-form specs or drift reports to files rather than dumping large drafts into chat.
2. Verify every command, flag, configuration key, symbol name, file path, and limitation directly against current source files.
3. Put the shortest successful path first, then customization, troubleshooting, and rollback.
4. **Spec-to-Code Drift Audit**: When checking existing design docs or READMEs against the codebase, report **only concrete divergences** across four classes (*Missing Features*, *Incomplete Models/Configs*, *Logic Shortcuts*, and *Architectural Divergence / Undocumented Logic*), or output `"No drift detected"`.
5. Validate local links, code examples, diagram accuracy, and platform differences.

## Practical application

Use for project READMEs, installation guides, architecture diagrams, MCP documentation, and operational runbooks.

## Prerequisites

Implemented behavior, source files, and target audience.

## Measurable benefit

Reduces onboarding time and support load by giving developers accurate, verifiable workflows.