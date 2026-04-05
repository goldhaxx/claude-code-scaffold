# Feature: Modular Tool Integration Layer

> Feature: tool-integration
> Created: 1774238505
> Status: Complete

## Summary

Introduces `scripts/operations.sh` — a mechanism-agnostic routing layer that reads `.claude/scaffold.json` and dispatches each scaffold operation (backlog, spec, plan, checkpoint, PR) to a pluggable provider via any supported mechanism (bash, MCP, CLI, API, or future additions). The workflow is the invariant; the tools are the variables. Zero-config projects continue to use local bash adapters with no behavior change.

## Job To Be Done

**When** a developer adds external tools to their scaffold (Linear, Notion, GitHub, or any future integration),
**I want to** route scaffold operations to those tools transparently via config,
**So that** the workflow (spec → plan → build → review) stays identical regardless of which provider and mechanism backs each operation.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `operations.sh resolve <operation>` with no `integrations` key in `.claude/scaffold.json` outputs JSON: `{"provider":"local","mechanism":"bash","invocation":{"command":"<shell command>"},"contract":{"output":[...]}}` for every defined operation name. Exit 0.

- [ ] **AC-2:** Given `integrations.routing.backlog: "linear"` and a `providers.linear` block with `"mechanism": "mcp"` in `.claude/scaffold.json`, `operations.sh resolve backlog.list` outputs JSON: `{"provider":"linear","mechanism":"mcp","invocation":{"tool":"mcp__claude_ai_Linear__list_issues","params":{"project":"<configured>","team":"<configured>"}},"contract":{"output":["id","title","status","priority"]}}`. Exit 0.

- [ ] **AC-3:** Given `integrations.routing.backlog: "linear"` with no matching entry in `providers`, `operations.sh resolve backlog.list` exits 1 with stderr: `ERROR: provider "linear" is configured for backlog but has no entry in integrations.providers`.

- [ ] **AC-4:** Partial routing config — when `integrations.routing` contains only `backlog`, all other operation groups (`spec`, `plan`, `checkpoint`, `pr`) resolve to their local adapters unchanged.

- [ ] **AC-5:** `operations.sh resolve backlog.list` local adapter command, when executed, produces JSON with the same schema as `docs-check.sh list-specs`: array of `{feature_id, status, created}` objects. Verified by running both commands against the same `docs/specs/` directory and comparing output schemas with `jq`.

- [ ] **AC-6:** `operations.sh resolve backlog.get <id>` with linear routing outputs JSON including `"mechanism":"mcp"`, `"tool":"mcp__claude_ai_Linear__get_issue"`, and a `"contract"` mapping Linear issue fields (`identifier`, `title`, `state.name`, `priority`) to scaffold contract fields (`id`, `title`, `status`, `priority`).

- [ ] **AC-7:** `.claude/commands/catchup.md` step 0c calls `operations.sh resolve backlog.list` instead of hardcoding `docs-check.sh list-specs`. Verified by: `grep -q "operations.sh resolve backlog.list" .claude/commands/catchup.md`.

- [ ] **AC-8:** `.claude/scaffold.json` with a valid `integrations` object passes `jq empty` validation. `ccanvil-sync.sh`'s `TRACKED_PATTERNS` array includes `.claude/scaffold.json` so the config file is tracked in the lockfile.

- [ ] **AC-9 (error):** `operations.sh resolve backlog.list` when `.claude/scaffold.json` contains invalid JSON exits 1 with stderr: `ERROR: .claude/scaffold.json is not valid JSON`.

- [ ] **AC-10 (error):** `operations.sh resolve unknown.op` exits 1 with stderr: `ERROR: unknown operation "unknown.op"`. Exit 1.

- [ ] **AC-11 (edge):** `operations.sh resolve <op>` when `.claude/scaffold.json` does not exist behaves identically to AC-1 (all local). No error, exit 0.

- [ ] **AC-12:** The `mechanism` field in resolve output is an extensible string (not a closed enum). Phase 1 implements `bash` and `mcp`. The schema accommodates `cli`, `api`, `sdk`, `webhook` without code changes — unknown mechanisms pass through as-is in the JSON output.

## Affected Files

| File | Change |
|------|--------|
| `scripts/operations.sh` | New — routing layer, subcommand `resolve` |
| `tests/operations.bats` | New — bats tests |
| `.claude/scaffold.json` | Modified — add `integrations` schema |
| `scripts/ccanvil-sync.sh` | Modified — add `.claude/scaffold.json` to `TRACKED_PATTERNS` |
| `.claude/commands/catchup.md` | Modified — call `operations.sh resolve backlog.list` in step 0c |
| `CLAUDE.md` | Modified — add `operations.sh` to Commands section |
| `GUIDE.md` | Modified — add to Command Reference table |

## Dependencies

- **Requires:** `jq` (already used by `ccanvil-sync.sh`, `docs-check.sh`, `context-budget.sh`)
- **Requires:** Linear MCP tools present in `settings.local.json` (already: `mcp__claude_ai_Linear__list_issues`, `mcp__claude_ai_Linear__get_issue`)
- **Blocked by:** Nothing
- **Research complete:** See `docs/research/tool-integration-landscape.md` for the full integration mechanism taxonomy (MCP, Agent SDK, plugins, CLIs, APIs, webhooks, gh-aw, A2A) that informed this design.

## Out of Scope

