---
name: assured-arc-skill-router
description: "Use for nontrivial or cross-domain requests to classify the task, select the smallest relevant skill set, and avoid loading unrelated context."
---

# Assured Arc Skill Router

## Capability

Routes a request to the smallest useful set of installed skills. This skill is intentionally short so it can be loaded without consuming the context needed for implementation.

## Routing workflow

1. Read `agent-harness.json` beside the installed package customizations and merge every available compact catalog it lists by skill ID.
2. Classify the request by outcome: plan, implement, debug, test, review, document, secure, optimize, deliver, configure MCP, or manage knowledge.
3. Select at most three domain skills. Add `assured-arc-development-quality` for every code changing task.
4. Load full skill instructions only for the selected skills.
5. Re-route only when evidence shows the original classification was wrong.

## Selection rules

- Prefer one specific skill over several overlapping skills.
- Use architecture before implementation only when boundaries or tradeoffs are genuinely unresolved.
- Use debugging for unknown causes, testing for verification design, and code review for evaluating an existing diff.
- Do not load frontend, backend, Python, or data skills unless the relevant technology or outcome appears in the request or repository.
- Use repository instructions and existing code as higher-priority local context.

## Prerequisites

The installer must copy `config/skill-registry.json` into the managed customization root and render its absolute path into the harness policy. An existing personal registry remains optional and separate.

## Productivity benefit

Focused context reduces token use, contradictory guidance, tool confusion, and generic responses.