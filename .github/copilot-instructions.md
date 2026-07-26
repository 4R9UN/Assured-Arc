# Public Assured Arc Repository Instructions

This repository contains the public, portable Assured Arc configuration package.

- Never add personal paths, tenant identifiers, internal repositories, credentials, API keys, session transcripts, or private MCP endpoints.
- Keep all examples generic and use placeholders such as `${env:MY_TOKEN}` instead of secrets.
- Installer changes must be idempotent, dry run capable, and reversible through the state file and uninstall scripts.
- Preserve a user’s existing VS Code settings by merging missing defaults unless they explicitly request force replacement.
- For code changes, use the `assured-arc-development-quality` skill and run the narrowest meaningful validation.
- Do not publish releases, create remote repositories, or send telemetry without explicit user approval.
