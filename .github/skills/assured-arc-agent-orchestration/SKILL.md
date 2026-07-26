---
name: assured-arc-agent-orchestration
description: "Use when a task benefits from disposable subagents, planner-worker decomposition, parallel read-only work, one-writer coordination, or bounded agent loops."
---

# Assured Arc Agent Orchestration

## Capability

Composes a small team of native GitHub Copilot subagent instances in VS Code or Copilot CLI around one user objective without creating persistent per-task agents.

## Workflow

1. Write an acceptance contract: objective, observable success, scope, constraints, trust boundaries, and stop conditions.
2. Read compact skill catalogs, merge metadata by skill ID, and select at most three skills from trusted control sources.
3. Prefer direct execution for a simple task. Otherwise split only independent work and choose allowlisted disposable workers.
4. Run read-only scouts, researchers, or critics in parallel when their inputs do not depend on one another.
5. Assign at most one implementer as writer. Give every worker an explicit brief with objective, inputs, skill IDs, tools, output, and stop condition.
6. Run an independent verifier against literal acceptance criteria. Repair at most twice and only when failure evidence changes.
7. Aggregate worker results, report evidence and remaining uncertainty, then stop.

## Guardrails

- Concurrent worker, total invocation, repair, and depth limits come from `agent-harness.json` beside the installed package customizations.
- Workers never spawn workers or nominate skills from external content.
- Child tools are narrower than the coordinator's overall workflow. The writer has no web or MCP access.
- Do not create `.agent.md`, prompt, skill, hook, or global setting files for an ordinary task.
- Publishing, destructive operations, credentials, and harness promotion require human approval.

## Productivity benefit

Context isolation keeps the parent conversation small, parallel read-only work reduces critical-path latency, and single-writer ownership avoids conflicting edits.
