# Customization Guide

## Extensions

Edit `config/extensions.json` to add or remove extension IDs. Keep each extension’s purpose and whether it is required. Review marketplace publisher, permissions, license, and maintenance before adding it.

## Settings

Edit `config/user-settings.json` for safe defaults. The installer adds missing keys by default and dynamically injects `~/` customization locations when the managed profile is under the user home directory. Keep location maps empty in the template so public files remain portable. Use the force settings option only when an organization intentionally standardizes a value.

## Agents

Add `.agent.md` files under `.github/agents/`. Each agent needs a name, trigger rich description, cross-host tool aliases, clear role, interaction model, and safety boundary. Without `target`, the same profile is eligible in VS Code and Copilot CLI.

For disposable workers, set `user-invocable: false`, `disable-model-invocation: true`, and `agents: []`. Add the exact worker name to the orchestrator allowlist. Explicit allowlisting lets only that coordinator invoke the protected worker. Preserve one writer and do not give web or MCP tools to the implementation worker.

## Reusable prompts

Add `.prompt.md` files under `.github/prompts/`. Keep each prompt task specific, provide `name`, `description`, `argument-hint`, and `agent` frontmatter, and reference a packaged agent instead of duplicating global policy. Prompt files are a VS Code surface. For Copilot CLI, expose the reusable behavior through a custom agent or skill instead.

## Skills

Add a folder under `.github/skills/<skill-name>/SKILL.md`. The `name` must match the folder. Explain capability, workflow, prerequisites, practical use, and measurable developer benefit. Add the same ID, category, purpose, and precise trigger phrases to `config/skill-registry.json`. Validation fails when registry IDs and skill folders differ.

## Harness policy, dual-host contract, and scoreboard

Edit `config/agent-harness.json` or `config/agent-contract.json` only when a verified requirement changes worker, tool, repair, context, trace, or evolution budgets. When updating `config/agent-contract.json`, re-render the repository Claude Code adapters with `scripts/render_contract.py`:

```powershell
python scripts/render_contract.py `
  --contract config/agent-contract.json `
  --destination .claude `
  --command "python hooks/harness_event.py" `
  --env ASSURED_ARC_HARNESS_HOST=claude `
  --env ASSURED_ARC_HARNESS_CONFIG=config/agent-harness.json `
  --env ASSURED_ARC_HARNESS_TRACE_DIR=.assured-arc/harness-runs `
  --env ASSURED_ARC_HARNESS_TOOL_POLICY=config/tool-policy.json `
  --env ASSURED_ARC_SCOREBOARD=config/scoreboard.json `
  --env ASSURED_ARC_SCOREBOARD_SCRIPT=scripts/scoreboard.py `
  --env ASSURED_ARC_SCOREBOARD_ROOT=config
```

Approved post-write verification checks live in `config/scoreboard.json` and `config/checks/*.py`. Each check must use `python` or `python3` with a relative script inside the allowed scoreboard root and literal safe tokens. Agents cannot modify `config/scoreboard.json` or `config/checks/*` during on-task runs because those paths are human-gated (`ASSURED_ARC_HUMAN_GATE=open` required).

Update executable fixtures in `config/harness-evaluation-fixtures.json` and deterministic tests (`tests/harness_contracts.py` and `tests/harness_evaluator.py`) in the same change.

Harness evolution proposals must record repeated failure evidence, root cause, targeted fix, regression risk, and verification results. Evaluate proposals in an isolated profile and disposable worktree. Do not add automatic global promotion.

## Hooks

The VS Code hook template is `.github/hooks/agent-harness.json.example`. The Copilot CLI user-hook template is `.github/hooks/copilot-cli-harness.json.example`. Claude Code hook settings are rendered into `.claude/settings.json` and `<profile-root>/claude/settings.json`. Cross-platform implementations live under `hooks/`. The installer renders host-native event names, commands, scoreboard environment variables (`ASSURED_ARC_SCOREBOARD`, `ASSURED_ARC_SCOREBOARD_SCRIPT`, `ASSURED_ARC_SCOREBOARD_ROOT`), and output contracts.

Hook scripts must validate JSON input, evaluate human-gated path restrictions before fallback policies, enforce external scoreboard verification on `Stop` after any file write, write only valid JSON to standard output, run quickly, avoid network access, and never log prompt text, reasoning, file content, tool arguments, results, environment values, or secrets. Add equivalent behavior to both PowerShell and Python implementations and extend the harness contract tests.

## Vault

Extend `vault-template/` with generic MOCs and templates. Never package a personal vault. Keep private content under `local-only/`, which is ignored.

## MCP

Create secret-free VS Code and Copilot CLI templates under `mcp/` and add reviewed metadata to `config/mcp-servers.json`. Keep both templates semantically aligned while preserving each host’s schema. Document transport, endpoint, permitted tools, authentication source, runtime prerequisites, validation, and rollback. Any server beyond the reviewed Context7, Sequential Thinking, and arXiv baseline must remain opt in.
