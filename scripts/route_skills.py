#!/usr/bin/env python3
"""Deterministic skill router that scores tasks against compact skill registries."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

DEFAULT_REGISTRY = Path(__file__).resolve().parents[1] / "config" / "skill-registry.json"
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9_-]*")
CODE_CHANGE_RE = re.compile(
    r"\b(?:implement|write|edit|modify|update|change|refactor|fix|patch|add|create|delete|remove|clean\s+up|optimize|upgrade)\b",
    re.IGNORECASE,
)
STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how",
    "in", "into", "is", "it", "of", "on", "or", "that", "the", "this", "to", "use", "with",
}


def _tokenize(text: str) -> set[str]:
    return {tok for tok in TOKEN_RE.findall(text.lower()) if tok not in STOPWORDS and len(tok) > 1}


def load_merged_registry(paths: list[Path]) -> dict[str, Any]:
    merged_skills: dict[str, dict[str, Any]] = {}
    routing: dict[str, Any] = {
        "defaultRouter": "assured-arc-skill-router",
        "mandatoryForCodeChanges": ["assured-arc-development-quality", "assured-arc-codebase-reuse-hygiene"],
        "maximumDomainSkills": 3,
    }
    for path in paths:
        if not path.is_file():
            continue
        with path.open(encoding="utf-8") as stream:
            data = json.load(stream)
        if isinstance(data.get("routing"), dict):
            routing.update(data["routing"])
        for entry in data.get("skills", []):
            if isinstance(entry, dict) and entry.get("id"):
                merged_skills[str(entry["id"])] = entry
    return {"routing": routing, "skills": list(merged_skills.values())}


def route_task(
    task: str,
    registry_paths: list[Path] | None = None,
    code_change: bool | None = None,
    max_domain_skills: int | None = None,
) -> dict[str, Any]:
    paths = registry_paths or [DEFAULT_REGISTRY]
    catalog = load_merged_registry(paths)
    routing = catalog["routing"]
    limit = max(1, min(int(max_domain_skills if max_domain_skills is not None else routing.get("maximumDomainSkills", 3)), 3))

    normalized_task = " ".join(task.lower().split())
    task_tokens = _tokenize(normalized_task)
    is_code_change = bool(CODE_CHANGE_RE.search(normalized_task)) if code_change is None else bool(code_change)
    mandatory_ids = list(routing.get("mandatoryForCodeChanges", [])) if is_code_change else []
    router_id = str(routing.get("defaultRouter", "assured-arc-skill-router"))

    scored: list[dict[str, Any]] = []
    for skill in catalog["skills"]:
        skill_id = str(skill["id"])
        if skill_id == router_id or skill_id in mandatory_ids:
            continue
        score = 0.0
        matched: list[str] = []
        for trigger in skill.get("triggers", []):
            trig_norm = " ".join(str(trigger).lower().split())
            if not trig_norm:
                continue
            if re.search(rf"(?<![a-z0-9]){re.escape(trig_norm)}(?![a-z0-9])", normalized_task):
                score += 6.0 + (1.5 if " " in trig_norm else 0.0)
                matched.append(str(trigger))
                continue
            trig_tokens = _tokenize(trig_norm)
            overlap = trig_tokens & task_tokens
            if overlap and (len(overlap) / len(trig_tokens)) >= 0.5:
                score += 2.5 * (len(overlap) / len(trig_tokens))
                matched.append(str(trigger))

        purpose_tokens = _tokenize(str(skill.get("purpose", "")))
        id_tokens = _tokenize(skill_id.replace("assured-arc-", ""))
        score += len(purpose_tokens & task_tokens) * 0.6 + len(id_tokens & task_tokens) * 1.5
        if score > 0:
            scored.append({"id": skill_id, "category": skill.get("category", ""), "score": round(score, 2), "matchedTriggers": matched[:4]})

    scored.sort(key=lambda item: (-item["score"], item["id"]))
    selected_domain = [item["id"] for item in scored[:limit]]
    return {
        "task": task,
        "codeChange": is_code_change,
        "maximumDomainSkills": limit,
        "mandatorySkills": mandatory_ids,
        "domainSkills": selected_domain,
        "selectedSkills": mandatory_ids + selected_domain,
        "candidates": scored[: limit + 2],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Route a task objective to the smallest useful Assured Arc skill set.")
    parser.add_argument("task", help="Task description or user objective to classify.")
    parser.add_argument("--registry", action="append", default=[], help="Path to a skill-registry.json file.")
    parser.add_argument("--code-change", action="store_true", help="Force code-change mandatory skills.")
    parser.add_argument("--read-only", action="store_true", help="Force read-only routing.")
    parser.add_argument("--max-domain", type=int, default=None, help="Maximum domain skills to select (<= 3).")
    parser.add_argument("--json", action="store_true", help="Emit JSON output.")
    args = parser.parse_args(argv)

    registry_paths = [Path(p).expanduser().resolve() for p in args.registry] if args.registry else [DEFAULT_REGISTRY]
    code_flag: bool | None = True if args.code_change else (False if args.read_only else None)
    result = route_task(args.task, registry_paths=registry_paths, code_change=code_flag, max_domain_skills=args.max_domain)
    if args.json:
        sys.stdout.write(json.dumps(result, indent=2) + "\n")
    else:
        sys.stdout.write(f"Code change: {result['codeChange']}\n")
        sys.stdout.write(f"Mandatory skills: {', '.join(result['mandatorySkills']) or '(none)'}\n")
        sys.stdout.write(f"Domain skills (<= {result['maximumDomainSkills']}): {', '.join(result['domainSkills']) or '(none)'}\n")
        sys.stdout.write(f"Selected skills: {', '.join(result['selectedSkills']) or '(none)'}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
