---
name: assured-arc-codebase-reuse-hygiene
description: "Use when implementing features, refactoring, fixing bugs, or reviewing code to enforce deep codebase comprehension, reuse of existing modules/helpers, anti-bloat surgical edits, and cleanup of dead code or unwanted files."
license: MIT
---

# Assured Arc Codebase Reuse & Hygiene

Use this skill whenever writing, refactoring, or reviewing code so the agentic system understands existing architecture, reuses established utilities, prevents code bloat, and keeps the workspace clean.

## Capability

Enforces a four-step engineering discipline: **Understand → Reuse → Minimal Edit → Clean Up**.

## Workflow

1. **Map Before Writing (Understand the System)**
   - Search the codebase for existing modules, shared helpers, constants, schemas, and tests that already solve part or all of the problem.
   - Trace callers, callees, and data contracts before proposing new files or functions.
2. **Reuse Before Creating (Zero Redundancy)**
   - Extend or parameterize existing functions, classes, and configuration tables rather than creating parallel implementations.
   - Reuse standard library and already-installed repository dependencies before proposing any new package.
   - Never create a new file when an existing module already owns that responsibility.
3. **Prevent Code Bloat (Surgical Changes)**
   - Write the smallest direct implementation that satisfies the acceptance criteria.
   - Do not add speculative abstractions, wrapper-around-wrapper layers, unused parameters, or unrequested configuration flags.
   - Do not leave commented-out code blocks, `TODO` placeholders, or debug `print`/`console.log` statements.
4. **Clean Up Unwanted Code & Files (Workspace Hygiene)**
   - When replacing or refactoring logic, delete the obsolete functions, dead branches, unused imports, and orphaned files in the same change.
   - Remove any temporary scratch files, `.bak`/`.tmp` artifacts, or one-off debug scripts before completing the task.
   - Verify `git status` and `git diff` confirm only intentional, minimal changes remain.

## Guardrails

- Never delete user-owned data, untracked personal notes, or human-gated control-plane files without explicit approval.
- Ensure every deletion of dead code or superseded files is verified by running the repository test suite and scoreboard checks.

## Productivity benefit

Keeps the codebase compact, idiomatic, and easy to maintain by eliminating duplicate helpers, bloated diffs, dead code, and leftover scratch files.
