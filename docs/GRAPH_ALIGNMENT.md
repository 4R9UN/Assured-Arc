# Graph and Agent Alignment

## Decision

**Keep the current native harness. Do not add Agent-Graph to the default installation.**

The paper [Graphs Meet AI Agents: Taxonomy, Progress, and Future Opportunities](https://arxiv.org/abs/2506.18019) is a survey of how graph structures and AI agents can support each other. It is not a runtime, package, or feature that can be enabled.

The [Agent-Graph repository](https://github.com/keta1930/agent-graph) is a separate full stack platform. Its visual editor, persistent services, scheduling, nested workflows, and team features solve a broader problem than this local Assured Arc workbench. Adding that platform would introduce a second orchestration runtime and service dependencies without evidence that they improve Assured Arc’s target workflow.

The safe decision is selective adoption:

1. Keep explicit graph shaped relationships for phases, workers, skills, tools, vault links, and evaluation scenarios.
2. Keep the sparse coordinator topology, delegation depth one, one writer, independent verification, and bounded repair.
3. Use original graph visuals to make those relationships easier to inspect.
4. Add runtime graph machinery only after real failures demonstrate a need and a focused evaluation shows a benefit.

## Visual architecture

[![Animated pencil-style map of Assured Arc](assets/assured-arc-architecture.gif)](assets/assured-arc-architecture.svg)

The animation progressively reveals the graph-shaped relationships among host surfaces, policy, workers, context, and evidence. Open the [editable static SVG](assets/assured-arc-architecture.svg) for a motion-free version. The artwork uses a general pencil and paper visual vocabulary, not the characters, wording, or composition of the Agent-Graph artwork. The repository’s configuration, agents, hooks, and tests remain the source of truth.

## Alignment with the paper

| Paper theme | Current implementation | Alignment | Decision |
| --- | --- | --- | --- |
| Graphs for planning | The harness uses an explicit seven phase loop, acceptance contracts, stop conditions, and bounded repair | Partial | Keep the simple phase graph. Add task DAG metadata only if branching or resumable work repeatedly fails |
| Graphs for execution and tool use | Skills route capabilities, the tool policy classifies actions, hooks enforce budgets, and MCP access is isolated from editing | Strong | Keep the current deterministic routing and policy graph |
| Graphs for memory | The optional Obsidian vault uses MOCs, links, and portable Markdown | Partial and intentional | Keep memory local and opt in. Do not turn the vault into hidden execution state |
| Graphs for multi-agent coordination | One coordinator connects five context isolated worker roles with no worker to worker delegation | Strong for this scope | Preserve the sparse static topology rather than enabling dynamic nested graphs |
| Agents for graph construction and understanding | Generated registries and vault indexes make relationships inspectable, but no general graph synthesis agent is installed | Limited | Treat this as an optional documentation or analysis workflow, not a default runtime |
| Evaluation, privacy, and security challenges | Deterministic scenarios, exact tool policy, protected paths, metadata only traces, and human promotion gates are implemented | Strong foundation | Continue regression evaluation before any topology change |

## Comparison with Agent-Graph

| Concern | Native Assured Arc harness | Agent-Graph | Default choice here |
| --- | --- | --- | --- |
| Primary environment | Local VS Code and Copilot CLI workflow | Full stack visual multi-agent platform | Native workbench |
| Orchestration | Portable GitHub Copilot custom agents and disposable subagents | Graph editor and application runtime | Native workbench |
| Topology | Sparse, static, depth one | Dynamic and nested graph workflows | Sparse topology |
| Persistence | Installer state plus optional local Markdown vault | Persistent application services and storage | Local state only |
| Scheduling | Current interactive session | Scheduled and queued workflows | Out of scope |
| Collaboration | Single developer profile | Team and role features | Out of scope |
| Runtime dependencies | Selected Copilot host, shell, Node.js, Python, and reviewed MCP tools | Backend, frontend, database, object storage, and container deployment | Minimal reviewed set |
| Safety model | One writer, exact tool policy, approvals, rollback, and metadata only traces | Platform specific controls | Assured Arc controls |

Agent-Graph can be evaluated separately when a team explicitly needs a visual workflow product, persistent scheduling, nested multi-agent graphs, or shared role management. It should not be silently installed beside Assured Arc because the two systems have different ownership, persistence, and threat boundaries.

## What is enabled now

The following graph concepts are already enabled without a new runtime:

- A phase graph for contract, routing, delegation, action, verification, repair, and completion.
- A worker graph with one coordinator, five bounded roles, and one writer.
- A skill and capability graph backed by compact registries and lazy loading.
- A policy graph that maps tools to allow, ask, or deny decisions.
- An optional knowledge graph made from Obsidian MOCs and wikilinks.
- An evaluation graph made from event trajectories and expected decisions.

## Evidence required before adding more

A graph feature should be proposed only when repository evidence identifies a repeated failure. A proposal must define a measurable comparison against the current baseline.

| Candidate | Evidence needed | Minimum evaluation |
| --- | --- | --- |
| Task dependency DAG | Several real tasks fail because dependencies are lost, branches cannot be resumed, or ordering is ambiguous | Compare completion, tool calls, latency, and correction count against the current planner |
| Tool dependency graph | Repeated tool selection conflicts or invalid call ordering survive the existing exact policy | Add deterministic failure fixtures and show fewer routing errors without broader permissions |
| Runtime graph memory | Local vault retrieval repeatedly misses relevant context | Use sanitized local data and measure retrieval quality before adding storage or embeddings |
| Dynamic worker topology | The fixed five roles create a demonstrated quality or throughput bottleneck | Prove improvement under the same worker, tool, privacy, and repair budgets |
| Persistent scheduler | Users require approved work to continue outside an interactive VS Code session | Design a separate opt in service with explicit ownership, authentication, audit, and uninstall boundaries |

Until one of these conditions is met, extra graph infrastructure is speculative complexity.

## Sources

- [Graphs Meet AI Agents: Taxonomy, Progress, and Future Opportunities, arXiv:2506.18019v1, 22 June 2025](https://arxiv.org/abs/2506.18019v1)
- [Paper HTML](https://arxiv.org/html/2506.18019v1)
- [Agent-Graph repository](https://github.com/keta1930/agent-graph)
- [Agent-Graph project metadata](https://github.com/keta1930/agent-graph/blob/master/pyproject.toml)
- [VS Code custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents)
- [VS Code subagents](https://code.visualstudio.com/docs/agents/subagents)
- [VS Code hooks](https://code.visualstudio.com/docs/agent-customization/hooks)
