# Feature: Linear API substrate for bash scripts

> Feature: bts-164-linear-api-substrate
> Work: linear:BTS-164
> Created: 1777141479
> Status: In Progress

## Summary

Bash scripts in `.ccanvil/scripts/` are write-aware of the configured provider (`idea-add`, `ticket.transition` route through `operations.sh resolve` to Linear MCP) but read-blind: `cmd_idea_count` opens `.ccanvil/ideas.log` directly, bypassing the resolver. Skills can call MCP; scripts can't. The fix introduces a third resolver mechanism — `http` — and a `linear-query.sh` wrapper that hits Linear's GraphQL endpoint with `curl` + `jq` + `LINEAR_API_KEY` env-var auth. Both reads and writes route through the wrapper, so scripts and skills share one provider-aware substrate. Closes the read-path asymmetry surfaced repeatedly during `/recall` and `/radar`. Per-row consumers like `radar-gather` and `cmd_idea_count` become thin shims over the resolver.

## Job To Be Done

**When** I run `/recall` or `/radar` on a Linear-routed project,
**I want to** see live Linear state — not stale `.ccanvil/ideas.log` data — and have any bash script (cron prompts, audit-session, etc.) able to read or write Linear state without needing a skill in the call chain,
**So that** the system stops reporting confidently-wrong numbers and the bash surface gets symmetric provider awareness.

## Acceptance Criteria

- [ ] **AC-1:** `.ccanvil/scripts/linear-query.sh` exists with subcommands: `list-issues`, `get-issue`, `list-states`, `list-labels`, `save-issue`, `transition`. Each accepts JSON args on stdin or via flags; emits canonical JSON on stdout.
- [ ] **AC-2:** `linear-query.sh` exits 2 with `LINEAR_API_KEY not set` to stderr when env var is missing AND any subcommand other than `--help` is invoked. Exits 0 on `--help`.
- [ ] **AC-3:** `linear-query.sh` authenticates via the `Authorization: <api_key>` header (Linear's accepted form). All requests POST to `https://api.linear.app/graphql` with `Content-Type: application/json`.
- [ ] **AC-4:** `operations.sh resolve idea.list` returns `mechanism: "http"` with `invocation` carrying `endpoint`, `query` (GraphQL template), `variables`, and `auth_env: "LINEAR_API_KEY"` when `routing.idea = linear`. Same for `idea.count`, `idea.add`, `idea.triage`, `ticket.transition`, `ticket.get`, `backlog.list`.
- [ ] **AC-5:** `cmd_idea_count`, when called on a Linear-routed project, returns counts derived from a Linear API query — not from `.ccanvil/ideas.log`. The local-log fast path remains for `routing.idea = local`.
- [ ] **AC-6:** `radar-gather` JSON output reflects Linear state on Linear-routed projects (e.g., the `ideas.triage` count matches `linear-query.sh list-issues --state triage --label idea`).
- [ ] **AC-7:** Write mutations dispatched through the substrate succeed end-to-end against a stubbed GraphQL endpoint in tests: `save-issue` (create), `save-issue` with `id+state` (transition), `save-issue` with `id+priority` or `id+labels` (update).
- [ ] **AC-8:** `bats` coverage in `hub/tests/linear-query.bats` covers each subcommand against a stubbed endpoint (curl wrapper interceptable via `LINEAR_QUERY_ENDPOINT` env override) — query construction, response parsing, auth-missing exit.
- [ ] **AC-9 (edge):** With `routing.idea = local`, the resolver returns `mechanism: "bash"` for all idea/ticket verbs and `linear-query.sh` is never invoked. Local-log path continues to function unchanged.
- [ ] **AC-10 (provider neutrality):** Resolver output shape (`{provider, mechanism, invocation, contract}`) is uniform regardless of mechanism. Consumers can switch on `mechanism` without provider-specific branches in the calling script.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/linear-query.sh` | New — Linear GraphQL client wrapper (curl + jq) |
| `.ccanvil/scripts/operations.sh` | Modified — add `http` mechanism emission for Linear-routed verbs (`idea.*`, `ticket.*`, `backlog.list`); existing `mcp` paths preserved as a parallel option for skill consumers that still want MCP shape |
| `.ccanvil/scripts/docs-check.sh` | Modified — `cmd_idea_count` (line ~1841) and `radar-gather` (line ~1658) become resolver-aware; on `mechanism: http` they shell out to `linear-query.sh` |
| `hub/tests/linear-query.bats` | New — bats coverage for the wrapper (stub endpoint, query construction, auth) |
| `hub/tests/idea-count-resolver.bats` | New — coverage for `cmd_idea_count` resolver branching (local vs http paths) |
| `.ccanvil/guide/command-reference.md` | Modified — document `linear-query.sh` and the `http` mechanism |

## Dependencies

- **Requires:** `curl` and `jq` (already pinned in CLAUDE.md tech-stack section). `LINEAR_API_KEY` env var set by the operator.
- **Blocked by:** Nothing structural. Adjacent provider-onboarding workflow (separate ticket) is recommended but not required for shipping.

## Out of Scope

- **Provider-onboarding workflow** — the `/init --provider linear` flow that walks operators through API key setup. Captured as adjacent ticket; not a v1 deliverable here. v1 expects the env var to already be set and surfaces a clean error if not (AC-2).
- **Schema introspection / GraphQL fragment library** — v1 hand-writes the queries it needs.
- **Skill migration** — skills like `/idea` and `/permissions-review` currently call MCP directly; v1 leaves that path intact. Skills can opt into `http` later as a follow-up.
- **Multi-workspace support** — a single `LINEAR_API_KEY` against a single workspace.
- **Caching** — no client-side cache. If hot-loop usage emerges, revisit with a 5s TTL (per BTS-164 capture).
- **Webhooks / real-time events.**

## Implementation Notes

- Pattern: `linear-query.sh` is bash-as-script, follows the same shape as `permissions-audit.sh` (subcommands, JSON in/out, exit codes 0/2/3 for ok/usage/runtime). Reuses existing helpers — don't introduce a new framework.
- GraphQL templates live in heredocs inside the script. Keep them minimal — only the fields that callers actually use (`id`, `title`, `state`, `priority`, `labels`, `createdAt`).
- Endpoint override: tests set `LINEAR_QUERY_ENDPOINT` env to point at a local stub (a bats fixture serving canned JSON via `nc` or a fixture file). Production path defaults to `https://api.linear.app/graphql`.
- `cmd_idea_count`'s migration is the smallest user-visible win. Ship it first within the implementation phasing — that's where the recurring `/recall` bug lives. Resolver wiring + `radar-gather` migration follow once the wrapper is proven end-to-end.
- Self-application: this substrate will itself unblock BTS-163 (release primitive) by giving releases the Linear-side parity needed for `release.migrate`. Reflect that sequencing in the plan when it's written.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
