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

import io
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
import hooks.harness_event as harness_event_module

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


def invoke_python(event: dict[str, Any], trace_root: Path) -> tuple[dict[str, Any], str]:
    environment = os.environ.copy()
    environment["ASSURED_ARC_HARNESS_CONFIG"] = str(CONFIG)
    environment["ASSURED_ARC_HARNESS_TRACE_DIR"] = str(trace_root)
    environment["ASSURED_ARC_HARNESS_TOOL_POLICY"] = str(POLICY)
    stdout = io.StringIO()
    with patch.dict(os.environ, environment, clear=True), patch("sys.stdin", io.StringIO(json.dumps(event))), patch("sys.stdout", stdout):
        code = harness_event_module.main()
    if code != 0:
        raise RuntimeError(f"python hook exit {code}")
    response = json.loads(stdout.getvalue() or "{}")
    return response, decision(response)


def invoke_powershell_batch(events: list[dict[str, Any]], trace_root: Path) -> list[tuple[dict[str, Any], str]]:
    environment = os.environ.copy()
    environment["ASSURED_ARC_HARNESS_CONFIG"] = str(CONFIG)
    environment["ASSURED_ARC_HARNESS_TRACE_DIR"] = str(trace_root)
    environment["ASSURED_ARC_HARNESS_TOOL_POLICY"] = str(POLICY)
    ps_script = (
        "$ErrorActionPreference = 'Stop'; "
        f"$hook = '{str(POWERSHELL_HOOK).replace(chr(39), chr(39)*2)}'; "
        "while ($null -ne ($line = [Console]::In.ReadLine())) { "
        "if ([string]::IsNullOrWhiteSpace($line)) { continue }; "
        "$out = & $hook -InputJson $line; "
        "[Console]::Out.WriteLine($out) "
        "}"
    )
    payload = "\n".join(json.dumps(event, separators=(",", ":")) for event in events) + "\n"
    completed = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", ps_script],
        input=payload,
        text=True,
        capture_output=True,
        env=environment,
        check=False,
        timeout=20,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"hook exit {completed.returncode}: {completed.stderr.strip()}")
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != len(events):
        raise RuntimeError(f"expected {len(events)} responses, got {len(lines)}")
    results: list[tuple[dict[str, Any], str]] = []
    for line in lines:
        response = json.loads(line)
        results.append((response, decision(response)))
    return results


def bucket(seconds: float) -> str:
    if seconds < 1:
        return "under-1s"
    if seconds < 5:
        return "1-5s"
    if seconds < 15:
        return "5-15s"
    return "15s-plus"


def evaluate() -> dict[str, Any]:
    fixture_data = json.loads(FIXTURES.read_text(encoding="utf-8"))
    failures: list[dict[str, str]] = []
    counts: Counter[str] = Counter()
    event_count = 0
    started = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="assured-arc-harness-eval-") as temporary:
        temp = Path(temporary)
        py_decisions_by_scenario: dict[str, list[str]] = {}
        for scenario in fixture_data["scenarios"]:
            trace_root = temp / "python" / scenario["id"]
            enriched_events = [{"timestamp": "2026-01-01T00:00:00Z", "cwd": str(ROOT), **event} for event in scenario["events"]]
            event_count += len(enriched_events)
            decisions: list[str] = []
            responses: list[dict[str, Any]] = []
            for enriched in enriched_events:
                try:
                    response, result = invoke_python(enriched, trace_root)
                except (RuntimeError, json.JSONDecodeError) as error:
                    failures.append({"scenario": scenario["id"], "class": "implementation-error", "platform": "python"})
                    decisions.append("error")
                    responses.append({"error": type(error).__name__})
                    continue
                decisions.append(result)
                responses.append(response)
                counts[result] += 1
            py_decisions_by_scenario[scenario["id"]] = decisions
            if decisions != scenario["expect"]:
                failures.append({"scenario": scenario["id"], "class": "assertion-failure", "platform": "python"})
            for required in scenario.get("responseContains", []):
                if required not in json.dumps(responses):
                    failures.append({"scenario": scenario["id"], "class": "missing-invariant", "platform": "python"})

        if shutil.which("pwsh"):
            ps_trace_root = temp / "powershell"
            all_ps_events: list[dict[str, Any]] = []
            slices: list[tuple[dict[str, Any], int, int]] = []
            for scenario in fixture_data["scenarios"]:
                start_idx = len(all_ps_events)
                for event in scenario["events"]:
                    all_ps_events.append({"timestamp": "2026-01-01T00:00:00Z", "cwd": str(ROOT), **event})
                slices.append((scenario, start_idx, len(all_ps_events)))
            event_count += len(all_ps_events)
            try:
                batch_results = invoke_powershell_batch(all_ps_events, ps_trace_root)
                for scenario, start_idx, end_idx in slices:
                    scenario_slice = batch_results[start_idx:end_idx]
                    decisions = [result for _, result in scenario_slice]
                    responses = [response for response, _ in scenario_slice]
                    for result in decisions:
                        counts[result] += 1
                    if decisions != scenario["expect"]:
                        failures.append({"scenario": scenario["id"], "class": "assertion-failure", "platform": "powershell"})
                    for required in scenario.get("responseContains", []):
                        if required not in json.dumps(responses):
                            failures.append({"scenario": scenario["id"], "class": "missing-invariant", "platform": "powershell"})
                    if py_decisions_by_scenario.get(scenario["id"]) != decisions:
                        failures.append({"scenario": scenario["id"], "class": "platform-drift", "platform": "both"})
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError):
                for scenario in fixture_data["scenarios"]:
                    failures.append({"scenario": scenario["id"], "class": "implementation-error", "platform": "powershell"})

        secret = "EVALUATOR-SECRET-MUST-NOT-PERSIST"
        redaction_trace = temp / "redaction"
        invoke_python({"timestamp": "2026-01-01T00:00:00Z", "cwd": str(ROOT), "session_id": "redaction", "hook_event_name": "UserPromptSubmit", "prompt": secret}, redaction_trace)
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
