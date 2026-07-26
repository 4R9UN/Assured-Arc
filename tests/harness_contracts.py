#!/usr/bin/env python3
"""Deterministic static and hook contracts for the portable agent harness."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
WORKERS = {
    "Assured Arc Disposable Scout": ["read", "search"],
    "Assured Arc Disposable Researcher": [
        "read",
        "search",
        "web",
        "context7/*",
        "sequential-thinking/*",
        "arxiv/*",
    ],
    "Assured Arc Disposable Implementer": ["read", "edit", "search"],
    "Assured Arc Disposable Verifier": ["read", "search", "execute"],
    "Assured Arc Disposable Critic": ["read", "search"],
}
def load_json(relative: str) -> dict[str, Any]:
    with (ROOT / relative).open(encoding="utf-8") as stream:
        value = json.load(stream)
    assert isinstance(value, dict), relative
    return value


def frontmatter(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, flags=re.DOTALL)
    assert match, f"Missing frontmatter: {path.name}"
    return match.group(1)


def field(block: str, name: str) -> str:
    match = re.search(rf"(?m)^{re.escape(name)}:\s*(.*?)\s*$", block)
    assert match, f"Missing {name}"
    return match.group(1)


def inline_list(value: str) -> list[str]:
    assert value.startswith("[") and value.endswith("]"), value
    return [item.strip().strip("'\"") for item in value[1:-1].split(",") if item.strip()]


def block_list(block: str, name: str) -> list[str]:
    match = re.search(rf"(?m)^{re.escape(name)}:\s*\n((?:\s+- .+\n?)+)", block)
    assert match, f"Missing list {name}"
    return [line.strip()[2:].strip("'\"") for line in match.group(1).splitlines()]


def run_hook(
    script: Path,
    payload: dict[str, Any],
    config: Path,
    traces: Path,
    host: str = "vscode",
    bound_event: str = "",
) -> dict[str, Any]:
    environment = os.environ.copy()
    environment["ASSURED_ARC_HARNESS_CONFIG"] = str(config)
    environment["ASSURED_ARC_HARNESS_TRACE_DIR"] = str(traces)
    environment["ASSURED_ARC_HARNESS_TOOL_POLICY"] = str(ROOT / "config/tool-policy.json")
    environment["ASSURED_ARC_HARNESS_HOST"] = host
    if bound_event:
        environment["ASSURED_ARC_HARNESS_EVENT"] = bound_event
    completed = subprocess.run(
        [sys.executable, str(script)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=environment,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr
    return json.loads(completed.stdout or "{}")


def event(name: str, session: str, **values: Any) -> dict[str, Any]:
    return {
        "timestamp": "2026-01-01T00:00:00Z",
        "cwd": str(ROOT),
        "session_id": session,
        "hook_event_name": name,
        **values,
    }


def validate_static_contracts() -> None:
    harness = load_json("config/agent-harness.json")
    tool_policy = load_json("config/tool-policy.json")
    assert harness["delegation"]["maximumDepth"] == 1
    assert harness["delegation"]["maximumParallelWorkers"] == 3
    assert harness["delegation"]["maximumWorkerInvocationsPerSession"] == 7
    assert harness["delegation"]["singleWriter"] is True
    assert harness["delegation"]["nestedSubagents"] is False
    assert harness["delegation"]["allowedWorkers"] == list(WORKERS)
    assert harness["protectedRoots"] == ["~/.copilot", "~/.assured-arc"]
    assert harness["loop"]["maximumRepairIterations"] == 2
    assert harness["loop"]["maximumEquivalentFailures"] == 1
    assert harness["skillRouting"]["maximumSkillsPerWorker"] == 3
    assert harness["skillRouting"]["routeAllInstalledSkills"] is True
    assert harness["skillRouting"]["router"] == "~/.copilot/route-skills.py"
    assert harness["skillRouting"]["canonicalRegistry"] == "~/.copilot/skill-registry.json"
    assert harness["toolPolicy"]["exactClassification"] is True
    assert harness["toolPolicy"]["unknownDecision"] == "ask"
    assert tool_policy["unknownDecision"] == "ask"
    assert tool_policy["tools"]["read_file"] == "read"
    assert tool_policy["tools"]["apply_patch"] == "write"
    assert tool_policy["tools"]["run_in_terminal"] == "execute"
    assert tool_policy["tools"]["view"] == "read"
    assert tool_policy["tools"]["powershell"] == "execute"
    assert tool_policy["tools"]["task"] == "delegate"
    assert set(harness["tracing"]["neverRecord"]) >= {
        "prompt text",
        "model reasoning",
        "file contents",
        "tool arguments",
        "tool results",
        "credentials",
        "raw transcripts",
    }
    assert harness["evolution"]["automatic"] is False
    assert harness["evolution"]["automaticPromotion"] is False

    for agent_path in (ROOT / ".github/agents").glob("*.agent.md"):
        assert not any(line.startswith("\t") for line in frontmatter(agent_path).splitlines()), f"Tab-indented YAML: {agent_path.name}"

    orchestrator = frontmatter(ROOT / ".github/agents/assured-arc-orchestrator.agent.md")
    assert inline_list(field(orchestrator, "tools")) == ["read", "search", "agent"]
    assert block_list(orchestrator, "agents") == list(WORKERS)
    assert field(orchestrator, "disable-model-invocation") == "true"

    writer_count = 0
    for name, tools in WORKERS.items():
        filename = "assured-arc-" + name.removeprefix("Assured Arc ").lower().replace(" ", "-") + ".agent.md"
        block = frontmatter(ROOT / ".github/agents" / filename)
        assert field(block, "name").strip("'\"") == name
        assert inline_list(field(block, "tools")) == tools
        assert inline_list(field(block, "agents")) == []
        assert field(block, "user-invocable") == "false"
        assert field(block, "disable-model-invocation") == "true"
        writer_count += int("edit" in tools)
    assert writer_count == 1
    assert "web" not in WORKERS["Assured Arc Disposable Implementer"]
    assert "execute" not in WORKERS["Assured Arc Disposable Implementer"]
    assert "edit" not in WORKERS["Assured Arc Disposable Researcher"]
    assert "execute" not in WORKERS["Assured Arc Disposable Researcher"]
    for tool_set in ("context7/*", "sequential-thinking/*", "arxiv/*"):
        assert tool_set in WORKERS["Assured Arc Disposable Researcher"]
        assert tool_set not in WORKERS["Assured Arc Disposable Implementer"]

    settings = load_json("config/user-settings.json")
    assert settings["chat.customAgentInSubagent.enabled"] is True
    assert settings["chat.subagents.allowInvocationsFromSubagents"] is False
    assert settings["chat.useAgentSkills"] is True
    assert settings["chat.useAgentsMdFile"] is False
    assert settings["chat.useClaudeMdFile"] is False
    assert settings["chat.instructionsFilesLocations"][".github/instructions"] is False
    for unsupported in (
        "github.copilot.chat.searchSubagent.enabled",
        "github.copilot.chat.anthropic.toolSearchTool.enabled",
        "github.copilot.chat.anthropic.contextEditing.enabled",
    ):
        assert unsupported not in settings
    for key in (
        "chat.agentFilesLocations",
        "chat.promptFilesLocations",
        "chat.agentSkillsLocations",
        "chat.hookFilesLocations",
    ):
        assert settings[key] == {}

    hook_config = load_json(".github/hooks/agent-harness.json.example")
    assert set(hook_config["hooks"]) == {
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PreCompact",
        "SubagentStart",
        "SubagentStop",
        "Stop",
    }
    for hooks in hook_config["hooks"].values():
        for hook in hooks:
            assert hook["env"]["ASSURED_ARC_HARNESS_TOOL_POLICY"] == "__HARNESS_TOOL_POLICY__"
    cli_hook_config = load_json(".github/hooks/copilot-cli-harness.json.example")
    assert cli_hook_config["version"] == 1
    assert set(cli_hook_config["hooks"]) == {
        "sessionStart",
        "sessionEnd",
        "userPromptSubmitted",
        "preToolUse",
        "postToolUse",
        "postToolUseFailure",
        "preCompact",
        "subagentStart",
        "subagentStop",
        "agentStop",
    }
    for hooks in cli_hook_config["hooks"].values():
        for hook in hooks:
            assert hook["env"]["ASSURED_ARC_HARNESS_HOST"] == "copilot-cli"
            assert hook["env"]["ASSURED_ARC_HARNESS_EVENT"] == "__HARNESS_EVENT__"
            assert "bash" in hook and "powershell" in hook
def validate_python_hook() -> None:
    script = ROOT / "hooks/harness_event.py"
    base_config = load_json("config/agent-harness.json")
    secret = "SHOULD-NOT-APPEAR-IN-TRACE"
    with tempfile.TemporaryDirectory(prefix="assured-arc-harness-contract-") as temporary:
        temp = Path(temporary)
        config = temp / "agent-harness.json"
        config.write_text(json.dumps(base_config), encoding="utf-8")
        traces = temp / "traces"

        first = run_hook(
            script,
            event("SubagentStart", "writer-session", agent_id="one", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        assert first["hookSpecificOutput"]["hookEventName"] == "SubagentStart"
        second = run_hook(
            script,
            event("SubagentStart", "writer-session", agent_id="two", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        assert second["continue"] is False and "Single-writer" in second["stopReason"]
        run_hook(
            script,
            event("SubagentStop", "writer-session", agent_id="wrong", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        still_blocked = run_hook(
            script,
            event("SubagentStart", "writer-session", agent_id="three", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        assert still_blocked["continue"] is False and "Single-writer" in still_blocked["stopReason"]
        run_hook(
            script,
            event("SubagentStop", "writer-session", agent_id="one", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        repair_writer = run_hook(
            script,
            event("SubagentStart", "writer-session", agent_id="repair", agent_type="Assured Arc Disposable Implementer"),
            config,
            traces,
        )
        assert repair_writer["hookSpecificOutput"]["hookEventName"] == "SubagentStart"

        unrelated = run_hook(
            script,
            event("SubagentStart", "unrelated-session", agent_id="plan", agent_type="Plan"),
            config,
            traces,
        )
        assert unrelated == {"continue": True}

        for index in range(3):
            allowed = run_hook(
                script,
                event("SubagentStart", "worker-session", agent_id=str(index), agent_type="Assured Arc Disposable Scout"),
                config,
                traces,
            )
            assert allowed["hookSpecificOutput"]["hookEventName"] == "SubagentStart"
        denied = run_hook(
            script,
            event("SubagentStart", "worker-session", agent_id="four", agent_type="Assured Arc Disposable Scout"),
            config,
            traces,
        )
        assert denied["continue"] is False and "budget" in denied["stopReason"].lower()

        ask = run_hook(
            script,
            event("PreToolUse", "approval-session", tool_name="run_in_terminal", tool_input={"command": "npm install example"}),
            config,
            traces,
        )
        assert ask["hookSpecificOutput"]["permissionDecision"] == "ask"
        protected = run_hook(
            script,
            event(
                "PreToolUse",
                "protected-session",
                tool_name="apply_patch",
                tool_input={"filePath": str(Path.home() / ".assured-arc/copilot/agent-harness.json")},
            ),
            config,
            traces,
        )
        assert protected["hookSpecificOutput"]["permissionDecision"] == "deny"
        exact_root = run_hook(
            script,
            event(
                "PreToolUse",
                "protected-root-session",
                tool_name="delete_file",
                tool_input={"filePath": str(Path.home() / ".assured-arc")},
            ),
            config,
            traces,
        )
        assert exact_root["hookSpecificOutput"]["permissionDecision"] == "deny"
        global_settings = run_hook(
            script,
            event(
                "PreToolUse",
                "settings-session",
                tool_name="apply_patch",
                tool_input={"filePath": str(Path.home() / "AppData/Roaming/Code/User/settings.json")},
            ),
            config,
            traces,
        )
        assert global_settings["hookSpecificOutput"]["permissionDecision"] == "ask"
        documentation_edit = run_hook(
            script,
            event(
                "PreToolUse",
                "documentation-session",
                tool_name="apply_patch",
                tool_input={"filePath": "docs/example.md", "content": "Document npm install and rm -rf safely."},
            ),
            config,
            traces,
        )
        assert "hookSpecificOutput" not in documentation_edit

        invocation_limited = json.loads(json.dumps(base_config))
        invocation_limited["delegation"]["maximumWorkerInvocationsPerSession"] = 2
        config.write_text(json.dumps(invocation_limited), encoding="utf-8")
        for index in range(2):
            started = run_hook(
                script,
                event("SubagentStart", "invocation-budget", agent_id=str(index), agent_type="Assured Arc Disposable Scout"),
                config,
                traces,
            )
            assert started["hookSpecificOutput"]["hookEventName"] == "SubagentStart"
            run_hook(
                script,
                event("SubagentStop", "invocation-budget", agent_id=str(index), agent_type="Assured Arc Disposable Scout"),
                config,
                traces,
            )
        invocation_denied = run_hook(
            script,
            event("SubagentStart", "invocation-budget", agent_id="three", agent_type="Assured Arc Disposable Scout"),
            config,
            traces,
        )
        assert invocation_denied["continue"] is False and "invocation budget" in invocation_denied["stopReason"].lower()

        broken_config = temp / "broken.json"
        broken_config.write_text("{}", encoding="utf-8")
        environment = os.environ.copy()
        environment["ASSURED_ARC_HARNESS_CONFIG"] = str(broken_config)
        environment["ASSURED_ARC_HARNESS_TRACE_DIR"] = str(traces)
        environment["ASSURED_ARC_HARNESS_TOOL_POLICY"] = str(ROOT / "config/tool-policy.json")
        failed_closed = subprocess.run(
            [sys.executable, str(script)],
            input=json.dumps(event("PreToolUse", "broken-policy", tool_name="read_file", tool_input={})),
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )
        assert failed_closed.returncode == 2

        limited = json.loads(json.dumps(base_config))
        limited["loop"]["maximumToolCallsPerSession"] = 2
        config.write_text(json.dumps(limited), encoding="utf-8")
        for index in range(2):
            response = run_hook(
                script,
                event("PreToolUse", "tool-budget", tool_name="read_file", tool_input={"filePath": f"safe-{index}"}),
                config,
                traces,
            )
            assert "hookSpecificOutput" not in response
        over_budget = run_hook(
            script,
            event("PreToolUse", "tool-budget", tool_name="read_file", tool_input={"filePath": "safe-third"}),
            config,
            traces,
        )
        assert over_budget["hookSpecificOutput"]["permissionDecision"] == "deny"

        run_hook(script, event("UserPromptSubmit", "redaction-session", prompt=secret), config, traces)
        run_hook(
            script,
            event("PreToolUse", "redaction-session", tool_name="read_file", tool_input={"token": secret}),
            config,
            traces,
        )
        all_trace_text = "\n".join(path.read_text(encoding="utf-8") for path in traces.rglob("*") if path.is_file())
        assert secret not in all_trace_text
        records = [json.loads(line) for path in traces.glob("*.jsonl") for line in path.read_text(encoding="utf-8").splitlines()]
        assert records
        allowed_keys = {"timestamp", "event", "session", "workspace", "agent", "tool", "decision"}
        assert all(set(record) == allowed_keys for record in records)

        run_hook(script, event("Stop", "redaction-session", stop_hook_active=False), config, traces)
        state_files = list((traces / "state").glob("*.json"))
        assert all("redaction-session" not in path.name for path in state_files)

        cli_start = run_hook(
            script,
            {
                "sessionId": "cli-session",
                "timestamp": 1,
                "cwd": str(ROOT),
                "source": "startup",
                "hook_event_name": "sessionStart",
            },
            config,
            traces,
            host="copilot-cli",
        )
        assert "additionalContext" in cli_start and "hookSpecificOutput" not in cli_start
        cli_bound_start = run_hook(
            script,
            {"sessionId": "cli-bound", "timestamp": 1, "cwd": str(ROOT), "source": "startup"},
            config,
            traces,
            host="copilot-cli",
            bound_event="sessionStart",
        )
        assert "additionalContext" in cli_bound_start
        cli_approval = run_hook(
            script,
            {
                "sessionId": "cli-approval",
                "timestamp": 2,
                "cwd": str(ROOT),
                "toolName": "powershell",
                "toolArgs": {"command": "npm install example"},
                "hook_event_name": "preToolUse",
            },
            config,
            traces,
            host="copilot-cli",
        )
        assert cli_approval["permissionDecision"] == "ask"
        assert "hookSpecificOutput" not in cli_approval
        first_cli_writer = run_hook(
            script,
            {
                "sessionId": "cli-writer",
                "timestamp": 3,
                "cwd": str(ROOT),
                "toolName": "task",
                "toolArgs": {"agent_type": "assured-arc-disposable-implementer", "prompt": "first"},
                "hook_event_name": "preToolUse",
            },
            config,
            traces,
            host="copilot-cli",
        )
        assert first_cli_writer["permissionDecision"] == "allow"
        second_cli_writer = run_hook(
            script,
            {
                "sessionId": "cli-writer",
                "timestamp": 4,
                "cwd": str(ROOT),
                "toolName": "task",
                "toolArgs": {"agent_type": "assured-arc-disposable-implementer", "prompt": "second"},
                "hook_event_name": "preToolUse",
            },
            config,
            traces,
            host="copilot-cli",
        )
        assert second_cli_writer["permissionDecision"] == "deny"
        assert "Single-writer" in second_cli_writer["permissionDecisionReason"]
        run_hook(
            script,
            {"sessionId": "cli-writer", "timestamp": 5, "cwd": str(ROOT), "stopReason": "end_turn"},
            config,
            traces,
            host="copilot-cli",
            bound_event="agentStop",
        )
        still_denied_after_turn = run_hook(
            script,
            {
                "sessionId": "cli-writer",
                "timestamp": 6,
                "cwd": str(ROOT),
                "toolName": "task",
                "toolArgs": {"agent_type": "assured-arc-disposable-implementer", "prompt": "third"},
            },
            config,
            traces,
            host="copilot-cli",
            bound_event="preToolUse",
        )
        assert still_denied_after_turn["permissionDecision"] == "deny"
        run_hook(
            script,
            {"sessionId": "cli-writer", "timestamp": 7, "cwd": str(ROOT), "reason": "complete"},
            config,
            traces,
            host="copilot-cli",
            bound_event="sessionEnd",
        )
        writer_after_session_end = run_hook(
            script,
            {
                "sessionId": "cli-writer",
                "timestamp": 8,
                "cwd": str(ROOT),
                "toolName": "task",
                "toolArgs": {"agent_type": "assured-arc-disposable-implementer", "prompt": "new session"},
            },
            config,
            traces,
            host="copilot-cli",
            bound_event="preToolUse",
        )
        assert writer_after_session_end["permissionDecision"] == "allow"


def main() -> int:
    validate_static_contracts()
    validate_python_hook()
    print("PASS native harness contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
