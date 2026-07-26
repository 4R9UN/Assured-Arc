---
name: assured-arc-harness-evolution
description: "Use only when explicitly evaluating or improving agent prompts, tools, hooks, skills, subagents, middleware, or memory from repeated run evidence."
---

# Assured Arc Harness Evolution

## Purpose

Improves the external harness around a fixed model through a separate, review-gated `evaluate → analyze → improve → verify` loop.

This is not part of ordinary daily execution. Daily agents cannot modify global harness assets.

## Observable components

- System and global instructions
- Tool descriptions and implementations
- Hooks and deterministic middleware
- Skills and compact registries
- Subagent definitions and routing policy
- Long-term memory and context policy
- Evaluation scenarios and verifiers

## Workflow

1. Evaluate a frozen harness on multiple isolated scenarios and retain pass, fail, timeout, cost, and sanitized trace metadata.
2. Distill traces into an overview plus drill-down reports with links to local evidence.
3. Identify a repeated failure pattern and choose the narrowest component that owns the failure.
4. Produce a change contract with failure evidence, root cause, targeted fix, predicted benefit, regression risk, and verification plan.
5. Apply the proposal only in a disposable worktree and isolated VS Code profile.
6. Run the original and regression scenarios. Keep, revise, or revert the change based on observed deltas.
7. Require independent human review before promoting an immutable commit through the trusted installer.

## Governance

- The evaluator, proposer, and promoter are separate roles.
- The evolution worker cannot access personal credentials, global settings, private workspaces, or installer state.
- Automatic promotion, publishing, and production self-modification are prohibited.
- Regression predictions are hypotheses, not evidence. Broad changes require broader evaluation.

## Productivity benefit

Turns recurring agent failures into auditable harness improvements while avoiding uncontrolled prompt growth and self-modifying production behavior.
