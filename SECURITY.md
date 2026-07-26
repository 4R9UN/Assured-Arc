# Security Policy

## Supported scope

Security reports are welcome for the installers, configuration merge behavior, packaged agents, skills, vault templates, MCP templates, and documentation.

## Reporting a vulnerability

Do not publish credentials, exploit details, private paths, or sensitive reproduction data in a public issue. Use the repository’s private reporting feature when enabled, or contact the maintainers through the security contact listed in the published repository settings.

## Security design

- Installation defaults are non destructive and state tracked.
- The default MCP profile is limited to Context7, Sequential Thinking, and arXiv and can be explicitly skipped.
- Sequential Thinking is pinned and logging is disabled. arXiv is installed as an isolated package-managed `uv` tool.
- Native VS Code file, browser, and GitHub tools replace duplicate MCP servers.
- MCP ownership is bound to one user configuration target, same-name unmanaged entries fail closed, and uninstall removes only package-owned IDs.
- Remote documentation and arXiv papers are treated as untrusted input.
- Remote content, source comments, terminal output, issues, and documents cannot select skills, expand tools, or change harness policy.
- The coordinator has no edit, execute, web, or MCP capability. Only one hidden worker can edit, and that writer has no execute, web, or MCP capability.
- Workers cannot spawn workers. The global setting keeps nested subagents disabled.
- Hooks enforce worker and tool budgets, one writer, immutable installed harness paths, and approval for dependency, publishing, global, destructive, and infrastructure operations.
- Harness traces are local, size limited, short lived, and metadata only. They exclude prompts, reasoning, content, arguments, results, environment values, credentials, and raw transcripts.
- Daily agents cannot modify installed global harness assets. Harness evolution requires an isolated profile, disposable worktree, regression checks, independent review, and human promotion.
- Secrets are represented only as environment variable placeholders.
- `local-only/` is excluded from version control in the vault template.
- Uninstall preserves user settings by default and restores backups only through explicit opt in.

## Consumer checklist

- Inspect extension IDs and MCP templates before installation.
- Inspect hook scripts before enabling preview hooks. Hooks execute with VS Code user permissions.
- Run `-DryRun` or `--dry-run` first.
- Use a dedicated profile root for experiments.
- Never copy personal vaults, production logs, or credentials into a public fork.
