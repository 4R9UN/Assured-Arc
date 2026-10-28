# Troubleshooting

## Installer fails before changing files

Run a dry run first and resolve the named prerequisite.

```powershell
.\install.ps1 -DryRun
```

```bash
bash install/assured-arc.sh --dry-run
```

## VS Code command unavailable

Use the VS Code Command Palette and install the `code` command in PATH, then restart the terminal. You can still install agents, skills, instructions, and a vault with extensions skipped.

## JSON merge error

The installer backs up the target configuration before writing it. Check the backup folder under the profile root. If a custom settings file contains malformed JSONC, fix it manually or use `-SkipExtensions` while resolving configuration.

## Symbolic link or junction target refused

The installer does not write through linked settings, prompt, instruction, skill, or MCP targets because rollback could restore the link without restoring its referent. Apply the package manually to the link’s source repository, or replace the link only after making an independent backup.

## MCP server does not start

Check Node.js 18 or newer with `npx`, plus `uv` and Python 3.11 or newer. Then inspect the failing server separately:

- Context7: verify HTTPS access to `mcp.context7.com`.
- Sequential Thinking: verify `npx` can resolve the pinned package.
- arXiv: verify the managed executable under `<profile-root>/mcp/arxiv/bin` and network access.

Use `-SkipMcp` or `--skip-mcp` to install the remaining package without MCP.

Use uninstall with backup restoration when the pre-install MCP configuration should be restored.

## Agents, prompts, or skills do not appear

For VS Code, restart the editor, run **Chat: Open Customizations**, and inspect Chat diagnostics. Verify package assets and the registered discovery locations.

For Copilot CLI, personal installation requires `-InstallCopilotCli` or `--install-copilot-cli`. Restart the CLI, then use `/agent`, `copilot --agent assured-arc-orchestrator`, `copilot skill list`, and `/instructions`. Agents and modular instructions are stored under the selected Copilot home. Skills remain under the package profile and are registered through `skillDirectories` rather than copied over personal skills.

Existing personal skills under `~/.copilot/skills` are separate and should remain visible. The package does not replace that directory or the personal compact registry.

## Disposable workers do not start

Confirm `chat.customAgentInSubagent.enabled` is true and `chat.subagents.allowInvocationsFromSubagents` is false. The orchestrator must include the `agent` tool and explicitly list all five disposable worker names. Workers intentionally use `disable-model-invocation: true`; the explicit coordinator allowlist overrides that protection.

## Hook is not loaded

Open **Chat: Configure Hooks** and the GitHub Copilot Chat Hooks output channel. Confirm the rendered hook file is present under `<profile-root>/copilot/hooks/agent-harness.json` and its discovery entry exists in `chat.hookFilesLocations`.

Hooks are a preview capability and can be disabled by organization policy. When a hook command fails, run the installed PowerShell or Python script manually with a small JSON event over standard input. The command must return only valid JSON on standard output.

For Copilot CLI, confirm `<copilot-home>/hooks/assured-arc.json` exists and restart the CLI. CLI hooks use camelCase events and top-level decisions, while the VS Code template uses PascalCase events and VS Code-compatible output. Both are rendered from separate templates into the same policy scripts.

## Copilot CLI command unavailable

The installer never installs or upgrades Copilot CLI. Install it from the official GitHub instructions, confirm `copilot --version`, then rerun with `-InstallCopilotCli` or `--install-copilot-cli`. Omit that option to keep repository-level CLI compatibility without changing a personal CLI profile.

## Harness blocks a command or file edit

The `PreToolUse` hook evaluates human-gated paths first (`_human_gate_decision` / `Get-HumanGateDecision`), strictly denying writes to `.github/agents`, `.github/skills`, `.github/hooks`, `.claude/agents`, `.claude/settings.json`, `mcp.json`, `hooks/`, `scripts/`, `install/`, and `config/*` during daily work before fallback policies (`ask`). It asks before dependency installation, publishing, global configuration, destructive commands, and infrastructure changes. Set `ASSURED_ARC_HUMAN_GATE=open` only when intentionally performing human-reviewed harness evolution, or perform harness evolution in an isolated profile and worktree.

## Stop hook blocks completion after editing files

When an agent edits or creates a file (`Edit`, `Write`, `NotebookEdit`, `apply_patch`, etc.), `PostToolUse` marks the session `pendingVerification = true`. On `Stop`, the hook runs `scripts/scoreboard.py` against `config/scoreboard.json` with a one-time 32-hex `ASSURED_ARC_SCOREBOARD_NONCE`. Completion remains blocked (`continue: false` in VS Code / `decision: block` in Claude Code) until every approved check exits `0` and writes a matching `verification-receipt`. Model-written receipt files cannot clear this gate. Inspect the approved check scripts under `config/checks/` and fix any failing verification step.

## Rollback

Use the installer state file under the profile root. Dry run uninstall first, then explicitly restore backups only if you need pre-install settings returned.

```powershell
pwsh -File install/uninstall.ps1 -DryRun
pwsh -File install/uninstall.ps1 -RestoreBackups
```

```bash
bash install/uninstall.sh --dry-run
bash install/uninstall.sh --restore-backups
```
