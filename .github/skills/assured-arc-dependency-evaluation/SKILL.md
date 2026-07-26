---
name: assured-arc-dependency-evaluation
description: "Use when selecting, adding, upgrading, or replacing libraries, extensions, actions, agent skills, MCP servers, or other third-party dependencies."
---

# Assured Arc Dependency Evaluation

## Capability

Evaluates whether a third-party dependency is necessary, trustworthy, compatible, and maintainable before adoption.

## Workflow

1. Define the missing capability and check native platform or existing dependency options first.
2. Review first-party source, license, release history, maintainers, transitive dependencies, permissions, and network behavior.
3. Check compatibility, migration cost, lock-in, and rollback.
4. Prefer a narrow stable package over a broad framework when both solve the same requirement.
5. Document the decision and add automated update or validation coverage where appropriate.

## Practical application

Use for npm or Python packages, VS Code extensions, GitHub Actions, community skills, and MCP servers such as Context7, Sequential Thinking, and arXiv.

## Prerequisites

Primary source repository, license, package metadata, security advisories, and project constraints.

## Measurable benefit

Reduces supply-chain risk, unnecessary dependencies, and costly migrations.