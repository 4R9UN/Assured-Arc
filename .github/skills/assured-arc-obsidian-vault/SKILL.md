---
name: assured-arc-obsidian-vault
description: "Use when creating, configuring, or extending the portable Obsidian vault template, project notes, MOCs, templates, local-only notes, or VS Code workspace integration."
---

# Assured Arc Obsidian Vault

## Capability

Creates a portable knowledge vault that supports project documentation and agent context without storing sensitive data in public templates.

## Workflow

1. Create or select the destination vault through the installer.
2. Keep reusable notes under version control and private material under `local-only/`.
3. Use provided MOCs and project templates to connect work through wikilinks.
4. Use the generated workspace file to open source code and vault together in VS Code.
5. Validate Markdown links and JSON or YAML templates after structural changes.

## Practical application

- Create project architecture notes from `_templates/project.md`.
- Store reusable engineering decisions in `MOCs/Engineering.md`.
- Keep screenshots, tokens, private data, and raw logs in `local-only/`.

## Prerequisites

- Obsidian is optional. The vault remains standard Markdown if Obsidian is not installed.
- VS Code Markdown support is sufficient for basic editing.

## Productivity benefit

Provides durable, linked project memory that agents can use without relying on chat history alone.
