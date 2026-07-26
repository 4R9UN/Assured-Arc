# Obsidian Vault Integration

## Goal

The vault template provides durable, linked Markdown context for a project. It is intentionally tool neutral: it works in VS Code alone, and gains graph, search, Bases, Canvas, and plugin capabilities when opened in Obsidian.

## Structure

| Path | Purpose |
| --- | --- |
| `Home.md` | Entry point and workflow overview |
| `MOCs/` | Maps of content for projects, engineering, agents, skills, and MCP tools |
| `_templates/` | Reusable project note structure |
| `local-only/` | Excluded private data boundary |

## Workspace integration

The installer creates `assured-arc.code-workspace` inside the vault. Open it in VS Code to work on notes and add source folders as needed.

## Development workflow

1. Create a project note from the template.
2. Write measurable success criteria.
3. Link architecture, decisions, tests, and runbooks.
4. List which agents, skills, and MCP tools were used.
5. Store raw private artifacts only in `local-only/`.

## Synchronization options

This public template does not configure cloud sync automatically. Choose a provider appropriate for your organization, such as Git for sanitized notes, Obsidian Sync, a private drive, or a managed repository.

Never synchronize secrets, credentials, customer data, raw production logs, or private conversation exports through the public vault structure.