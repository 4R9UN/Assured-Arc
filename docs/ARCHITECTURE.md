# Architecture

## Design principles

- Public safe templates only
- Manifest driven configuration
- Idempotent installation
- Focused defaults with explicit opt out for network research tools
- Backup and rollback before mutation
- Standard Markdown for durable project context
- Evidence before runtime or topology complexity

## Visual map

[![Animated architecture map of Assured Arc v1.1.0](assets/assured-arc-architecture.gif)](assets/assured-arc-architecture.svg)

The animation reveals the dual-host entry surfaces (VS Code, GitHub Copilot CLI, and Claude Code), the shared acceptance contract, lazy skill router, 7-phase bounded execution loop, 5 isolated disposable workers (`1 Writer`), human-gated policy hooks, and the external scoreboard verification gate. Open the [editable static SVG](assets/assured-arc-architecture.svg) for a motion-free vector diagram. The diagrams and ownership table below remain the precise structural reference. [Graph and Agent Alignment](GRAPH_ALIGNMENT.md) explains how the design maps to graph-agent research and why Agent-Graph is not a default dependency.

## Component relationship

```mermaid
flowchart TB
    Repo[Public Assured Arc repository]
    Repo --> Install[Install scripts]
    Repo --> Contract[Shared dual-host contract]
    Repo --> Config[Configuration manifests]
    Repo --> Agents[Custom agents]
    Repo --> Prompts[Reusable prompts]
    Repo --> Registry[Compact skill registry]
    Repo --> Harness[Native agent harness policy]
    Repo --> Scoreboard[Scoreboard runner & approved checks]
    Contract --> ClaudeAdapters[Rendered Claude Code adapters]
    Harness --> Workers[Disposable worker archetypes]
    Harness --> Hooks[Policy, human-gate & trace hooks]
    Hooks --> Scoreboard
    Registry --> Skills[Lazy-loaded agent skills]
    Repo --> Vault[Vault template]
    Repo --> MCP[MCP templates]

    Install --> UserSettings[VS Code user settings]
    Install --> CliProfile[Optional Copilot CLI profile]
    Install --> ClaudeProfile[Managed Claude adapter root]
    Install --> UserLocations[VS Code customization locations]
    Install --> CopilotProfile[Managed customization root]
    Install --> State[Managed state v4 & backups]
    Install --> OptionalVault[Developer vault]
    Install --> ResearchMcp[User research MCP config]

    UserLocations --> Agents
    UserLocations --> Prompts
    UserLocations --> Skills
    UserLocations --> Hooks
    CliProfile --> Agents
    CliProfile --> Skills
    CliProfile --> Hooks
    ClaudeProfile --> ClaudeAdapters
    ClaudeProfile --> Hooks
    CopilotProfile --> Scoreboard
    Agents --> Harness
    Harness --> Registry
    CopilotProfile --> Skills
    OptionalVault --> Agents
    ResearchMcp --> Agents
```

## Daily execution boundary

```mermaid
flowchart LR
    Request[User objective in VS Code, CLI, or Claude] --> Coordinator[Orchestrator read search agent]
    Coordinator --> Scout[Read-only scout]
    Coordinator --> Research[Read-only web & MCP researcher]
    Coordinator --> Writer[Single implementation writer]
    Coordinator --> Critic[Read-only critic]
    Writer --> Verify[Independent verifier]
    Writer --> StopGate[Stop hook scoreboard gate]
    StopGate --> Scoreboard[scripts/scoreboard.py + nonce receipt]
    Scoreboard --> Coordinator
    Verify --> Coordinator
    Scout --> Coordinator
    Research --> Coordinator
    Critic --> Coordinator
    Hooks[Deterministic human-gate hooks] --> Coordinator
    Hooks --> Writer
```

Delegation depth is one. Workers cannot spawn workers. Remote research is separated from the writer, the coordinator cannot edit or execute directly, and completion after any file edit requires a passing nonce-verified receipt from `scripts/scoreboard.py`.

## Installer state lifecycle

```mermaid
stateDiagram-v2
    [*] --> DryRun
    DryRun --> Validated: prerequisites pass
    Validated --> BackedUp: user accepts install
    BackedUp --> Installed: managed assets copied
    Installed --> Verified: validation complete
    Installed --> RolledBack: failure during install
    Verified --> Uninstalled: uninstall invoked
    RolledBack --> [*]
    Uninstalled --> [*]
```

## Configuration ownership

| Component | Source of truth | Installer behavior |
| --- | --- | --- |
| Extensions | `config/extensions.json` | Installs IDs through VS Code command |
| User settings | `config/user-settings.json` | Merges missing keys by default |
| Shared contract | `config/agent-contract.json` | Renders `.claude` adapters via `scripts/render_contract.py` and copies contract to `<profile-root>/claude/agent-contract.json` |
| Claude adapters | `scripts/render_contract.py` | Renders 6 role agents and hook settings into `<profile-root>/claude` |
| Agents | `.github/agents` | Copies package owned files only |
| Reusable prompts | `.github/prompts` | Copies package owned prompt files into the managed profile |
| Skill routing | `config/skill-registry.json` | Copies the package catalog without replacing the personal catalog |
| Skills | `.github/skills` | Copies package owned folders into the managed profile only |
| Instructions | `.github/instructions` | Copies the two repository neutral global instructions |
| Harness policy | `config/agent-harness.json` | Renders package registry and skill paths into the managed profile |
| Scoreboard gate | `config/scoreboard.json`, `scripts/scoreboard.py`, `config/checks/` | Copies scoreboard manifest, runner, and approved checks into the managed profile |
| Hooks | `.github/hooks` and `hooks` | Renders platform commands, scoreboard environment variables, and local trace paths into the managed profile |
| Evaluation | `config/harness-evaluation-fixtures.json` and `tests/harness_evaluator.py` | Replays deterministic behavior and regression contracts |
| Vault | `vault-template` | Creates missing files only |
| MCP inventory | `config/mcp-servers.json` | Pins reviewed identities and local versions |
| Windows entry point | `install.ps1` | Delegates to the tested internal PowerShell lifecycle implementation |
| MCP configuration | `mcp/mcp.json.example` | Merges Context7, Sequential Thinking, and arXiv by default and prepares the managed arXiv runtime |
| Copilot CLI MCP configuration | `mcp/copilot-cli.mcp.json.example` | Uses the CLI-native `mcpServers` schema and separately tracked ownership |
| Copilot CLI profile | `~/.copilot` or `COPILOT_HOME` | Explicit opt in for agents, instructions, hooks, skill-directory registration, and MCP |
| Rollback | `<profile-root>/state.json` | Preserves first-run backups across upgrades, removes owned MCP and Claude entries, and can restore complete originals |
