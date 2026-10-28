# Assured Arc

[![Validate](https://github.com/4R9UN/Assured-Arc/actions/workflows/validate.yml/badge.svg)](https://github.com/4R9UN/Assured-Arc/actions/workflows/validate.yml)
[![Release](https://img.shields.io/badge/release-v1.1.0-0284C7?style=flat-square&logo=github)](https://github.com/4R9UN/Assured-Arc/releases/tag/v1.1.0)
[![Hosts](https://img.shields.io/badge/hosts-VS%20Code%20%7C%20Copilot%20CLI%20%7C%20Claude%20Code-9333EA?style=flat-square)](#at-a-glance)
[![Agents](https://img.shields.io/badge/agents-7%20Visible%20%2B%205%20Disposable%20%2B%206%20Claude-38BDF8?style=flat-square)](docs/AGENTS.md)
[![Skills](https://img.shields.io/badge/skills-28%20Lazy--Loaded-10B981?style=flat-square)](docs/SKILLS.md)
[![Web Research](https://img.shields.io/badge/web%20research-Live%20Surfing%20%2B%20Context7%20%2B%20arXiv-A855F7?style=flat-square)](docs/SKILLS.md#assured-arc-web-research)
[![Governance](https://img.shields.io/badge/governance-Single--Writer%20%2B%20Scoreboard%20Gate-059669?style=flat-square)](docs/HARNESS.md)
[![Human Gate](https://img.shields.io/badge/human%20gate-Protected%20Control%20Plane-E11D48?style=flat-square)](docs/HARNESS.md)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-475569?style=flat-square)](docs/INSTALLATION.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-F59E0B?style=flat-square)](LICENSE)

> A public, safety-first workbench for repeatable AI engineering workflows across **VS Code**, **GitHub Copilot CLI**, and **Claude Code**—featuring a shared dual-host agent contract, disposable subagents, lazy-loaded skills, deterministic human-gated hooks, external scoreboard verification, optional Obsidian knowledge management, and reviewed research MCP tools.

## Short description

**Assured Arc** (`v1.1.0`) creates a consistent, auditable agentic development environment across **VS Code**, **GitHub Copilot CLI**, and **Claude Code**. A single canonical contract (`config/agent-contract.json`) governs bounded agent roles, while repository agents and skills work natively across hosts. One reversible installer configures the VS Code experience, renders native Claude Code adapters (`<profile-root>/claude`), wires external scoreboard verification hooks (`scripts/scoreboard.py`), and can optionally add the same agents, skills, instructions, hooks, and reviewed MCP tools to a personal Copilot CLI profile without copying secrets or replacing unrelated configuration.

It is built for developers, engineering teams, workshops, and maintainers who need predictable, high-assurance AI-assisted workflows across machines while retaining dry-run preview, backup, checksum-verified state tracking, customization, and surgical uninstall support.

## What's new in v1.1.0

- **Shared Dual-Host Contract (`config/agent-contract.json` + `scripts/render_contract.py`)**: One canonical JSON contract (`v1.1.0`) defines role capabilities, delegation depth (`1`), single-writer concurrency (`1`), parallel worker limits (`3`), skill budgets (`3`), and repair limits (`2`), rendering native Claude Code adapters (`.claude/agents/*.md`, `.claude/settings.json`) without copying Copilot agent files.
- **External Scoreboard Verification Gate (`scripts/scoreboard.py` + `config/scoreboard.json`)**: Verify-after-write is enforced by deterministic hooks rather than prompt instructions. Any file write sets `pendingVerification = true`, blocking `Stop` completion until `scripts/scoreboard.py` executes approved checks (`config/checks/approved_check.py`) and writes a session- and cryptographic `verificationNonce`-matched `verification-receipt`.
- **Strict Human-Gated Path Precedence**: `PreToolUse` hooks (`hooks/harness_event.py` and `hooks/harness-event.ps1`) evaluate human-gated boundaries first, strictly denying on-task edits to `.github/agents`, `.github/skills`, `.github/hooks`, `.claude/agents`, `.claude/settings.json`, `mcp.json`, `hooks/`, `scripts/`, `install/`, and `config/*` before fallback policies (`ask`) unless `ASSURED_ARC_HUMAN_GATE=open` is set by a human.
- **Web Research & Surfing Skill (`assured-arc-web-research`)**: Added a portable skill for live web search (`web`, `WebSearch`), primary URL fetching (`WebFetch`, `fetch_webpage`), source provenance, and untrusted web content quarantine.

## At a glance

| Area | Included capability |
| --- | --- |
| **Version** | `v1.1.0` ([CHANGELOG.md](CHANGELOG.md)) |
| **Installation** | One Windows entry point (`install.ps1`), cross-platform internal installers (`install/assured-arc.*`), dry run, backup, rollback, `doctor`, legacy migration planner, repeat install, and surgical uninstall |
| **Agents** | 7 visible Copilot specialists, 5 hidden disposable Copilot workers, and 6 contract-rendered Claude Code role adapters |
| **Hosts** | VS Code by default, native Claude Code adapter rendering (`.claude/` & `<profile-root>/claude`), plus explicit personal-profile opt-in for GitHub Copilot CLI |
| **Orchestration** | Native coordinator, single implementation writer, delegation depth `1`, up to `3` concurrent workers, external scoreboard verification, and bounded repair (`≤ 2`) |
| **Skills & prompts** | 28 portable lazy-loaded skills (`config/skill-registry.json`, including `assured-arc-web-research`) and 6 VS Code reusable slash-command prompts (`.github/prompts/*.prompt.md`) |
| **Verification gate** | Hook-enforced `scripts/scoreboard.py` + `config/scoreboard.json` with 32-hex cryptographic nonce receipts (`selfScoreAllowed: false`) |
| **Web & MCP research** | Host live web surfing (`web`, `WebSearch`, `WebFetch`), Context7 (HTTPS), Sequential Thinking `2026.7.4`, and isolated `uv`-managed arXiv MCP `0.5.1` |
| **Knowledge** | Optional portable Markdown and Obsidian vault template (`vault-template/`) |
| **Safety** | Strict human-gated path precedence, least-privilege tool scopes, state SHA-256 integrity, metadata-only traces, public safety checks, and explicit approval boundaries |

## Problem statement

Modern GitHub Copilot workflows depend on custom agents, skills, instructions, hooks, MCP servers, IDE settings, CLI settings, and local knowledge. Configuring these pieces independently creates several recurring problems:

- Machines drift because each component is installed and updated differently.
- Agent prompts grow large because every workflow is loaded instead of selecting relevant skills lazily.
- Broad tool access lets research, implementation, and verification responsibilities overlap.
- Multiple agents can edit concurrently, producing conflicting changes and unclear ownership.
- MCP tools can duplicate native host capabilities or introduce unnecessary file, network, and credential exposure.
- Installers that overwrite user settings or cannot roll back make experimentation risky.
- Personal paths, secrets, internal endpoints, and raw transcripts can accidentally leak into shared configuration.

## Proposed solution

The repository provides a manifest-driven, dual-host agent harness and a reversible installer. It uses a canonical bounded-task contract (`config/agent-contract.json`), portable custom agents, disposable subagents, lazy-loaded skills, and deterministic hooks across GitHub Copilot (VS Code & CLI) and Claude Code rather than adding an external orchestration service or background daemon. VS Code prompt files remain an IDE-specific convenience.

The solution follows this execution model:

1. Convert the user request into explicit acceptance criteria and stopping conditions under the shared contract.
2. Select no more than three relevant domain skills from compact registries (`config/skill-registry.json`).
3. Complete simple read-only work directly or delegate focused tasks to context-isolated disposable workers.
4. Allow only one implementation writer (`Implementer`) and keep remote web/MCP research strictly separated from editing.
5. Enforce external verification after every file write via the `Stop` hook and `scripts/scoreboard.py`, permitting at most two evidence-driven repairs.
6. Deny on-task mutations to harness, agent, skill, hook, MCP, and permission files unless a human opens `ASSURED_ARC_HUMAN_GATE=open`.
7. Record package ownership with SHA-256 state verification so upgrades and uninstall affect only package-managed assets.

This repository provides a manifest-driven setup with safe defaults:

- Copies generic, public-safe AI agents, skills, and instructions into supported VS Code and optional Copilot CLI locations, and renders native Claude Code adapters from `config/agent-contract.json`.
- Backs up affected VS Code, Copilot CLI, and Claude adapter configuration before changing it.
- Merges missing settings rather than replacing user settings by default.
- Installs recommended extensions through VS Code unless explicitly skipped.
- Creates an optional Markdown-first Obsidian vault template.
- Installs the reviewed Context7, Sequential Thinking, and arXiv MCP profile by default, with an explicit opt-out.
- Installs the external scoreboard runner (`scripts/scoreboard.py`) and approved check suite (`config/scoreboard.json`).
- Records installation state (`schema: 4`) for health checks (`doctor`), rollback, and surgical uninstall.
- Installs a bounded native agent harness with disposable subagents, one writer, nonce-verified scoreboard gates, and metadata-only local traces.

> [!warning]
> This is a starter kit, not a copy of anyone’s personal configuration. Do not commit credentials, customer data, internal URLs, private vault content, raw chat transcripts, or organization specific MCP endpoints.

## Capabilities

| Capability | What it provides | Key boundary |
| --- | --- | --- |
| **Safe installation** | Install profiles (`Minimal`, `Research`, `Full`, `CopilotCli`), merged settings, state SHA-256 checksum, backups, `doctor`, rollback, and uninstall | Existing unrelated settings and MCP entries are preserved |
| **Dual-host contract** | Canonical `config/agent-contract.json` rendered into Claude Code adapters (`.claude/agents/*.md`, `.claude/settings.json`) alongside Copilot | Never copies Copilot agent files into Claude; forbids runtime agent/skill invention |
| **Native orchestration** | Coordinator plus Scout, Researcher, Implementer, Verifier, and Critic workers | Delegation depth `1`, `1` active writer, `≤ 3` parallel workers, and no nested subagents |
| **Context-efficient skills** | Compact registry selects up to `3` domain skills, with Development Quality added for code changes | The full 28-skill library is never injected into every prompt |
| **Scoreboard verification gate** | Hook-driven `scripts/scoreboard.py` runs approved checks (`config/scoreboard.json`) after any file edit | `Stop` hook blocks completion until a session- and nonce-matched receipt passes; no self-scoring |
| **Web & research tooling** | Live web surfing (`assured-arc-web-research`), current library docs (Context7), structured analysis (Sequential Thinking), and paper search (arXiv) | Web and MCP tools are available to read-only researchers, never to the implementation writer |
| **Deterministic policy hooks** | Strict human-gated path precedence, worker/tool budgets, approval checks, and metadata-only traces | Traces and run receipts exclude prompts, reasoning, file contents, arguments, results, and secrets |
| **Durable project context** | Optional Markdown and Obsidian vault with MOCs and project templates | Private artifacts stay under `local-only/` |
| **Public package safety** | Generic examples, secret-free templates, and automated public-safety scans | No tenant data, personal paths, internal URLs, or private MCP endpoints |

## Architecture

[![Assured Arc Architecture](docs/assets/assured-arc-architecture.gif)](docs/assets/assured-arc-architecture.svg)

See [Graph and Agent Alignment](docs/GRAPH_ALIGNMENT.md) for the arXiv research comparison and why a separate graph runtime is not required.

```mermaid
flowchart LR
    U[Developer] --> I[Cross-platform installer]
    I --> B[Backup & state ledger v4]
    I --> VS[VS Code user profile]
    I --> CLI[Optional Copilot CLI profile]
    I --> CL[Rendered Claude adapters]
    I --> CP[Managed package profile]
    I --> V[Optional Obsidian vault]
    I --> M[Research MCP configuration]

    VS --> E[Extensions]
    VS --> A[Custom agents & 6 slash prompts]
    CLI --> A
    CLI --> HK[Deterministic policy hooks]
    CL --> HK
    CP --> SC[External scoreboard & checks]
    CP --> SR[Compact skill registry]
    SR --> S[28 lazy-loaded portable skills]
    CP --> IN[Targeted global instructions]
    V --> K[Project knowledge & MOCs]
    M --> T[Least-privilege MCP tools]

    A --> H[Bounded coordinator & disposable workers]
    CL --> H
    H --> SR
    H --> HK
    HK --> SC
    A --> IN
    A --> K
    A --> T

    B --> R[Doctor, rollback & surgical uninstall]
```

### Installation to daily usage

```mermaid
flowchart TD
    A[Clone or download repository] --> B[Run dry run]
    B --> C{Prerequisites pass?}
    C -->|No| D[Fix host, shell, Node, Python, or uv requirement]
    D --> B
    C -->|Yes| E[Run installer]
    E --> F[Backup and copy managed assets]
    F --> G[VS Code, optional CLI, vault, and research MCP profile]
    G --> H[State file recorded]
    H --> I[Restart VS Code or Copilot CLI]
    I --> J[Choose an agent or invoke a skill]
    J --> K[Route skills and disposable workers]
    K --> M[Verify and repair within budgets]
    M --> L[Run validation or uninstall]
```

### Agent context and data flow

[![Agent and Harness Data Flow](docs/assets/assured-arc-harness-architecture.gif)](docs/assets/assured-arc-harness-architecture.svg)

```mermaid
flowchart LR
    Q[Developer request] --> R[Agent routing]
    R --> G[Development quality gate]
    R --> D[Domain skill]
    R --> V[Vault project context]
    R --> M[Research MCP tool]

    V --> P[Sanitized project notes]
    M --> X[Scoped external or local capability]
    G --> C[Minimal implementation and verification]
    D --> C
    P --> C
    X --> C
    C --> O[Verified change or documented recommendation]
```

## Quick start

### Prerequisites

| Platform | Required for the default installation |
| --- | --- |
| Windows | VS Code, PowerShell, Node.js 18 or newer with `npx`, `uv`, and Python 3.11 or newer |
| macOS or Linux | VS Code, Bash, Python 3, Node.js 18 or newer with `npx`, and `uv` with Python 3.11 or newer |

The VS Code `code` command is required only when extension installation is enabled. Obsidian is optional because the generated vault remains standard Markdown.

Clone the repository, inspect the dry run, then run the installer.

### Windows

```powershell
git clone https://github.com/<your-org>/assured-arc.git
Set-Location assured-arc
.\install.ps1 -DryRun
.\install.ps1
.\install.ps1 -InstallCopilotCli
```

### macOS and Linux

```bash
git clone https://github.com/<your-org>/assured-arc.git
cd assured-arc
bash install/assured-arc.sh --dry-run
bash install/assured-arc.sh
bash install/assured-arc.sh --install-copilot-cli
```

The default install creates `~/.assured-arc` for state (`state.json`), backups, managed skills, hooks, scoreboard checks (`scoreboard.json`, `scoreboard.py`, `checks/approved_check.py`), rendered Claude Code adapters (`~/.assured-arc/claude`), the arXiv runtime, and the optional vault. `-InstallCopilotCli` or `--install-copilot-cli` additionally uses the native Copilot home, normally `~/.copilot`, for agents, instructions, user hooks, settings registration, and CLI MCP configuration. Existing VS Code and CLI settings and unrelated MCP entries are merged, not replaced.

### Confirm installation

After installation, restart or reload the selected hosts, then verify:

1. **Assured Arc Orchestrator** appears in the agent picker.
2. The **six** package prompts appear in the VS Code slash-command menu.
3. Context7, Sequential Thinking, and arXiv appear under **MCP: List Servers**.
4. The state file exists under `~/.assured-arc/state.json` and `pwsh -File install/doctor.ps1` (or `bash install/doctor.sh`) reports `PASS`.
5. Rendered Claude Code adapters exist under `~/.assured-arc/claude/agents` and `~/.assured-arc/claude/settings.json` (as well as `.claude/` in the repository).
6. Chat customization diagnostics show no errors for package agents, prompts, skills, or hooks.

For Copilot CLI integration, also verify:

1. Run `copilot --agent assured-arc-orchestrator` or select the agent with `/agent`.
2. Run `copilot skill list` and confirm the packaged skills are listed from the managed directory.
3. Run `copilot mcp list` and confirm Context7, Sequential Thinking, and arXiv when MCP installation is enabled.
4. Restart Copilot CLI after hook or agent changes because those files load at session start.

## Installation options

| Need | PowerShell | Bash |
| --- | --- | --- |
| Preview all work | `-DryRun` | `--dry-run` |
| Select install profile (`Minimal`, `Research`, `Full`, `CopilotCli`) | `-Profile <Name>` | `--profile <Name>` |
| Install into the personal Copilot CLI profile | `-InstallCopilotCli` | `--install-copilot-cli` |
| Skip extensions | `-SkipExtensions` | `--skip-extensions` |
| Skip vault | `-SkipVault` | `--skip-vault` |
| Choose vault path | `-VaultPath <path>` | `--vault-path <path>` |
| Skip the default three-server MCP profile | `-SkipMcp` | `--skip-mcp` |
| Replace conflicting settings | `-ForceSettings` | `--force-settings` |
| Disable backups | `-NoBackup` | `--no-backup` |
| Run read-only health check | `pwsh -File install/doctor.ps1` | `bash install/doctor.sh` |
| Plan legacy profile migration | `pwsh -File install/migrate-legacy.ps1` | `bash install/migrate-legacy.sh` |

Copy [config/assured-arc.example.json](config/assured-arc.example.json) to a local, ignored location when you need repeatable customization. Do not store secrets in that file.

## Included AI agents

| Agent | Purpose | Typical use |
| --- | --- | --- |
| Assured Arc Orchestrator | Global coordinator with read, search, and subagent capabilities | Contract, route skills, delegate, verify, and synthesize |
| Assured Arc Development | Minimal, testable implementation work | Add a feature, fix a bug, refactor a focused component |
| Assured Arc Architecture | Minimum viable architecture and tradeoff analysis | Design boundaries, APIs, data flow, or major refactors |
| Assured Arc QA | Reproduction, test design, regression, and lifecycle validation | Validate bugs, implementations, installers, and rollback |
| Assured Arc Documentation | Accurate documentation and Mermaid diagrams | Update onboarding, architecture, examples, or guides |
| Assured Arc Research | Read only public dependency evaluation | Assess a VS Code extension, MCP server, or community skill |
| Assured Arc Security Review | Read only installation and configuration review | Review secrets, permissions, MCP scope, rollback, and release readiness |

Each agent has a dedicated [configuration file](.github/agents) with a clear purpose, cross-host tool aliases, reviewable handoff buttons (`send: false`), interaction model, and safety boundary. Repository copies are discovered by both VS Code and Copilot CLI. With personal CLI installation enabled, agents are copied to the CLI-native agent directory and VS Code points to the same source to avoid duplicate user-level definitions.

The orchestrator can instantiate five hidden disposable worker archetypes: **Scout**, **Researcher**, **Implementer**, **Verifier**, and **Critic**. Workers have isolated context, cannot spawn children (`agents: []`), and terminate after returning one focused result. Only the **Implementer** can edit files, and any file edit triggers the external scoreboard verification gate (`scripts/scoreboard.py`) on `Stop`.

For **Claude Code**, `scripts/render_contract.py` renders six native role adapters (`assured-arc-orchestrator`, `assured-arc-scout`, `assured-arc-researcher`, `assured-arc-implementer`, `assured-arc-verifier`, and `assured-arc-critic`) under `.claude/agents/` and `<profile-root>/claude/agents/` directly from `config/agent-contract.json`. See [docs/HARNESS.md](docs/HARNESS.md) and [docs/AGENTS.md](docs/AGENTS.md).

## Included reusable prompts

The package installs six short, user-invoked prompt files into its managed VS Code prompt directory. Copilot CLI does not consume `.prompt.md` files; invoke the corresponding agent or skill directly instead.

| Prompt | Purpose |
| --- | --- |
| `plan-implement-verify` | Route, implement, and validate a development request end to end |
| `research-and-decide` | Evaluate a dependency, technology, MCP server, extension, or architecture choice |
| `review-current-change` | Review the current diff for correctness, security, rollback, tests, and unnecessary complexity |
| `parallel-research-synthesize` | Run up to three independent read only evidence streams and synthesize one answer |
| `multi-agent-change-review` | Review a change through independent correctness, security, and reliability perspectives |
| `evolve-harness-safely` | Draft and evaluate an isolated harness change without global promotion |

Prompts reference packaged agents instead of duplicating their full policies. A concise general instruction applies evidence-first behavior, safe action boundaries, and focused verification to all packaged agents.

## Included skills

The package includes **28 curated skills**. The installed [skill registry](config/skill-registry.json) routes each request to no more than three domain skills. Code-changing tasks always add the Development Quality gate.

| Category | Skills | Why it matters |
| --- | --- | --- |
| Core | Skill Router, Development Quality, Repository Onboarding, Task Planning, Agent Orchestration, Context Efficiency | Select focused context, coordinate bounded workers, and reduce repeated tokens |
| Design | Architecture Design | Resolve boundaries and tradeoffs before expensive implementation |
| Implementation | Backend and API, Frontend and Accessibility, Python Quality, Data and SQL, Configuration Management | Apply stack-aware implementation guidance only when relevant |
| Quality | Debugging, Testing, Code Review, Performance and Reliability, Security and Privacy, Error Handling, Observability, Agent Evaluation, Ponytail | Find root causes, verify behavior, test loops, reduce defects, and remove unnecessary complexity |
| Delivery | Git and CI, Dependency Evaluation, Documentation Quality | Improve integration, supply-chain decisions, and developer onboarding |
| Platform | Web Research, MCP Safety, Obsidian Vault, Harness Evolution | Search the live web with prompt-injection quarantine, add reviewed MCP tools, maintain durable knowledge, and govern harness evolution |

Skills are lazy loaded by their descriptions and the registry. This keeps context focused instead of loading every workflow into each chat. See [docs/SKILLS.md](docs/SKILLS.md) for every skill’s capability, prerequisites, practical use, and productivity benefit.

Customize agents, skills, extension manifests, vault templates, and MCP templates through [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md).

## Obsidian vault integration

The optional [vault template](vault-template) is standard Markdown. It works without Obsidian, but becomes more navigable when opened in Obsidian.

```text
vault/
├── Home.md
├── MOCs/
│   ├── Projects.md
│   ├── Engineering.md
│   ├── Agents and Skills.md
│   └── MCP Tools.md
├── _templates/
│   └── Project Template.md
└── local-only/
    └── .gitkeep
```

- `Home.md` is the entry point.
- MOCs organize project, engineering, agent, skill, and MCP context.
- The project template records outcomes, validation, agents, skills, and MCP tools.
- `local-only/` is excluded from version control for screenshots, raw logs, secrets, and private artifacts.

See [docs/OBSIDIAN.md](docs/OBSIDIAN.md) for workflows and VS Code integration.

## MCP tools

The default VS Code [MCP template](mcp/mcp.json.example) and [Copilot CLI template](mcp/copilot-cli.mcp.json.example) contain the same three research tools with host-native top-level keys:

| Tool | Purpose | Boundary |
| --- | --- | --- |
| Context7 | Current, version-specific library and API documentation | Hosted HTTPS, requests leave the machine |
| Sequential Thinking | Structured analysis with revision and branching | Pinned npm package, thought logging disabled |
| arXiv | Academic paper search, download, and reading | Isolated `uv` tool, downloaded papers stored locally and treated as untrusted |

Native VS Code and Copilot CLI tools handle local files, shell work, and GitHub access, so duplicate MCP servers are intentionally excluded. Ponytail remains a lazy-loaded YAGNI skill rather than a second runtime.

```mermaid
flowchart LR
    A[Agent request] --> B{MCP configured and approved?}
    B -->|No| C[Use native host tools and local context]
    B -->|Yes| D[Scoped MCP server]
    D --> E[Validated response]
    E --> F[Agent result]
```

### MCP configuration principles

- Use local `stdio` for development and narrowly scoped file access.
- Use HTTPS for remote endpoints.
- Store tokens in environment variables or host secret stores, never in committed JSON.
- Review every community MCP server before enabling it.
- Keep a rollback path through the Assured Arc installation state file.

The profile requires Node.js 18 or newer with `npx`, plus `uv` and Python 3.11 or newer. Context7 and package installation require network access. The installer pins Sequential Thinking and installs arXiv into the package-managed profile.

See [docs/MCP.md](docs/MCP.md) for protocols, authentication patterns, endpoints, and troubleshooting.

## What the installer changes

| Location | Change | Default behavior |
| --- | --- | --- |
| VS Code user settings | Adds missing AI instruction discovery settings | Backs up, then merges defaults |
| Managed customization root | Adds agents, prompts, skills, instructions, harness policy, scoreboard config/checks, and hooks under `<profile-root>/copilot` | Does not overwrite existing personal skill or prompt libraries |
| Claude Code adapter root | Renders 6 contract-driven Claude agents, `settings.json` hooks, and `agent-contract.json` under `<profile-root>/claude` | Never copies Copilot agent files; removed cleanly on uninstall |
| VS Code customization locations | Adds exact managed agent, prompt, skill, instruction, and hook paths | Removes only package paths on uninstall |
| Copilot CLI personal profile | Optionally adds agents, modular instructions, a managed skill-directory entry, user hooks, and reviewed MCP entries | Explicit opt in, conflict checked, and removed by exact ownership |
| External scoreboard gate | Installs `scoreboard.json`, `scoreboard.py`, and `checks/approved_check.py` wired via `ASSURED_ARC_SCOREBOARD*` | Blocks `Stop` after any file write until nonce-verified checks exit `0` |
| Local harness traces | Writes size-limited metadata and atomic run/verification receipts under `<profile-root>/harness-runs` | Excludes prompts, content, arguments, results, and secrets |
| Extensions | Recognizes built-in Copilot Chat and installs missing manifest extensions without forcing replacement or downgrade | Enabled unless skipped |
| MCP user config | Adds three reviewed research servers and a managed arXiv runtime | Enabled unless skipped |
| Vault path | Creates missing template files | Enabled unless skipped |

## Usage examples

### Example: implement and verify a feature

Select **Assured Arc Orchestrator** or invoke `/plan-implement-verify`, then ask:

> Add validation for this configuration field, preserve backward compatibility, and add a regression test.

The harness inspects the repository, selects relevant skills, assigns one writer, runs an independent verifier, and returns changed files plus validation evidence.

### Example: research a current library API

Select **Assured Arc Research** or invoke `/research-and-decide`, then ask:

> Verify the current authentication API for this framework and recommend the smallest supported integration.

The research agent uses Context7 for current documentation, separates verified facts from assumptions, and does not edit or install the evaluated dependency.

### Example: research academic papers

Ask **Assured Arc Research**:

> Find recent arXiv papers about agent evaluation, compare their methodologies, and identify practical ideas for this harness.

The agent uses arXiv for paper discovery and treats downloaded paper text as untrusted external data.

### Example: analyze a complex design

Select **Assured Arc Orchestrator** and ask:

> Compare two deployment designs, identify trust and failure boundaries, select the minimum viable option, and define verification checkpoints.

The coordinator can use Sequential Thinking for revision and branching, parallel read-only workers for independent evidence, and a critic for unsupported assumptions.

### Example: review a change from several perspectives

Invoke `/multi-agent-change-review`:

> Review the current change for correctness, security, rollback safety, and unnecessary complexity.

Independent critics inspect distinct dimensions, then the coordinator deduplicates findings by root cause and severity.

### Example: use the simplest solution

Ask for the Ponytail skill explicitly:

> Use Ponytail mode to simplify this implementation and identify what can be deleted.

The skill prefers deletion, standard libraries, platform capabilities, and direct code over speculative abstractions.

### Example: install without optional components

```powershell
.\install.ps1 -SkipExtensions -SkipVault -SkipMcp
```

This installs only the VS Code-managed agents, prompts, skills, instructions, harness policy, and hooks. Add `-InstallCopilotCli` when the same pack should also be globally available in Copilot CLI.

## Real world scenarios

### Scenario: new laptop onboarding

A developer installs VS Code and runs the dry run. The installer finds the `code` command, shows the extension plan, backs up existing settings, adds agents and skills, and creates a vault at `~/.assured-arc/vault`.

### Scenario: team project knowledge

A team copies the vault template into a project repository. Each project note records ownership, success criteria, selected skills, and validation evidence. Private logs remain in `local-only/`.

### Scenario: safe MCP evaluation

A developer uses Assured Arc Research to examine a public MCP server. Assured Arc Security Review checks transport, authentication, scope, and data exposure before any capability beyond the reviewed baseline is added.

### Scenario: rollback after a bad setup

The installer state file records managed paths and backups. Run the uninstall script to remove package assets. Add `-RestoreBackups` or `--restore-backups` to restore the saved user configuration.

## Uninstall and rollback

If this machine has a profile created before the Assured Arc rebrand, uninstall that profile before installing Assured Arc. Run the uninstall script from the matching installed version, or pass the exact prior profile root explicitly. Do not copy or move its state file into `~/.assured-arc`.

### Uninstall on Windows

```powershell
pwsh -File install/uninstall.ps1 -DryRun
pwsh -File install/uninstall.ps1
pwsh -File install/uninstall.ps1 -RestoreBackups -RemoveExtensions -RemoveVault
```

### Uninstall on macOS and Linux

```bash
bash install/uninstall.sh --dry-run
bash install/uninstall.sh
bash install/uninstall.sh --restore-backups --remove-extensions --remove-vault
```

By default, uninstall removes managed agents, skills, prompts, instructions, hooks, scoreboard configs/checks, rendered Claude adapters, package-owned VS Code and Copilot CLI MCP entries, and the managed arXiv runtime. Existing host settings and unrelated MCP entries remain untouched. Backup restoration returns complete pre-install files when explicitly requested.

## Validation

```powershell
pwsh -File tests/validate.ps1
pwsh -File tests/public-safety.ps1
```

```bash
bash tests/validate.sh
```

Validation checks file structure, JSON, script syntax, dual-host contract parity, Claude adapter rendering, harness capability boundaries, human-gate path precedence, external scoreboard nonce receipts, hook budgets and redaction, the root installer, `doctor` and `migrate-legacy` read-only helpers, skill and prompt metadata, registry parity, installer lifecycle, rollback, settings cleanup, vault behavior, the exact three-server MCP inventory, and a no-network MCP fixture lifecycle.

## Troubleshooting

| Problem | Resolution |
| --- | --- |
| `code` command missing | Open VS Code Command Palette, run **Shell Command: Install 'code' command in PATH**, then restart the terminal. Or use `-SkipExtensions`. |
| PowerShell execution policy blocks scripts | Run with `pwsh -ExecutionPolicy Bypass -File .\install.ps1`. Review the script before using bypass. |
| Python 3 missing on macOS or Linux | Install Python 3, which the installer and hooks use for safe JSON merge, Claude contract rendering, scoreboard verification, and state generation. |
| Copilot CLI agent is missing | Restart the CLI, then use `/agent` or `copilot --agent assured-arc-orchestrator`. Confirm `-InstallCopilotCli` was used for personal availability. |
| Stop hook blocks completion after file edit | A write tool marked the session `pendingVerification`. Ensure approved checks in `config/scoreboard.json` pass when `Stop` runs `scripts/scoreboard.py`. |
| Hook denies editing `.github/*`, `.claude/*`, or `config/*` | Harness, skill, hook, MCP, and permission files are human-gated. Set `ASSURED_ARC_HUMAN_GATE=open` only when intentionally evolving the harness. |
| MCP profile does not start | Confirm Node.js 18+, `npx`, `uv`, and Python 3.11+, then inspect `MCP: List Servers` or `copilot mcp list`. |
| Existing settings look wrong | Run uninstall with backup restoration or manually restore a file from `<profile-root>/backups`. |
| Obsidian is not installed | The vault remains usable as Markdown. Install Obsidian later and open the generated vault folder. |

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed diagnostics.

## Repository layout

```text
.
├── install.ps1                # Single Windows installation entry point
├── CHANGELOG.md               # Release history and version notes
├── .claude/                   # Contract-rendered Claude Code agents and hook settings
├── .github/
│   ├── agents/                # Portable VS Code and Copilot CLI agents (7 visible + 5 workers)
│   ├── instructions/          # Targeted AI instructions
│   ├── prompts/               # 6 reusable VS Code slash-command prompt files
│   ├── hooks/                 # Portable hook configuration templates (VS Code & CLI)
│   └── skills/                # 28 lazy-loaded reusable workflows
├── config/                    # Shared contract, harness policy, scoreboard, and manifests
│   └── checks/                # Approved deterministic verification checks
├── docs/                      # Architecture, harness, MCP, skills, and troubleshooting guides
│   └── assets/                # Animated GIF and editable SVG architecture diagrams
├── hooks/                     # Cross-platform policy, human-gate, and trace hook scripts
├── install/                   # Cross-platform installers, uninstaller, doctor, and migration helpers
├── mcp/                       # Safe MCP templates for VS Code and Copilot CLI
├── scripts/                   # Contract renderer, scoreboard runner, and asset generator
├── tests/                     # Contract, trajectory, lifecycle, and public-safety suites
└── vault-template/            # Portable Obsidian-compatible Markdown vault
```

## Security model

This package is safe by default, not magical.

- Review every extension and MCP server before enabling it.
- Use the dry run on a new machine.
- Keep secret values outside tracked configuration.
- Treat downloaded skills and MCP config as code that requires review.
- Use the provided security review agent before public release or team wide rollout.
- Do not assume the installer can validate a cloud upload, remote MCP endpoint, or third party extension’s runtime behavior.

See [SECURITY.md](SECURITY.md) for reporting and hardening guidance.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request.
All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Contributors should:

1. Keep changes public safe and portable.
2. Add tests or validations for installer and config changes.
3. Preserve idempotency, backup, rollback, and dry run behavior.
4. Avoid adding a dependency when standard platform functionality is sufficient.
5. Update documentation and diagrams when architecture changes.

## License

This project is released under the [MIT License](LICENSE).

See [NOTICE.md](NOTICE.md) for source attribution and public package boundaries.
