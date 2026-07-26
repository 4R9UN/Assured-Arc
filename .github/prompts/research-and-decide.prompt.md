---
name: research-and-decide
description: "Research a dependency, technology, MCP server, extension, or architecture choice and produce an evidence-based recommendation."
argument-hint: "Name the technology or decision to evaluate"
agent: Assured Arc Research
---

Evaluate `${input:subject:Technology, dependency, or decision}` for this repository or use case.

- Prefer first-party documentation, source code, license, releases, and security advisories.
- Compare the native or existing alternative before recommending another dependency.
- Assess compatibility, permissions, authentication, network behavior, maintenance, lock-in, migration, and rollback.
- Separate verified facts from assumptions.
- Return: recommendation, evidence, risks, prerequisites, and a minimal adoption plan.

Do not install or configure the subject during this research prompt.
