---
name: assured-arc-agent-evaluation
description: "Use when testing agent loops, tracing subagents, defining behavioral contracts, creating golden scenarios, replaying failures, measuring token or latency budgets, or preventing agent regressions."
---

# Assured Arc Agent Evaluation

## Capability

Evaluates the harness as software through deterministic contracts and sanitized execution evidence rather than trusting an agent's self-assessment.

## Minimum contracts

- Termination: every loop stops within worker, repair, tool, and time budgets.
- Capability: unknown agents, nested delegation, and tool escalation fail closed.
- History: tool results and verifier evidence are associated with the correct run.
- Safety: destructive and global operations require exact human approval.
- Quality: changed behavior satisfies literal acceptance criteria and relevant regression checks.
- Privacy: traces contain metadata only and exclude prompts, arguments, results, secrets, and file contents.

## Workflow

1. Define representative success, failure, timeout, malformed-output, and injection scenarios.
2. Mock subagents and tools so orchestration can be tested without model calls or network access.
3. Record pass or fail, worker count, tool count, elapsed time, and bounded token data when available.
4. Run repeated scenarios to detect non-deterministic regressions, not only one successful sample.
5. Compare changes against a baseline. Reject a harness change that improves one case while causing an unreviewed regression.
6. Keep raw traces local and short-lived. Distill recurring evidence into sanitized run cards.

## Productivity benefit

Makes agent changes reproducible, catches runaway loops and capability drift, and provides evidence for improving the harness without guesswork.
