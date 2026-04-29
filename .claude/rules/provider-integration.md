---
manifest:
  id: provider-integration
  purpose: Codify the BTS-183 substrate-provider rule — anything reachable from operations.sh that integrates with an external provider exposing both MCP and shell-to-API surfaces (REST/GraphQL/CLI) MUST use the shell-to-API surface, never MCP. MCP is reserved for ad-hoc operator queries from interactive Claude sessions via claude.ai connectors. Captures the 7-row tradeoff matrix that justifies the choice and the OVERRIDE-pattern stubbing convention for tests.
  input:
    - "read-only: rule consumed when adding new operations.sh resolvers or extending wrappers"
  output:
    - "behavior-shape: forces new substrate verbs to land as shell-to-API subcommands first; rejects mechanism: mcp branches in operations.sh"
  side-effect:
    - "shapes-substrate-design (no file mutation; behavioral influence)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=mixed-mode-substrate-drift-then-200-LOC-dead-code-sweep | mitigation=/review-flag-or-stasis-determinism-review"
  contract:
    - http-for-substrate
    - mcp-for-operator-tools-only
    - new-verbs-land-as-wrapper-subcommands-first
    - never-add-mechanism-mcp-resolution-for-new-verbs
    - OVERRIDE-pattern-stubbing-for-tests
  anchor:
    - BTS-164 (Linear daily-driver migration MCP→http)
    - BTS-166 (substrate dispatch via http)
    - BTS-167 (.env auto-source)
    - BTS-183 (rule + dead-code sweep)
    - BTS-203 (LINEAR_QUERY_OVERRIDE stubbing pattern)
    - BTS-252 (manifest seed)
---

# Provider Integration: http for substrate, MCP for operator tools

## The Rule

When integrating ccanvil substrate (anything reachable from `.ccanvil/scripts/operations.sh`) with an external provider that exposes both an MCP server AND a shell-to-API surface (REST/GraphQL/CLI), **always use the shell-to-API surface — never MCP**. MCP is reserved for ad-hoc operator queries from inside an interactive Claude session, dispatched via the user-level claude.ai connectors. It is not a substrate path; it is not maintained as a parallel substrate.

This is canonical. New verbs land as new shell-to-API subcommands (e.g., new `linear-query.sh` subcommands for Linear, new `gh` subcommands or wrappers for GitHub, etc.). Mixed-mode drift — half the verbs on MCP, half on http — is what produced the 200-LOC dead-code sweep that anchored this rule (BTS-183).

## Why http won

Anchored on the BTS-164/166/167 migration of Linear daily-driver verbs from MCP → http. Live evidence:

| Dimension | MCP | http (shell-to-API) |
|------|------|---------------------|
| LLM in the loop per call | yes | no |
| Speed for batched ops | LLM round-trip per call | one round-trip + N shell calls |
| Token cost | nontrivial | zero |
| Capability ceiling | what MCP exposes | full GraphQL/REST — any field, any mutation |
| Failure recovery | tool result, agent interprets | clean exit codes; pending-log fallback |
| Test surface | mock MCP server | mock GraphQL with fixtures |
| Auth model | MCP server config | one env var (e.g., `LINEAR_API_KEY`) + `.env` auto-source |

Each row is a real friction surface that hit the migration. Test surface alone — being able to stub `linear-query.sh` via `LINEAR_QUERY_OVERRIDE` and write deterministic bats coverage — has unblocked dozens of bats fixtures across BTS-203, BTS-205, BTS-211, BTS-237, etc.

## Why MCP for operator tools

The unique MCP advantage: **operator-friendly ad-hoc queries inside an interactive session**. Typing "show me BTS-21" or "what was my last meeting" and having Claude fetch via the connector is exactly what MCP is for. It's a different contract: discoverable, conversational, semantic — not deterministic.

This is preserved by keeping MCP available at the user level (claude.ai connectors, `mcp__claude_ai_*` tools). The substrate path — anything an `operations.sh` resolver might dispatch — is the question; and the answer is http.

## How to Apply

When adding a new operation to `operations.sh`:

1. **Ask:** is the provider already integrated via shell-to-API? If yes → resolve to that. If no → write the wrapper FIRST (e.g., extend `linear-query.sh` with a new subcommand), THEN add the resolver.
2. **Never** add a `mechanism: "mcp"` resolution branch to `operations.sh` for any new verb.
3. When extending an existing wrapper, prefer adding new subcommands over coupling more behavior into the resolver itself. The wrapper handles auth + GraphQL/REST shape; the resolver only computes which command to run.
4. Test via the OVERRIDE pattern (`LINEAR_QUERY_OVERRIDE`, `GH_OVERRIDE`, `LQ_OVERRIDE` for new providers): set an env var that lets bats substitute a stubbed wrapper script. Mirrors `BTS-203`.

## Out of Scope

- **Migrating `claude_ai_Linear` MCP usage out of interactive sessions.** That stays — operator tool, not substrate.
- **Deprecating MCP at the Claude Code level.** Not our call.
- **Generalizing this rule to specific future providers** (GitHub, Notion, etc.). Each provider audits before its first substrate integration; the rule is the default.

## Anchors

- BTS-183 (this rule + sweep of dead-code MCP branches).
- BTS-164 / BTS-166 / BTS-167 (the migration that motivated the rule).
- BTS-203 (stubbing pattern — `LINEAR_QUERY_OVERRIDE`).
- `.claude/rules/deterministic-first.md` (parent principle: minimize subprocess work; this rule is its provider-integration corollary).
