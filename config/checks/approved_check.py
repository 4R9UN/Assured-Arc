#!/usr/bin/env python3
"""Deterministic workspace hygiene and anti-bloat check run by the external scoreboard."""

from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

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
BIDI_AND_TAG_CODEPOINTS = (
    set(range(0x202A, 0x202F))
    | set(range(0x2066, 0x206A))
    | set(range(0xE0000, 0xE0080))
)
COVERT_COMMENT_INJECTION_RE = re.compile(
    r"<!--[\s\S]{0,2000}?(?:ignore\s+(?:all\s+)?(?:previous|prior)\s+instructions|"
    r"disregard\s+(?:the\s+)?system\s+prompt|"
    r"webhook\.site|requestbin\.com|canarytokens\.com)[\s\S]{0,2000}?-->",
    re.IGNORECASE,
)
TOOL_POISONING_META_RE = re.compile(
    r"(?:ignore\s+(?:all\s+)?(?:previous|prior)\s+instructions|"
    r"disregard\s+(?:the\s+)?system\s+prompt|"
    r"do\s+not\s+tell\s+the\s+user|"
    r"exfiltrate\s+(?:secrets|tokens|credentials|ssh)|"
    r"webhook\.site|requestbin\.com|canarytokens\.com)",
    re.IGNORECASE,
)
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


def _check_trojan_unicode(rel_path: Path, raw: bytes) -> list[str]:
    text = raw.decode("utf-8", errors="ignore")
    bad_cps = sorted({ord(ch) for ch in text if ord(ch) in BIDI_AND_TAG_CODEPOINTS})
    if bad_cps:
        hex_list = ", ".join(f"U+{cp:04X}" for cp in bad_cps[:5])
        return [f"Trojan/smuggled Unicode codepoints ({hex_list}): {rel_path}"]
    return []


def _check_markdown_agentshield(rel_path: Path, raw: bytes) -> list[str]:
    text = raw.decode("utf-8", errors="ignore")
    if COVERT_COMMENT_INJECTION_RE.search(text):
        return [f"covert prompt-injection directive in HTML comment: {rel_path}"]
    return []


def _is_mcp_config(rel_path: Path) -> bool:
    lowered = rel_path.name.lower()
    return (
        lowered in {"mcp.json", "mcp-config.json", "mcp-servers.json"}
        or ".mcp.json" in lowered
        or lowered.startswith("mcp.json.")
    )


def _walk_mcp_strings(node: object) -> list[str]:
    found: list[str] = []
    if isinstance(node, dict):
        for key, val in node.items():
            if str(key).lower() in {"description", "notes", "title", "prompt", "instructions", "annotations"} and isinstance(val, str):
                found.append(val)
            else:
                found.extend(_walk_mcp_strings(val))
    elif isinstance(node, list):
        for item in node:
            found.extend(_walk_mcp_strings(item))
    return found


def _check_json_and_mcp(rel_path: Path, raw: bytes) -> list[str]:
    issues: list[str] = []
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        return [f"invalid utf-8 in json file: {rel_path} ({exc})"]
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        return [f"invalid json syntax: {rel_path}:{exc.lineno} ({exc.msg})"]

    if not _is_mcp_config(rel_path) or not isinstance(parsed, dict):
        return issues

    for meta_text in _walk_mcp_strings(parsed):
        if TOOL_POISONING_META_RE.search(meta_text):
            issues.append(f"MCP tool-poisoning directive in metadata: {rel_path}")
            break

    servers_obj = parsed.get("servers") or parsed.get("mcpServers")
    if isinstance(servers_obj, dict):
        for server_id, spec in servers_obj.items():
            if not isinstance(spec, dict):
                continue
            url = str(spec.get("url") or "").strip()
            if url:
                parsed_url = urlparse(url)
                host = (parsed_url.hostname or "").lower()
                if parsed_url.scheme == "http" and host not in LOOPBACK_HOSTS:
                    issues.append(f"insecure non-HTTPS remote MCP endpoint '{server_id}': {rel_path}")
    return issues


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
            if suffix in TEXT_SUFFIXES or _is_mcp_config(rel_path):
                try:
                    raw = path.read_bytes()
                except OSError:
                    continue
                if raw.startswith(b"<<<<<<< ") or any(marker in raw for marker in CONFLICT_MARKERS):
                    violations.append(f"unresolved merge conflict marker: {rel_path}")
                    continue
                violations.extend(_check_trojan_unicode(rel_path, raw))
                if suffix == ".py":
                    violations.extend(_check_python_ast(rel_path, raw))
                elif suffix == ".md":
                    violations.extend(_check_markdown_agentshield(rel_path, raw))
                elif suffix == ".json" or _is_mcp_config(rel_path):
                    violations.extend(_check_json_and_mcp(rel_path, raw))
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


