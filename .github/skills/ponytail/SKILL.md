---
name: ponytail
description: "Use when the user asks for the simplest solution, minimal code, YAGNI, stdlib-first implementation, deletion of overengineering, or a lazy senior developer review."
license: MIT
source: "Adapted from https://github.com/DietrichGebert/ponytail"
---

# Ponytail

Use this skill only when explicitly requested or when the task is clearly about overengineering. The default development quality gate already enforces restraint for ordinary coding work.

## Capability

Finds the shortest correct path through this ladder:

1. Does the requested code need to exist?
2. Can the standard library solve it?
3. Can the platform or existing dependency solve it?
4. Can one direct implementation replace a new abstraction?
5. What can be deleted after the change?

## Workflow

- Restate the requested behavior without speculative additions.
- Prefer deletion, reuse, or one direct function before a framework or configurable abstraction.
- Preserve necessary validation, security, correctness, and realistic error handling. “Simple” does not mean unsafe or incomplete.
- In a review, identify the exact abstraction, dependency, or branch that can be removed and what replaces it.
- Verify the minimal implementation against the same success criteria as any other code change.

## Modes

- Lite: implement what was asked and mention one simpler alternative when useful.
- Full: enforce YAGNI, standard library first, platform first, then minimum code.
- Ultra: challenge whether the feature or abstraction should exist at all. Use only when the user explicitly requests it.

## Productivity benefit

Reduces code volume, dependency surface, maintenance cost, and review time while keeping correctness and safety intact.
