#!/usr/bin/env python3
"""Run the approved scoreboard and write a verification receipt only on full success."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


CHECK_ID = re.compile(r"^[a-z0-9-]{1,64}$")
SAFE_ARG = re.compile(r"^[A-Za-z0-9_.=+/-]{1,180}$")
NONCE = re.compile(r"^[a-f0-9]{32}$")


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict) or not isinstance(value.get("checks"), list):
        raise ValueError("Scoreboard config must contain a checks array.")
    return value


def _approved_command(argv: list[Any], config_dir: Path, allow_root: Path) -> list[str]:
    if len(argv) < 2 or any(not isinstance(item, str) for item in argv):
        raise ValueError("Approved check argv must be a python command and a relative script.")
    if argv[0] not in {"python", "python3"}:
        raise ValueError("Approved checks may only start with python or python3.")
    script = Path(argv[1])
    if script.is_absolute() or ".." in script.parts or script.suffix != ".py":
        raise ValueError("Approved check script must be a relative Python file inside the scoreboard root.")
    target = (config_dir / script).resolve()
    try:
        target.relative_to(allow_root.resolve())
    except ValueError as exc:
        raise ValueError("Approved check script escapes the allowed root.") from exc
    if not target.is_file():
        raise ValueError("Approved check script does not exist.")
    extra: list[str] = []
    for item in argv[2:]:
        if not SAFE_ARG.fullmatch(item) or item.startswith("-"):
            raise ValueError("Approved check arguments must be literal safe tokens.")
        extra.append(item)
    return [sys.executable, str(target), *extra]


def run_scoreboard(config: Path, cwd: Path, allow_root: Path, session: str, trace_dir: Path, nonce: str) -> dict[str, Any]:
    if not NONCE.fullmatch(nonce):
        raise ValueError("Scoreboard nonce is missing.")
    spec = _load(config)
    checks = spec["checks"]
    if not checks:
        raise ValueError("Scoreboard has no approved checks.")
    results: list[dict[str, Any]] = []
    environment = os.environ.copy()
    environment.pop("ASSURED_ARC_SCOREBOARD_NONCE", None)
    environment["ASSURED_ARC_SCOREBOARD_RUNNING"] = "1"
    for check in checks:
        if not isinstance(check, dict) or not CHECK_ID.fullmatch(str(check.get("id", ""))):
            raise ValueError("Approved check id is missing or invalid.")
        timeout = int(check.get("timeoutSeconds", 60))
        if timeout < 1 or timeout > 300:
            raise ValueError("Approved check timeout is outside 1-300 seconds.")
        command = _approved_command(list(check.get("argv", [])), config.parent, allow_root)
        completed = subprocess.run(
            command,
            cwd=cwd,
            env=environment,
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        results.append(
            {
                "id": str(check["id"]),
                "status": "pass" if completed.returncode == 0 else "fail",
                "exitCode": int(completed.returncode),
            }
        )
    passed = all(item["status"] == "pass" for item in results)
    receipt = {
        "schema": 1,
        "kind": "verification-receipt",
        "source": "scoreboard",
        "nonce": nonce,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "session": session,
        "status": "pass" if passed else "fail",
        "checks": results,
    }
    if passed:
        receipt_dir = trace_dir / "receipts"
        receipt_dir.mkdir(parents=True, exist_ok=True)
        target = receipt_dir / f"verification-{session}.json"
        temporary = target.with_suffix(f".tmp-{os.getpid()}")
        temporary.write_text(json.dumps(receipt, ensure_ascii=True, separators=(",", ":")) + "\n", encoding="utf-8")
        os.replace(temporary, target)
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description="Run approved Assured Arc verification checks.")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--cwd", required=True, type=Path)
    parser.add_argument("--allow-root", required=True, type=Path)
    parser.add_argument("--session", required=True)
    parser.add_argument("--trace-dir", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{16}", args.session):
        print("Scoreboard rejected an invalid session id.", file=sys.stderr)
        return 2
    nonce = os.environ.get("ASSURED_ARC_SCOREBOARD_NONCE", "")
    try:
        cwd = args.cwd.expanduser().resolve()
        allow_root = args.allow_root.expanduser().resolve()
        if not cwd.is_dir():
            raise ValueError("Scoreboard workspace does not exist.")
        receipt = run_scoreboard(args.config, cwd, allow_root, args.session, args.trace_dir, nonce)
    except (OSError, ValueError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"Scoreboard rejected the approved checks: {exc.__class__.__name__}", file=sys.stderr)
        return 2
    print(json.dumps({"status": receipt["status"], "checks": [item["id"] for item in receipt["checks"]]}))
    return 0 if receipt["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
