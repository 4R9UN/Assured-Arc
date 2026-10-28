#!/usr/bin/env python3
"""Replay deterministic event trajectories against both harness hooks."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "agent-harness.json"
POLICY = ROOT / "config" / "tool-policy.json"
FIXTURES = ROOT / "config" / "harness-evaluation-fixtures.json"
PYTHON_HOOK = ROOT / "hooks" / "harness_event.py"
POWERSHELL_HOOK = ROOT / "hooks" / "harness-event.ps1"
ALLOWED_SUMMARY_KEYS = {
    "schema", "builtAt", "scenarioCount", "eventCount", "passCount",
    "failureCount", "elapsedBucket", "decisionCounts", "failures",
}


def decision(response: dict[str, Any]) -> str:
    output = response.get("hookSpecificOutput", {})
    if output.get("permissionDecision"):
        return str(output["permissionDecision"])
    if response.get("continue") is False:
        return "deny"
    if output.get("hookEventName") == "SubagentStart":
        return "allow"
    return "observe"


def invoke(command: list[str], event: dict[str, Any], trace_root: Path) -> tuple[dict[str, Any], str]:
    environment = os.environ.copy()
    environment["ASSURED_ARC_HARNESS_CONFIG"] = str(CONFIG)
    environment["ASSURED_ARC_HARNESS_TRACE_DIR"] = str(trace_root)
    environment["ASSURED_ARC_HARNESS_TOOL_POLICY"] = str(POLICY)
    completed = subprocess.run(
        command,
        input=json.dumps(event),
        text=True,
        capture_output=True,
        env=environment,
        check=False,
        timeout=10,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"hook exit {completed.returncode}: {completed.stderr.strip()}")
    response = json.loads(completed.stdout or "{}")
    return response, decision(response)


def bucket(seconds: float) -> str:
    if seconds < 1:
        return "under-1s"
    if seconds < 5:
        return "1-5s"
    if seconds < 15:
        return "5-15s"
    return "15s-plus"


def _run_scenario(
    scenario: dict[str, Any],
    platforms: list[tuple[str, list[str]]],
    temp: Path,
) -> tuple[int, Counter[str], list[dict[str, str]]]:
    local_failures: list[dict[str, str]] = []
    local_counts: Counter[str] = Counter()
    local_events = 0
    platform_decisions: dict[str, list[str]] = {}
    platform_responses: dict[str, list[dict[str, Any]]] = {}
    for platform, command in platforms:
        trace_root = temp / platform / scenario["id"]
        decisions: list[str] = []
        responses: list[dict[str, Any]] = []
        for event in scenario["events"]:
            local_events += 1
            enriched = {"timestamp": "2026-01-01T00:00:00Z", "cwd": str(ROOT), **event}
            try:
                response, result = invoke(command, enriched, trace_root)
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                local_failures.append({"scenario": scenario["id"], "class": "implementation-error", "platform": platform})
                decisions.append("error")
                responses.append({"error": type(error).__name__})
                continue
            decisions.append(result)
            responses.append(response)
            local_counts[result] += 1
        platform_decisions[platform] = decisions
        platform_responses[platform] = responses
        if decisions != scenario["expect"]:
            local_failures.append({"scenario": scenario["id"], "class": "assertion-failure", "platform": platform})
        for required in scenario.get("responseContains", []):
            serialized = json.dumps(responses)
            if required not in serialized:
                local_failures.append({"scenario": scenario["id"], "class": "missing-invariant", "platform": platform})
    if "powershell" in platform_decisions and platform_decisions.get("python") != platform_decisions.get("powershell"):
        local_failures.append({"scenario": scenario["id"], "class": "platform-drift", "platform": "both"})
    return local_events, local_counts, local_failures


def evaluate() -> dict[str, Any]:
    fixture_data = json.loads(FIXTURES.read_text(encoding="utf-8"))
    failures: list[dict[str, str]] = []
    counts: Counter[str] = Counter()
    event_count = 0
    started = time.perf_counter()
    powershell = ["pwsh", "-NoProfile", "-File", str(POWERSHELL_HOOK)]
    python = [sys.executable, str(PYTHON_HOOK)]
    platforms = [("python", python)]
    if shutil.which("pwsh"):
        platforms.append(("powershell", powershell))
    with tempfile.TemporaryDirectory(prefix="assured-arc-harness-eval-") as temporary:
        temp = Path(temporary)
        with ThreadPoolExecutor(max_workers=len(fixture_data["scenarios"])) as pool:
            futures = [pool.submit(_run_scenario, scenario, platforms, temp) for scenario in fixture_data["scenarios"]]
            for future in futures:
                local_events, local_counts, local_failures = future.result()
                event_count += local_events
                counts.update(local_counts)
                failures.extend(local_failures)
        secret = "EVALUATOR-SECRET-MUST-NOT-PERSIST"
        redaction_trace = temp / "redaction"
        invoke(python, {"timestamp": "2026-01-01T00:00:00Z", "cwd": str(ROOT), "session_id": "redaction", "hook_event_name": "UserPromptSubmit", "prompt": secret}, redaction_trace)
        trace_text = "\n".join(path.read_text(encoding="utf-8") for path in redaction_trace.rglob("*") if path.is_file())
        if secret in trace_text:
            failures.append({"scenario": "metadata-redaction", "class": "privacy-failure", "platform": "python"})
    elapsed = time.perf_counter() - started
    summary: dict[str, Any] = {
        "schema": 1,
        "builtAt": "runtime",
        "scenarioCount": len(fixture_data["scenarios"]),
        "eventCount": event_count,
        "passCount": len(fixture_data["scenarios"]) - len({item["scenario"] for item in failures}),
        "failureCount": len(failures),
        "elapsedBucket": bucket(elapsed),
        "decisionCounts": dict(sorted(counts.items())),
        "failures": failures,
    }
    assert set(summary) == ALLOWED_SUMMARY_KEYS
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write", type=Path, help="Write privacy-safe evaluation summary")
    args = parser.parse_args()
    summary = evaluate()
    serialized = json.dumps(summary, indent=None if args.json else 2, separators=(",", ":") if args.json else None)
    if args.write:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)
    return 1 if summary["failureCount"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
