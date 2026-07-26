# Validation

Run the platform appropriate validation before publishing or changing installer behavior.

## Windows

```powershell
pwsh -File tests/validate.ps1
```

## macOS and Linux

```bash
bash tests/validate.sh
```

The tests are intentionally non destructive and use temporary profiles. They validate required structure, script syntax, JSON, agent and skill metadata, coordinator and worker capability contracts, one writer, worker and tool budgets, approval decisions, trace redaction, managed customization discovery, install, repeat install, rollback, uninstall, settings cleanup, MCP ownership, and public safety.

The MCP lifecycle uses local no network fixtures. The suites do not install real extensions, create a real user vault, launch production MCP servers, or modify the active VS Code profile.
