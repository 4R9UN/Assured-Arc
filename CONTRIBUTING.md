# Contributing

Thank you for improving Assured Arc.

## Before contributing

- Read [README.md](README.md), [SECURITY.md](SECURITY.md), and the repository instructions.
- Never include credentials, personal paths, internal endpoints, customer data, session transcripts, or proprietary configuration.
- Keep changes portable across Windows, macOS, and Linux when the component claims cross platform support.

## Development workflow

1. Run the appropriate dry run installer.
2. Make the smallest focused change.
3. Run `pwsh -File tests/validate.ps1` and `bash tests/validate.sh` where available.
4. Update README and relevant documentation when behavior, config, or architecture changes.
5. Explain testing and limitations in the pull request.

## Pull request expectations

- One purpose per pull request.
- No unrelated formatting or generated files.
- New extension, agent, skill, or MCP template includes a clear purpose, safety boundary, and prerequisites.
- New MCP content must use least privilege and contain no secrets.
- Installer changes preserve idempotency, dry run behavior, backup, and uninstall compatibility.

## Reporting problems

Use GitHub Issues for bugs, documentation gaps, and enhancement proposals. Use the security reporting process for vulnerabilities.
