---
name: multi-agent-change-review
description: "Review a change through independent correctness, security, reliability, and simplicity perspectives, then deduplicate findings."
argument-hint: "Provide the intended outcome or review focus"
agent: Assured Arc Orchestrator
---

Review the current change against `${input:requirement:Intended outcome}`.

- Run up to three read-only disposable critics in parallel with distinct dimensions: correctness and regression, security and privacy, and reliability and unnecessary complexity.
- Give every critic the same acceptance contract but only its assigned perspective.
- Do not allow critics to edit, execute, browse, call MCP, or see one another's findings.
- Deduplicate by root cause and calibrate severity.
- If an executable check is needed, use one disposable verifier with an approved command list.
- Return blocking, important, and advisory findings with exact evidence. State clearly when no actionable issue exists.
