# Tool Integration Landscape — Research Report

> **Research date:** 2026-03-23
> **Related issue:** BTS-19 (Modular tool integration layer)
> **Scope:** Integration mechanisms available for agentic development scaffolds — MCP, SDKs, CLIs, APIs, plugins, webhooks, and emerging protocols
> **Prior research:** [Agentic Git Workflows](agentic-git-workflows.md) (2026-03-22)
> **Linear doc:** [Tool Integration Landscape](https://linear.app/zwright/document/tool-integration-landscape-research-report-5d28f69ac19c)

---

## Table of Contents

1. [Why This Research Exists](#1-why-this-research-exists)
2. [Integration Mechanism Taxonomy](#2-integration-mechanism-taxonomy)
3. [Per-Mechanism Findings](#3-per-mechanism-findings)
4. [How the Best Teams Integrate](#4-how-the-best-teams-integrate)
5. [Design Implications for the Scaffold](#5-design-implications-for-the-scaffold)
6. [Recommendations](#6-recommendations)

---

## 1. Why This Research Exists

BTS-19 defines an operations abstraction layer for the scaffold — a routing system that dispatches workflow operations (backlog, specs, plans, etc.) to pluggable providers. The initial spec assumed two adapter types: `bash` (local scripts) and `mcp` (MCP tool calls).

This research asks: **is that sufficient?** If the scaffold is distributed widely, people will connect it to Linear, Notion, GitHub, Slack, CI/CD pipelines, custom APIs, and tools that don't exist yet. The abstraction needs to accommodate all of them without refactoring.

The prior agentic-git-workflows research (2026-03-22) established what the best teams are doing in terms of workflow. This report focuses specifically on **how tools connect** — the integration mechanisms themselves.

---

## 2. Integration Mechanism Taxonomy

Every mechanism for connecting tools to an AI coding agent, classified by four dimensions:

| Mechanism | Deterministic? | Context cost | Runs where | Direction |
|-----------|---------------|-------------|------------|-----------|
| **Bash/CLI** | Yes | Low (cmd + stdout) | Script/shell | Agent-initiated |
| **MCP (Model Context Protocol)** | Execution: yes; Selection: no | Medium (tool descriptions always loaded) | Claude runtime | Bidirectional |
| **Agent SDK** | No (stochastic agent loop) | Isolated process | Separate runtime | Programmatic |
| **REST API (direct)** | Yes | Low (curl output) | Script/shell | Agent or script-initiated |
| **Plugins** | Mixed | On-demand | Claude Code | Extension |
| **Webhooks (inbound)** | Trigger: yes; Handling: varies | Event payload as prompt | External to scaffold | Event-driven |
| **Webhooks (outbound)** | Yes (side effect) | None | Script/shell | Scaffold to external |
| **GitHub Agentic Workflows** | Compilation: yes; Execution: no | Markdown at runtime | GitHub Actions | Event-driven |
| **Sub-agents** | No (stochastic) | Isolated context window | Claude (child process) | Parent delegates |
| **A2A (Agent-to-Agent)** | Protocol: yes; Behavior: no | Between agents | Cross-agent | Agent-to-agent |
| **LSP (Language Server Protocol)** | Yes | Code intelligence | Background process | Passive |
| **File-based (CLAUDE.md, rules)** | No (instruction-following) | Always loaded or on-demand | Claude context | Passive |

**Key observation:** These mechanisms fall into three categories based on the deterministic-first principle:

1. **Fully deterministic** — Bash/CLI, direct API, outbound webhooks, LSP. Same input, same output. Belong in scripts/hooks.
2. **Deterministic execution, stochastic selection** — MCP, plugins. The tool does the same thing every time, but Claude decides *when* to call it. Routing decision can be made deterministic via config.
3. **Fully stochastic** — Agent SDK, sub-agents, A2A. An agent loop with judgment. Reserve for genuinely semantic tasks.

---

## 3. Per-Mechanism Findings

### 3.1 MCP (Model Context Protocol)

**What it is:** A standardized protocol for connecting AI models to external tools and data sources. 1,000+ community-maintained servers available. Supported by Claude, ChatGPT, Cursor, and most major AI coding tools.

**How it works in the scaffold:** MCP servers run as separate processes. Claude discovers available tools from their descriptions, decides when to call them, and receives structured results. Tool descriptions are always loaded into context (competing for attention weight). Results also consume context.

**Strengths:**
- Universal protocol — works across AI tools
- Agent can dynamically discover and combine operations
- Fine-grained per-tool permissions in Claude Code
- Community-maintained servers reduce integration burden

**Weaknesses:**
- Tool descriptions consume context budget even when unused
- Agent decides when to call — introduces non-determinism in selection
- Slightly higher latency than direct calls (abstraction layer overhead)
- Server quality varies across community implementations

**When to use:** When the agent needs to dynamically choose between operations, or when you want tool portability across AI platforms.

**When NOT to use:** For known, static operations where the scaffold always calls the same thing. Use CLI/API instead — lower context cost, fully deterministic.

### 3.2 Claude Agent SDK

**What it is:** A library (Python and TypeScript) that provides the same agent loop, tools, and context management that power Claude Code, but programmable. Python package at v0.1.48; TypeScript at v0.2.71.

**How it works:** Call `query()` with a prompt and options. Claude autonomously reads files, runs commands, edits code, and loops until done. The SDK handles the tool loop — you don't implement one.

**Critical capability:** The SDK supports `settingSources: ['project']`, which loads `.claude/skills/`, `.claude/commands/`, `CLAUDE.md`, and hooks from `settings.json`. This means an SDK-based agent **inherits the full scaffold configuration**. A CI/CD agent built with the SDK would use the scaffold's TDD skills, spec templates, and deterministic hooks programmatically.

**Key primitives:**

| Primitive | Description |
|-----------|-------------|
| Built-in tools | Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch |
| Custom tools | In-process MCP servers via `create_sdk_mcp_server()` — wrap any Python/TS function as a tool |
| Hooks | Callbacks for PreToolUse, PostToolUse, Stop, SubagentStart/Stop, Notification — deterministic, zero context cost |
| Subagents | Isolated agent instances with own context windows |
| Sessions | Resume/fork via session_id — maintains full conversation history |

**When to use:** CI/CD pipelines, custom applications, production automation. When you need the scaffold's workflow programmatically rather than interactively.

**When NOT to use:** Day-to-day interactive development (use Claude Code CLI instead).

### 3.3 Bash/CLI Tools

**What it is:** Direct command execution via shell. Includes tools like `gh` (GitHub CLI), `linear` (Linear CLI), `jira`, `curl`, `jq`, and any other command-line tool.

**Strengths:**
- Zero context cost beyond command + output
- Fully deterministic
- Already the scaffold's primary integration mechanism

**Weaknesses:**
- No dynamic discovery — you must know the exact command
- Auth management is manual (tokens, config files)
- Limited to what the CLI exposes (not always full API coverage)

**When to use:** For known operations with predictable inputs. The scaffold's default mechanism. Any operation that can be expressed as a single CLI command should be.

### 3.4 Direct REST API

**Decision framework — API vs MCP:**

| Factor | Direct API | MCP |
|--------|-----------|-----|
| Latency | 5-15ms lower | Slightly higher (abstraction overhead) |
| Flexibility | Maximum control | Constrained to MCP primitives |
| Agent autonomy | None — script decides | Full — agent discovers and decides |
| Security | Manual auth management | Built-in per-tool permissions |
| Maintenance | You maintain integration code | Community-maintained servers |

**When to use:** Batch operations, regulated environments, or when you need maximum control over error handling and retries. Also useful when no MCP server exists for a service.

### 3.5 Claude Code Plugins

**What it is:** A packaging and distribution system for Claude Code capabilities. 13 official Anthropic plugins + 9,000+ community plugins (though only ~50-100 are production-ready as of March 2026).

**Plugin structure:**
```
plugin-name/
  .claude-plugin/
    plugin.json          # Manifest
  commands/              # Slash commands
  agents/                # Sub-agents
  skills/                # SKILL.md files
  hooks/
    hooks.json           # Event handlers
  .mcp.json              # MCP server configs
  .lsp.json              # LSP server configs
  settings.json          # Default settings
```

**Relevance to the scaffold:** The scaffold's `.claude/` directory structure maps almost directly to the plugin structure. Converting the scaffold to a distributable plugin is a straightforward packaging step. Plugins namespace their skills (`/plugin-name:skill-name`), preventing conflicts when multiple plugins coexist.

**Notable official plugins:**
- `code-review` — 5 parallel Sonnet agents + confidence scoring
- `feature-dev` — 7-phase feature development workflow with 3 agents
- `commit-commands` — git automation (`/commit`, `/commit-push-pr`)
- `pr-review-toolkit` — 6 specialized PR review agents

**When to use:** For distributing scaffold capabilities to other teams/projects. Also for consuming third-party capabilities without writing custom integrations.

### 3.6 Webhooks (Event-Driven)

**Production implementations:**
- **Cursor Automations** (launched March 2026): Built-in triggers from Slack, Linear, GitHub, PagerDuty, cron schedules, and custom webhooks. Agent spins up in cloud sandbox.
- **Custom implementations:** HTTP server or serverless function receives webhook, validates payload, spawns agent with event context as prompt.

**Pattern:**
1. External event fires (GitHub PR merged, Linear issue created, Slack message)
2. Webhook delivers JSON payload to endpoint
3. Receiver validates + routes
4. Agent spins up with event context as prompt (via Agent SDK)
5. Agent executes using scaffold configuration
6. Agent posts results back via API/webhook callback

**When to use:** For connecting external system events to scaffold workflows. Examples: Linear issue creation triggers spec-writer agent; GitHub PR merge triggers documentation update; Slack bug report triggers investigation.

### 3.7 GitHub Agentic Workflows (gh-aw)

**What it is:** Markdown-authored automation that compiles to GitHub Actions YAML. Technical preview since February 2026. Supports pluggable agent engines: Copilot CLI, Claude Code, OpenAI Codex.

**How it works:**
1. Write a markdown file in `.github/workflows/<name>.md` with YAML frontmatter + natural language instructions
2. Run `gh aw compile` to generate a `.lock.yml` file (hardened GitHub Actions YAML)
3. Commit both files. The `.lock.yml` runs in Actions, invoking a coding agent in a containerized environment

**Security model (default deny):**
- Read-only permissions by default
- Write operations restricted to "safe-outputs" (sanitized GitHub primitives)
- PRs are never merged automatically — human review mandatory
- Tool allow-listing, compile-time validation, SHA-pinned dependencies

**Explicit design principle:** *"Do not use agentic workflows as a replacement for GitHub Actions YAML workflows for CI/CD."* Deterministic CI/CD stays in YAML. Agentic workflows handle subjective/repetitive tasks: issue triage, documentation, test improvement, code simplification.

**Six automation patterns:** Continuous Triage, Continuous Documentation, Continuous Simplification, Continuous Testing, Continuous Quality, Continuous Reporting.

**When to use:** For CI/CD-triggered agentic tasks. The scaffold could define agentic workflows as markdown that compile to Actions, using Claude as the engine with scaffold configuration inherited via the repo.

### 3.8 A2A (Agent-to-Agent Protocol)

**What it is:** A protocol initiated by Google and now under the Linux Foundation for inter-agent communication. 50+ enterprise partners. Complements MCP (which provides tools/context to a single agent) by enabling agents from different providers to collaborate.

**Capabilities:** Async agent-to-agent communication, capability discovery, negotiation, task delegation across agent boundaries.

**When to use:** Future consideration. Relevant if the scaffold ever needs agents from different providers (Claude, Copilot, Codex) to collaborate on the same workflow.

---

## 4. How the Best Teams Integrate

Cross-referencing this research with the agentic-git-workflows findings:

### QuantumBlack (McKinsey)
**Integration model:** Engine orchestrates, agents execute. The workflow engine handles ALL deterministic operations (git, state machine transitions). Agents receive bounded inputs and produce artifacts. No agent touches git directly.

**Mechanisms used:** Custom orchestration engine (deterministic), LLM agents for semantic tasks (stochastic), two-layer evaluation gates (deterministic checks + critic agent).

**Lesson:** The integration layer IS the orchestration engine. Tools don't plug into agents — they plug into the engine, which routes to agents when judgment is needed.

### Ramp
**Integration model:** Cloud VMs (Modal) per session, Cloudflare Durable Objects for state. Fresh GitHub tokens per clone, dynamic git config per session.

**Mechanisms used:** Direct API (GitHub OAuth tokens for PR attribution), cloud sandbox execution, webhook-like session signaling (sandbox pushes, then API receives branch name + session ID).

**Lesson:** Attribution and security require integration at the API level, not the MCP level. PR creation via user's OAuth token prevents self-approval vulnerabilities.

### incident.io
**Integration model:** Local-first with worktrees. Custom bash function `w` abstracts worktree management. 4-5 parallel agents.

**Mechanisms used:** Bash/CLI (git worktree commands), Claude Code CLI, voice input (SuperWhisper).

**Lesson:** The simplest integration (bash + CLI) scales to production multi-agent workflows when the abstraction is right.

### GitHub Agentic Workflows
**Integration model:** Deterministic CI/CD (YAML) separated from stochastic agentic tasks (Markdown). Compiled from markdown to hardened Actions YAML.

**Mechanisms used:** gh-aw compilation, GitHub Actions runtime, pluggable agent engines, safe-output primitives.

**Lesson:** The compilation step (markdown to YAML) is a deterministic transform that hardens stochastic instructions. This pattern — deterministic wrapper around stochastic content — recurs everywhere.

### Cursor Automations
**Integration model:** Event-driven. Built-in triggers from Slack, Linear, GitHub, PagerDuty. Agent spins up in cloud sandbox.

**Mechanisms used:** Webhooks (inbound triggers), MCP (tool connections), cloud sandboxes (isolation), built-in memory (learning from past runs).

**Lesson:** Webhook-to-agent is a production-ready pattern. The trigger is deterministic; the handling is stochastic; the result is posted back via API (deterministic).

---

## 5. Design Implications for the Scaffold

### 5.1 The Abstraction Must Be Mechanism-Agnostic

The BTS-19 spec's `type: "bash" | "mcp"` is insufficient. The operations layer should declare **what** (contract), **who** (provider), and **how** (mechanism) independently:

```
Operation: backlog.list
  Provider: local    -> Mechanism: bash    -> Command: docs-check.sh list-specs
  Provider: linear   -> Mechanism: mcp     -> Tool: mcp__claude_ai_Linear__list_issues
  Provider: linear   -> Mechanism: cli     -> Command: linear issue list --json
  Provider: linear   -> Mechanism: api     -> Endpoint: POST api.linear.app/graphql
  Provider: github   -> Mechanism: cli     -> Command: gh issue list --json
```

The same provider can use different mechanisms. The same mechanism can serve different providers. The routing config separates these concerns.

### 5.2 Mechanisms Map to the Deterministic-First Hierarchy

The scaffold's existing hierarchy (hook, then script, then command, then pure reasoning) maps cleanly to integration mechanisms:

| Hierarchy level | Mechanisms | When to use |
|----------------|------------|-------------|
| **Hook** (zero context cost) | Webhooks (outbound), file watchers | Binary triggers: block, notify, format |
| **Script** (one command) | Bash/CLI, direct API, outbound webhooks | Known operations with predictable I/O |
| **Command** (script + judgment) | MCP, plugins, sub-agents | Routing is deterministic, execution needs discovery |
| **Pure reasoning** | Agent SDK, A2A, sub-agents | Genuinely semantic tasks: merge proposals, classification |

This means the routing layer itself should enforce the hierarchy: if a mechanism is deterministic, prefer it over a stochastic alternative for the same operation.

### 5.3 The Agent SDK Is the CI/CD Bridge

The Agent SDK's `settingSources: ['project']` capability means a programmatic agent inherits the full scaffold. This is the path to:
- CI/CD agents that run TDD workflows on PRs
- Automated spec validation
- Webhook receivers that spawn scaffold-aware agents
- GitHub Agentic Workflows using Claude as engine with scaffold context

The scaffold doesn't need to build any of this directly — it just needs to remain compatible with the SDK's loading mechanism (which it already is, since the SDK reads `.claude/` configuration).

### 5.4 Plugins Are the Distribution Path

The scaffold's `.claude/` structure maps directly to the plugin format. When the scaffold is ready for wider distribution, packaging it as a plugin provides:
- Namespaced skills/commands (no conflicts with other plugins)
- Version management
- Easy installation across projects
- Community discoverability

This doesn't require code changes — it's a packaging decision.

### 5.5 The Config Schema Needs Three Levels

Based on the research, the `scaffold.json` integrations config should support:

**Level 1 — Provider declaration:** What tools are available and how they connect.
```json
"providers": {
  "linear": { "mechanism": "mcp", "project": "Claude Code Scaffold" },
  "github": { "mechanism": "cli" },
  "notion": { "mechanism": "mcp", "workspace": "..." }
}
```

**Level 2 — Operation routing:** Which provider backs which operation.
```json
"routing": {
  "backlog": "linear",
  "spec": "local",
  "plan": "local",
  "checkpoint": "local",
  "pr": "github"
}
```

**Level 3 — Mechanism override:** For specific operations that need a different mechanism than the provider default.
```json
"overrides": {
  "backlog.create": { "mechanism": "api", "endpoint": "..." }
}
```

Level 3 is a future enhancement. Levels 1 and 2 are sufficient for Phase 1.

---

## 6. Recommendations

### For the BTS-19 Spec (immediate)

1. **Replace `"type"` with `"mechanism"`** in the resolve output schema. Make it an extensible string, not a closed enum. Phase 1 implements `bash` and `mcp`; the schema accommodates `cli`, `api`, `sdk`, `webhook` without code changes.

2. **Add `"mechanism"` to provider config** so Linear can be `"mechanism": "mcp"` today and `"mechanism": "cli"` tomorrow without changing routing.

3. **Add the mechanism-to-hierarchy mapping** to implementation notes. When multiple mechanisms are available for the same operation, prefer deterministic over stochastic.

4. **Remove the dependency** on "understanding which tools are commonly connected via MCP in practice." This research answers it: MCP is one of many mechanisms. The abstraction is mechanism-agnostic by design.

### For Future Phases

5. **Phase 2:** Add `cli` mechanism support. Linear CLI, GitHub CLI, and Jira CLI are all mature and deterministic. This shifts operations from stochastic (MCP) to deterministic (CLI) where possible.

6. **Phase 3:** Add webhook trigger support. Linear issue creation triggers spec-writer agent. GitHub PR merge triggers documentation update. Uses Agent SDK as the runtime.

7. **Phase 4:** Package scaffold as a Claude Code plugin for distribution. No code changes — packaging and manifest only.

8. **Phase 5:** GitHub Agentic Workflows integration. Define scaffold workflows as markdown that compile to Actions. Monitor gh-aw as it exits technical preview.

9. **Watch:** A2A protocol for cross-agent collaboration. Not actionable yet, but the operations abstraction should not preclude it.

---

## Sources

### Claude Agent SDK
- [Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Agent SDK Hooks](https://platform.claude.com/docs/en/agent-sdk/hooks)
- [Agent SDK Custom Tools](https://platform.claude.com/docs/en/agent-sdk/custom-tools)
- [Building Agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)
- [claude-agent-sdk-python (GitHub)](https://github.com/anthropics/claude-agent-sdk-python)
- [claude-agent-sdk-typescript (GitHub)](https://github.com/anthropics/claude-agent-sdk-typescript)

### Claude Code Plugins
- [Create Plugins (official docs)](https://code.claude.com/docs/en/plugins)
- [Official Plugins README](https://github.com/anthropics/claude-code/blob/main/plugins/README.md)
- [awesome-claude-plugins (Composio)](https://github.com/ComposioHQ/awesome-claude-plugins)
- [awesome-claude-code (hesreallyhim)](https://github.com/hesreallyhim/awesome-claude-code)

### MCP vs Direct API
- [MCP vs Direct API for AI Integration (2026 Guide)](https://modelslab.com/blog/api/mcp-vs-direct-api-ai-integration)
- [API vs. MCP: Everything You Need to Know (Composio)](https://composio.dev/content/api-vs-mcp-everything-you-need-to-know)
- [MCP vs APIs: When to Use Which (Tinybird)](https://www.tinybird.co/blog/mcp-vs-apis-when-to-use-which-for-ai-agent-development)

### GitHub Agentic Workflows
- [gh-aw Official Docs](https://github.github.com/gh-aw/)
- [Creating Workflows](https://github.github.com/gh-aw/introduction/overview/)
- [gh-aw GitHub Repository](https://github.com/github/gh-aw)
- [GitHub Changelog Announcement](https://github.blog/changelog/2026-02-13-github-agentic-workflows-are-now-in-technical-preview/)

### Event-Driven / Webhooks
- [Cursor Automations](https://cursor.com/blog/automations)
- [Cursor Automations Docs](https://cursor.com/docs/cloud-agent/automations)
- [Webhook in Agentic AI (2026 Guide)](https://interviewkickstart.com/blogs/articles/webhook-in-agentic-ai)

### Multi-Language / Orchestration
- [The 2026 Guide to Agentic Workflow Architectures](https://www.stackai.com/blog/the-2026-guide-to-agentic-workflow-architectures)
- [Bash to Agentic AI: Evolving DevOps Scripts](https://medium.com/devops-ai-decoded/bash-to-agentic-ai-evolving-your-10-essential-devops-scripts-for-2026-37880da0305c)

### Protocols
- [A2A Protocol (Google)](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)
- [A2A Protocol (official)](https://a2a-protocol.org/latest/)
- [AI Agent Protocols 2026: Complete Guide](https://www.ruh.ai/blogs/ai-agent-protocols-2026-complete-guide)

### Cross-Reference: Agentic Git Workflows Research
- [QuantumBlack: Agentic Workflows for Software Development](https://medium.com/quantumblack/agentic-workflows-for-software-development-dc8e64f4a79d)
- [Ramp: Why We Built Our Own Background Agent](https://builders.ramp.com/post/why-we-built-our-background-agent)
- [incident.io: Shipping Faster with Claude Code and Git Worktrees](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees)
- [GitHub: Spec-Driven Development with spec-kit](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)
