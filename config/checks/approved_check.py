#!/usr/bin/env python3
"""Deterministic workspace hygiene and anti-bloat check run by the external scoreboard."""

from __future__ import annotations

import ast
import os
from pathlib import Path
import sys

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_SUFFIXES = {".tmp", ".bak", ".orig", ".swp", ".swo", ".pyc", ".pyo"}
IGNORED_DIRS = {
    ".git",
    "__pycache__",
    ".venv",
    "venv",
    "node_modules",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".assured-arc",
    ".assured-arc-state",
    "backups",
}
TEXT_SUFFIXES = {".py", ".ps1", ".sh", ".json", ".md", ".svg", ".yml", ".yaml"}
CONFLICT_MARKERS = (b"\n<<<<<<< ", b"\r\n<<<<<<< ", b"\n=======\n", b"\r\n=======\r\n", b"\n>>>>>>> ", b"\r\n>>>>>>> ")
DEBUG_CALLS = {(" pdb", "set_trace"), ("pdb", "set_trace"), ("ipdb", "set_trace"), ("bdb", "set_trace")}


def _check_python_ast(rel_path: Path, raw: bytes) -> list[str]:
    issues: list[str] = []
    try:
        source = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        return [f"invalid utf-8 in python file: {rel_path} ({exc})"]
    try:
        tree = ast.parse(source, filename=str(rel_path))
    except SyntaxError as exc:
        return [f"python syntax error: {rel_path}:{exc.lineno or 1} ({exc.msg})"]

    seen_defs: dict[str, int] = {}
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            previous = seen_defs.get(node.name)
            if previous is not None:
                issues.append(
                    f"duplicate top-level definition '{node.name}': {rel_path}:{node.lineno} (first at line {previous})"
                )
            else:
                seen_defs[node.name] = node.lineno

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "breakpoint":
                issues.append(f"leftover debug breakpoint(): {rel_path}:{node.lineno}")
            elif (
                isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name)
                and (node.func.value.id, node.func.attr) in DEBUG_CALLS
            ):
                issues.append(
                    f"leftover debug trace {node.func.value.id}.{node.func.attr}(): {rel_path}:{node.lineno}"
                )
    return issues


def scan_workspace(root: Path) -> list[str]:
    violations: list[str] = []
    for current_root, dirs, files in os.walk(root, topdown=True):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]
        base = Path(current_root)
        for name in files:
            path = base / name
            rel_path = path.relative_to(root)
            suffix = path.suffix.lower()
            if name.endswith("~") or suffix in FORBIDDEN_SUFFIXES:
                violations.append(f"unwanted artifact: {rel_path}")
                continue
            if suffix in TEXT_SUFFIXES:
                try:
                    raw = path.read_bytes()
                except OSError:
                    continue
                if raw.startswith(b"<<<<<<< ") or any(marker in raw for marker in CONFLICT_MARKERS):
                    violations.append(f"unresolved merge conflict marker: {rel_path}")
                    continue
                if suffix == ".py":
                    violations.extend(_check_python_ast(rel_path, raw))
        if len(violations) >= 10:
            break
    return violations[:10]


def main() -> int:
    cwd = Path.cwd().resolve()
    target = cwd if cwd.is_dir() else DEFAULT_ROOT
    violations = scan_workspace(target)
    if violations:
        sys.stderr.write("Workspace hygiene check failed:\n" + "\n".join(violations[:10]) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


