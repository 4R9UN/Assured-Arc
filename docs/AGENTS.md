# AI Agents

The orchestrator provides one global entry point, while visible specialists and hidden disposable workers remain intentionally narrow. Repository agents are discovered by both VS Code and Copilot CLI. Personal CLI installation stores one shared user-level agent copy under the Copilot home and points VS Code to that source.

## Assured Arc Orchestrator

**Purpose:** coordinate the native disposable agent harness for nontrivial and cross-domain requests.

**Interaction model:** build an acceptance contract, merge compact skill catalogs, select no more than three domain skills, delegate to at most three allowlisted workers, enforce one writer, run independent verification, and repair at most twice.

**Host integration:** the coordinator uses portable `read`, `search`, and `agent` aliases. Editing, execution, and web research are delegated to workers with narrower capabilities in both hosts.

**Use cases:** general implementation requests, tasks spanning architecture and code, or requests where the correct specialist is not obvious.

## Hidden disposable workers

| Worker | Tools | Responsibility |
| --- | --- | --- |
| Assured Arc Disposable Scout | Read and search | Focused local repository discovery |
| Assured Arc Disposable Researcher | Read, search, web, Context7, Sequential Thinking, and arXiv | First party public evidence with provenance |
| Assured Arc Disposable Implementer | Read, edit, and search | The only implementation writer, with validation delegated to the independent verifier |
| Assured Arc Disposable Verifier | Read, search, and execute | Independent focused checks without edits |
| Assured Arc Disposable Critic | Read and search | Independent correctness, security, regression, and complexity challenge |

Workers are hidden from the picker, protected from general model selection, and explicitly allowlisted by the orchestrator. Every worker has `agents: []`, so delegation depth stays one. Disposable means the native subagent context ends after the worker returns. It does not mean generating a new agent file for each task.

## Assured Arc Development

**Purpose:** implement, debug, test, and refactor code with small verified changes.

**Interaction model:** inspect, select focused skills, implement, validate, report.

**Host integration:** custom agent picker or `/agent`, workspace file tools, and terminal validation.

**Use cases:** bug fixes, focused features, installer improvements, configuration migration.

## Assured Arc Documentation

**Purpose:** write accurate public documentation and diagrams.

**Interaction model:** inspect source files, validate claims, update docs, keep diagrams aligned.

**Host integration:** Markdown authoring and validation in both hosts, with VS Code preview support.

**Use cases:** README updates, onboarding guides, architecture documentation, tutorials.

## Assured Arc Architecture

**Purpose:** plan system boundaries, interfaces, data flow, deployment topology, and major refactors.

**Interaction model:** inspect existing code, define constraints and trust boundaries, compare the minimum viable architecture with one meaningful alternative, and record decisions.

**Host integration:** portable read, search, edit, and web tool aliases.

**Use cases:** service decomposition, API boundaries, event flows, persistence design, and major module ownership changes.

## Assured Arc QA

**Purpose:** reproduce failures, design focused tests, validate implementations, and assess regression and rollback behavior.

**Interaction model:** choose debugging, testing, or review skills; use isolated state; verify success, realistic failure, cleanup, and rollback.

**Host integration:** source and test editing plus terminal execution.

**Use cases:** bug reproduction, regression tests, installer lifecycle validation, and implementation signoff.

## Assured Arc Research

**Purpose:** evaluate public extensions, skills, MCP servers, and documentation before adoption.

**Interaction model:** read only, evidence based recommendation, no installation side effects.

**Host integration:** web and repository research plus the reviewed Context7, Sequential Thinking, and arXiv MCP tool sets.

**Use cases:** assess a marketplace extension, compare MCP transports, review community skills, check licenses.

## Assured Arc Security Review

**Purpose:** inspect installation and configuration safety before release or rollout.

**Interaction model:** read only review with blocking, important, and advisory findings.

**VS Code integration:** review scripts, config, and documentation without mutation.

**Use cases:** release readiness, secret scanning, MCP scope review, backup and rollback review.

## Why separate agents help

Separate agents prevent a documentation task from silently installing software, and prevent a research task from mutating a user environment. Narrow roles improve predictable behavior and make permissions easier to review.

## Manual handoffs

Visible agents offer reviewable handoff buttons for the smallest common flow:

`Research → Architecture → Development → QA → Security Review → Development`

Architecture can also start Development directly, and Documentation hands off to QA. Every handoff uses `send: false`, so the user can inspect or edit the prepared prompt before sending. Hidden disposable workers and their tool scopes are unchanged.

See [HARNESS.md](HARNESS.md) for budgets, hooks, context policy, daily use, and the separate harness evolution workflow.
