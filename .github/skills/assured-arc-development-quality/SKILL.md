---
name: assured-arc-development-quality
description: "Use when writing, reviewing, debugging, or refactoring code in this package. Enforces minimal implementation, surgical changes, and verifiable outcomes."
license: MIT
---

# Assured Arc Development Quality

Use this skill for every code changing task in this repository.

## Capability

Turns a request into a small, testable change. It protects installer compatibility and user configuration from speculative rewrites.

## Workflow

1. Inspect the installer, config template, state schema, and relevant validation first.
2. State material assumptions only when repository evidence cannot resolve them.
3. Implement the smallest behavior that meets the request.
4. Preserve command line compatibility and non destructive defaults.
5. Run focused syntax, JSON, dry run, or unit validation.

## Practical application

- A new extension belongs in `config/extensions.json`, not hardcoded in both installers.
- A new MCP capability beyond the reviewed baseline needs an opt in flag, documented auth requirements, and safe rollback behavior.
- A change to state data requires an uninstall compatibility check.

## Prerequisites

- Relevant runtime is installed: PowerShell for Windows validation, Bash for macOS or Linux validation.
- Read the existing config and tests before editing.

## Productivity benefit

Small diffs reduce installation regressions, make review faster, and preserve users’ existing VS Code configuration.