- Linear adapters for `spec`, `plan`, `checkpoint`, `status`, `pr`, `review` operation groups
- Notion adapter, GitHub adapter, Confluence adapter
- Multi-destination routing (writing to multiple providers simultaneously — see Design Consideration below)
- Wiring commands other than `/catchup`
- Auto-detection of available MCP tools from `settings.local.json`
- Migration tooling (moving data between providers)
- Data format translation between providers (e.g., markdown spec → Notion page structure)
- CLI mechanism (`linear issue list`, `gh issue list`) — Phase 2
- Webhook triggers — Phase 3
- Plugin packaging — Phase 4
- GitHub Agentic Workflows integration — Phase 5

## Design Consideration: Multi-Destination Routing and Document Granularity

> This section captures a design direction that Phase 1 must not preclude, even though it is out of scope for implementation.

**Per-document-type routing:** The operations taxonomy already separates `spec`, `plan`, and `checkpoint` as distinct operation groups. This granularity exists specifically so each document type can route to a different provider: specs to Linear, plans to Confluence, checkpoints to local. The Phase 1 config schema supports this natively via Level 2 routing.

**Multi-destination routing:** A user may want a spec to exist in Linear (for team visibility) AND locally (for deterministic validation via `docs-check.sh`). This is not "either/or" — it's "both." The local copy serves as the scaffold's validation layer (hash-based lifecycle state machine, spec↔plan alignment checks). The external copy serves as the collaboration layer.

The likely pattern:
```json
"routing": {
  "spec": ["linear", "local"],
  "plan": ["confluence", "local"],
  "checkpoint": "local"
}
```

Where a routing value is either a string (single provider) or an array (multi-destination, written in order). The first entry is the "primary" (source of truth for reads), all entries receive writes.

**Why this matters for Phase 1:** The `resolve` output schema must not assume a single provider per operation. Phase 1 returns a single resolution object (since only single-destination is implemented), but the schema should not break if a future phase returns an array. The simplest guard: Phase 1 always returns a single object, future phases may return `[{...}, {...}]` for multi-destination operations.

## Implementation Notes

- **Script pattern:** Follow `permissions-audit.sh` — `set -euo pipefail`, subcommand dispatch, JSON primary output, `--project-dir` flag pointing to directory containing `.claude/scaffold.json`.
- **Operations taxonomy** (all 17 defined, only backlog group gets Linear adapter in Phase 1): `backlog.{list,create,prioritize,get}`, `spec.{read,write,list,activate,complete}`, `plan.{read,write}`, `checkpoint.{read,write}`, `status.{get,update}`, `pr.{create,list}`, `review.run`.
- **Local adapter commands:** `backlog.list` → `docs-check.sh list-specs`; `backlog.get <id>` → read from `docs/specs/<id>.md`; spec/plan/checkpoint → corresponding `docs-check.sh` subcommands or direct file reads.
- **Mechanism-agnostic output:** The `mechanism` field is an extensible string. Phase 1 implements `bash` (local scripts) and `mcp` (MCP tool calls). Future phases add `cli` (direct CLI tools like `gh`, `linear`), `api` (REST/GraphQL), `sdk` (Agent SDK), `webhook` (event-driven). Unknown mechanisms pass through — the script doesn't validate mechanism values, allowing new mechanisms without code changes.
- **Config schema (three levels):**
  - **Level 1 — Providers:** What tools are available and how they connect. Each provider declares a default `mechanism`.
    ```json
    "providers": {
      "linear": { "mechanism": "mcp", "project": "...", "team": "..." },
      "github": { "mechanism": "cli" }
    }
    ```
  - **Level 2 — Routing:** Which provider backs which operation group.
    ```json
    "routing": { "backlog": "linear", "spec": "local", "plan": "local" }
    ```
  - **Level 3 — Overrides (future):** Per-operation mechanism override.
    ```json
    "overrides": { "backlog.create": { "mechanism": "api", "endpoint": "..." } }
    ```
  Only Levels 1 and 2 are implemented in Phase 1. Level 3 is a future enhancement.
- **Deterministic-first hierarchy for mechanisms:** When multiple mechanisms are available for the same operation, prefer deterministic over stochastic: `bash` > `cli` > `api` > `mcp` > `sdk`. The routing config is the source of truth — this hierarchy informs documentation and defaults, not runtime behavior.
- **Config fallback chain:** Missing file → all local. Missing `integrations` key → all local. Missing routing entry for a group → that group is local. `jq -r '.integrations.routing.<group> // "local"'`.
- **Routing groups:** An operation like `backlog.list` routes based on its group (`backlog`). All operations in a group share the same provider unless Level 3 overrides specify otherwise (future).
- **Test strategy:** `tests/operations.bats` uses fixture `.claude/scaffold.json` files in `mktemp -d`; assert JSON output with `jq -e`; assert exit codes and stderr content.

## Phased Roadmap

This spec is Phase 1 of a multi-phase effort. The full roadmap (from `docs/research/tool-integration-landscape.md`):

| Phase | Scope | Mechanisms |
|-------|-------|-----------|
| **1 (this spec)** | Operations abstraction + local refactor + Linear backlog proof | `bash`, `mcp` |
| **2** | CLI mechanism support (Linear CLI, GitHub CLI, Jira CLI) | `cli` |
| **3** | Webhook triggers via Agent SDK | `webhook`, `sdk` |
| **4** | Package scaffold as Claude Code plugin | (distribution) |
| **5** | GitHub Agentic Workflows integration | `gh-aw` |

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
