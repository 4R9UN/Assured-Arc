---
name: assured-arc-repository-onboarding
description: "Use when onboarding a developer to this Assured Arc package, choosing install options, customizing extensions, agents, skills, vault templates, or MCP examples."
---

# Assured Arc Repository Onboarding

## Capability

Guides a user from a safe dry run to a customized installation without exposing secrets or overwriting personal configuration.

## Workflow

1. Identify operating system, VS Code channel, shell, and whether the user needs an existing vault or a new template vault.
2. Review `config/assured-arc.example.json` and select only the desired optional components.
3. Run installer dry run before any mutation.
4. Install, validate the state file, and use the uninstall command if rollback is requested.
5. Open the vault Home note and confirm the selected agents and skills appear in VS Code.

## Practical application

Use when a team member wants only AI agents and skills, or wants agents, skills, a vault template, extensions, and optional MCP configuration.

## Prerequisites

- Supported VS Code build with the `code` command on PATH for extension installation.
- PowerShell 7 or Windows PowerShell on Windows, Bash and Python 3 on macOS or Linux.

## Productivity benefit

Avoids manual copy paste setup and makes environment configuration repeatable across machines and teams.
