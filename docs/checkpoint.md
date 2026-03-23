# Checkpoint

> Feature: tool-integration
> Last updated: 1774299317
> Plan hash: 2fce56f9
> Session objective: Research, spec, and plan BTS-19 (Modular Tool Integration Layer)

## Accomplished

### BTS-19 research and design
- Conducted deep research on tool integration mechanisms: MCP, Agent SDK, plugins, CLIs, APIs, webhooks, gh-aw, A2A protocol.
- Research report saved to `docs/research/tool-integration-landscape.md` and as a Linear project document.
- Key finding: abstraction must be mechanism-agnostic, not MCP-specific. 12 integration mechanisms identified, falling into 3 determinism tiers.

### BTS-19 spec written and activated
- Spec at `docs/specs/tool-integration.md` with 12 ACs covering: routing layer, local adapter, Linear MCP adapter, error handling, extensible mechanisms, config schema, /catchup wiring.
- Design consideration added for multi-destination routing (spec in Linear AND local simultaneously).
- Phased roadmap: 5 phases from bash+mcp through plugin distribution and gh-aw integration.
- Spec activated on branch `claude/feat/tool-integration`.

### BTS-19 plan written
- 11-step TDD plan at `docs/plan.md`. Steps build from skeleton through full taxonomy, MCP routing, schema compat, and documentation.

### README augmented
- New "What This Is" section: defines scaffold purpose (bootstrap for any repo), target persona (Claude Code developers), progressive unlock model (local → MCP → CLI → SDK → plugin).

### Housekeeping
- Cleaned up stale checkpoint and spec from completed features (permissions-audit, context-budget).
- Updated all memory files: ZWR → BTS, Zwright → Blocktech Solutions (Linear team rename).
- Updated Linear: BTS-19 labeled `has-spec`, research doc linked.

## Current State

- **Branch:** `claude/feat/tool-integration`
- **Tests:** 301/301 passing
- **Uncommitted changes:** This checkpoint
- **Build status:** Clean

## Blocked On

- Nothing

## Next Steps

1. Start Step 1 of the plan: script skeleton + unknown operation error (AC-10)
2. Continue through Steps 2-11 in TDD order
3. After all steps pass, `/review` then `/pr`

## Context Notes

- The spec's design consideration on multi-destination routing is critical: Phase 1 resolve output must not preclude returning arrays in future phases.
- macOS ships bash 3 — no associative arrays. Use case statements for operation registry.
- Linear MCP tool names must match `settings.local.json` allowlist entries exactly.
- The `integrations` config in scaffold.json starts empty (no routing, no providers) — everything defaults to local.

## Determinism Review

- **operations_reviewed:** 8
- **candidates_found:** 0
- Research conducted via sub-agents (isolated context, deterministic delegation).
- Spec written by spec-writer sub-agent (isolated context).
- Linear updates via MCP tools (deterministic API calls).
- All file operations used dedicated tools (Read, Write, Edit — not manual cat/sed).
- No manual cp, jq, shasum, or git -C commands improvised outside scripts.
- No candidates this session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
