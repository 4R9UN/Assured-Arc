#!/usr/bin/env python3
"""Render Claude adapters from the shared contract. Never copies Copilot agent files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROLE_ORDER = ("orchestrator", "scout", "researcher", "implementer", "verifier", "critic")
CLAUDE_TOOLS = {
    "read": ["Read"],
    "search": ["Grep", "Glob"],
    "web": ["WebFetch", "WebSearch"],
    "edit": ["Edit", "Write"],
    "execute": ["Bash"],
    "agent": ["Agent"],
}
ROLE_COPY = {
    "orchestrator": (
        "You coordinate one bounded task from the shared contract.",
        [
            "Restate acceptance criteria. Do not invent agents, skills, hooks, MCP servers, or permissions.",
            "Select at most {skills} reviewed skills and at most {workers} workers. Depth is {depth}.",
            "Assign at most {writers} implementer. Research stays off the writer.",
            "Verification is the deterministic scoreboard run by the Stop hook. Do not self-score acceptance.",
            "Stop after {repairs} repairs. Harness, skill, hook, MCP, and permission edits stay human-gated.",
        ],
    ),
    "scout": (
        "You map the files and constraints for one bounded task.",
        ["Read and search only. Do not edit, run commands, or spawn agents."],
    ),
    "researcher": (
        "You gather external evidence for one bounded question.",
        ["Use read, search, and reviewed web or MCP tools. Do not edit or spawn agents."],
    ),
    "implementer": (
        "You are the only writer for the assigned files.",
        [
            "Edit only the brief's write scope. Read before editing.",
            "Do not run commands, browse, call MCP, or spawn agents.",
            "Return changed files and stop. The Stop hook runs the scoreboard.",
        ],
    ),
    "verifier": (
        "You verify a completed write against literal acceptance criteria.",
        [
            "Do not edit product files, mint a receipt, or spawn agents.",
            "You may run the approved scoreboard command, but only the Stop hook can accept its receipt.",
            "A missing or failed receipt blocks completion.",
        ],
    ),
    "critic": (
        "You look for blocking gaps in the bounded change.",
        ["Read and search only. Do not edit, self-score, or expand the harness."],
    ),
}


def _tools(role: dict[str, Any]) -> list[str]:
    names: list[str] = []
    for tool in role.get("tools", []):
        token = str(tool)
        if token.endswith("/*"):
            continue
        for name in CLAUDE_TOOLS.get(token, []):
            if name not in names:
                names.append(name)
    return names


def _agent(role_name: str, role: dict[str, Any], limits: dict[str, Any]) -> str:
    summary, rules = ROLE_COPY[role_name]
    rendered_rules = [
        line.format(
            skills=limits["maximumSelectedSkills"],
            workers=limits["maximumParallelWorkers"],
            depth=limits["delegationDepth"],
            writers=limits["writers"],
            repairs=limits["maximumRepairIterations"],
        )
        for line in rules
    ]
    body = "\n".join(f"- {line}" for line in rendered_rules)
    tools = ", ".join(_tools(role))
    return (
        "---\n"
        f"name: assured-arc-{role_name}\n"
        f'description: "{summary}"\n'
        f"tools: {tools}\n"
        "---\n\n"
        f"{summary}\n\n"
        f"{body}\n"
    )


def _hook(command: str, environment: dict[str, str]) -> dict[str, Any]:
    return {"type": "command", "command": command, "timeout": 180, "env": environment}


def render_claude(contract: dict[str, Any], destination: Path, command: str, environment: dict[str, str]) -> None:
    limits = contract["limits"]
    roles = contract["roles"]
    agents = destination / "agents"
    agents.mkdir(parents=True, exist_ok=True)
    expected = {f"assured-arc-{name}.md" for name in ROLE_ORDER}
    for stale in agents.glob("*.md"):
        if stale.name not in expected:
            stale.unlink()
    for name in ROLE_ORDER:
        (agents / f"assured-arc-{name}.md").write_text(_agent(name, roles[name], limits), encoding="utf-8")
    hook = _hook(command, environment)
    settings_path = destination / "settings.json"
    existing: dict[str, Any] = {}
    if settings_path.exists():
        loaded = json.loads(settings_path.read_text(encoding="utf-8-sig"))
        if isinstance(loaded, dict):
            existing = loaded
    hooks = existing.setdefault("hooks", {})
    hooks["PreToolUse"] = [{"matcher": ".*", "hooks": [hook]}]
    hooks["PostToolUse"] = [{"matcher": "Edit|Write|NotebookEdit", "hooks": [hook]}]
    hooks["Stop"] = [{"hooks": [hook]}]
    hooks["SubagentStart"] = [{"hooks": [hook]}]
    hooks["SubagentStop"] = [{"hooks": [hook]}]
    settings_path.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
    (destination / "agent-contract.json").write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Claude adapters from the shared contract.")
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--command", required=True)
    parser.add_argument("--env", action="append", default=[], metavar="KEY=VALUE")
    args = parser.parse_args()
    environment = {}
    for item in args.env:
        key, separator, value = item.partition("=")
        if not separator or not key:
            raise SystemExit(f"Invalid environment entry: {item}")
        environment[key] = value
    contract = json.loads(args.contract.read_text(encoding="utf-8-sig"))
    render_claude(contract, args.destination, args.command, environment)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
