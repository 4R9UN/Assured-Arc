# Changelog

All notable changes to **Assured Arc** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-28

### Added

- **Shared Dual-Host Agent Contract (`config/agent-contract.json` & `scripts/render_contract.py`)**:
  - Added a single canonical JSON contract (`v1.1.0`) defining role tool capabilities, delegation depth (`1`), single-writer concurrency (`1`), maximum parallel workers (`3`), skill routing budget (`3`), and repair iteration limits (`2`).
  - Added `scripts/render_contract.py` to deterministically render native Claude Code adapters (`.claude/agents/assured-arc-*.md`, `.claude/settings.json`, and `agent-contract.json`) from the shared contract without copying Copilot agent files.
- **External Scoreboard Verification Gate (`scripts/scoreboard.py`, `config/scoreboard.json`, `config/checks/approved_check.py`)**:
  - Enforced verify-after-write at the hook level (`PostToolUse` marks sessions `pendingVerification = true` with a fresh cryptographic `verificationNonce`).
  - Blocked `Stop` completion after any file mutation until `scripts/scoreboard.py` executes all approved checks under `config/scoreboard.json` and writes a session- and nonce-matched `verification-receipt`.
  - Prevented self-scoring and forged verification receipts (model-written `verification-receipt.json` files are rejected).
- **Strict Human-Gated Path Precedence**:
  - Updated `hooks/harness_event.py` and `hooks/harness-event.ps1` (`_human_gate_decision` / `Get-HumanGateDecision`) to evaluate human-gated path restrictions first in `PreToolUse`, denying mutations to `.github/agents`, `.github/skills`, `.github/hooks`, `.claude/agents`, `.claude/settings.json`, `mcp.json`, `hooks/`, `scripts/`, `install/`, and `config/*` before fallback policies (`ask`) unless `ASSURED_ARC_HUMAN_GATE=open` is set by a human.
  - Added opt-in gate for dynamic workflow generation (`ASSURED_ARC_DYNAMIC_WORKFLOWS=1`).
- **First-Class Web Research & Surfing Skill (`assured-arc-web-research`)**:
  - Added `.github/skills/assured-arc-web-research/SKILL.md` and registered it in `config/skill-registry.json` (expanding the library to 28 portable skills) to guide live web search (`web`, `WebSearch`, `web_search`), primary URL fetching (`WebFetch`, `fetch_webpage`, `web_fetch`), citation provenance, and prompt-injection quarantine across `Assured Arc Research`, `Assured Arc Disposable Researcher`, and `assured-arc-researcher`.

### Changed

- **Cross-Platform Installer & Uninstall Lifecycle (`install/assured-arc.*`, `install/uninstall.*`)**:
  - Extended PowerShell and Bash installers to deploy `scoreboard.json`, `scoreboard.py`, `checks/approved_check.py`, and rendered Claude Code adapters (`<profile-root>/claude/*`) with full `ASSURED_ARC_SCOREBOARD*` hook environment wiring.
  - Updated `uninstall.ps1` and `uninstall.sh` ownership verification and cleanup to remove managed `scoreboard`, `scoreboard-check`, `claude-settings`, `claude-contract`, and `claude-agent` records cleanly.
- **Validation & Contract Test Suite (`tests/harness_contracts.py`, `tests/validate.ps1`, `tests/validate.sh`)**:
  - Added deterministic tests covering the shared contract, Claude adapter rendering, scoreboard nonce verification, forged receipt rejection, and human-gate precedence.

## [1.0.0] - 2026-10-28

### Added

- Initial public release of **Assured Arc** for VS Code and GitHub Copilot CLI.
- 7 visible specialist agents and 5 context-isolated disposable subagent workers (`Scout`, `Researcher`, `Implementer`, `Verifier`, `Critic`).
- 27 lazy-loaded portable skills with compact skill registry (`config/skill-registry.json`) and 6 VS Code slash-command prompts.
- Cross-platform reversible installers (`install.ps1`, `install/assured-arc.ps1`, `install/assured-arc.sh`), read-only `doctor` and `migrate-legacy` helpers, and checksum-verified `state.json` (Schema 4) rollback/uninstall.
- Reviewed 3-server research MCP baseline (`Context7`, `Sequential Thinking 2026.7.4`, and isolated `arXiv MCP Server 0.5.1`).
- Optional Markdown-first Obsidian vault template (`vault-template/`).
