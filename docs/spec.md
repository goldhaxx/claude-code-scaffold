# Feature: backlog.list canonical for "what's left" — http migration + Linear-route fallback

> Feature: bts-175-backlog-list-canonical
> Work: linear:BTS-175
> Created: 1777184242
> Status: In Progress

## Summary

`/recall` and `/radar` consume `operations.sh resolve backlog.list` to surface the canonical "what's in the backlog" view. On this project today, that resolver falls through to local `docs-check.sh list-specs` (empty here — specs aren't kept after squash-merge) because `routing.backlog` is unset, even though `routing.idea = linear` AND `state_ids.backlog` are both configured. As a workaround, Claude session reasoning has reached for `idea.list` (label-filtered) instead, silently hiding scaffold-labeled tickets. Surfaced 2026-04-26 when Claude reported "P3=0, P4=0, backlog effectively annihilated" three turns running, while four scaffold-labeled tickets sat in Backlog state. Fix: (1) migrate Linear `backlog.list` resolver from `mechanism: mcp` to `mechanism: http` (parity with `idea.list`), filtering by `--state <backlog_state_id>` only — NO label filter; (2) extend the routing fallback so the `backlog` group inherits `routing.idea` when `state_ids.backlog` is configured (mirrors the existing `work`/`ticket` fallback at operations.sh:883); (3) update `/recall` step 0c and `/radar` step 2 prose to handle the `http` mechanism and explicitly forbid using `idea.list` as a backlog proxy.

## Job To Be Done

**When** I run `/recall` or `/radar` on a Linear-routed project,
**I want** the "what's in the backlog" view to surface ALL items in Backlog state — regardless of label,
**So that** Claude reasoning about "what should I ship next?" sees the canonical truth, not a label-filtered subset that silently hides scaffold-labeled tickets.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** On a project with `routing.idea = linear` AND `state_ids.backlog` configured (no `routing.backlog` entry), `bash .ccanvil/scripts/operations.sh resolve backlog.list` returns JSON with `provider: "linear"` and `mechanism: "http"`. The fallback (idea→backlog) fires.
- [ ] **AC-2:** The resolved `invocation.command` for Linear `backlog.list` invokes `linear-query.sh list-issues` with `--state <backlog_state_id>` and NO `--label` flag. Verified by jq-on-resolver-output.
- [ ] **AC-3:** Eval'ing the resolved command on this project surfaces BTS-22 (P3, scaffold-labeled), BTS-20 (P4, scaffold-labeled), BTS-21 (P4, scaffold-labeled), and the just-promoted BTS-175 + any other Backlog-state items. Live-validation gate (per `.claude/rules/tdd.md`) — verifies the GraphQL filter shape matches Linear's contract.
- [ ] **AC-4:** On a local-only project (no `.claude/ccanvil.json` or no Linear provider), `backlog.list` still resolves to `mechanism: bash` with `docs-check.sh list-specs`. Backwards-compat preserved. Drift-guard via fixture-based bats.
- [ ] **AC-5:** Explicit `routing.backlog = "local"` overrides the idea-fallback. The fallback only fires when `routing.backlog` is unset. Drift-guard.
- [ ] **AC-6:** `/recall` SKILL.md step 0c prose contains the literal phrase `mechanism is http` AND `eval` (handles the new mechanism). Drift-guard.
- [ ] **AC-7:** `/recall` SKILL.md step 0c prose contains an explicit anti-pattern note (e.g., literal phrase `do NOT use idea.list` or `not idea.list` paired with backlog-reasoning context). Drift-guard.
- [ ] **AC-8:** `/radar` SKILL.md step 2 prose mirrors AC-6 + AC-7 anti-pattern guidance. Drift-guard.
- [ ] **AC-9:** Existing `mechanism: mcp` `backlog.list` Linear path is removed (deduped — the http path is the single source of truth). Drift-guard: `grep -c 'backlog.list' .ccanvil/scripts/operations.sh` does NOT decrease, but `grep -c 'mcp__claude_ai_Linear__list_issues' .ccanvil/scripts/operations.sh` decreases by 1.
- [ ] **AC-10:** Edge — `state_ids.backlog` empty/absent on a Linear node. Resolver emits a clear error (NOT a silent fallback to label-filtered idea.list, NOT a malformed http command). Exit code non-zero, stderr contains `state_ids.backlog`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — Linear `backlog.list` resolver migrated mcp→http; routing fallback extended (idea→backlog when state_ids.backlog configured); state_ids.backlog presence check |
| `.ccanvil/scripts/linear-query.sh` | Modified — `list-issues --state` auto-detects UUID format and uses `state.id.eq` filter (vs `state.type.eq` for type names). Surfaced by AC-3 live-validation gate. |
| `.claude/skills/recall/SKILL.md` | Modified — step 0c handles http mechanism + explicit anti-pattern note |
| `.claude/skills/radar/SKILL.md` | Modified — step 2 handles http mechanism + anti-pattern note |
| `hub/tests/backlog-list-canonical.bats` | New — AC-1 through AC-5, AC-9, AC-10 (resolver shape + routing fallback) |
| `hub/tests/recall-radar-backlog-prose.bats` | New — AC-6 through AC-8 (skill-prose drift-guards) |

## Dependencies

- **Requires:** `linear-query.sh list-issues --state` filter support (already shipped in BTS-164 substrate). `state_ids.backlog` config (already populated in this project's `.claude/ccanvil.local.json`).
- **Blocked by:** none.

## Out of Scope

- **`idea.list` self-documentation.** The original BTS-175 description floated "add a `filter_summary` field to the resolver output JSON so any consumer that DOES use `idea.list` is forced to surface 'filter: label=idea'." Useful but additive — not the primary fix. Capture as follow-up if `idea.list` consumers are still proxying for backlog elsewhere.
- **Migrating other `mechanism: mcp` resolvers to http.** Only `backlog.list` is in scope here; `backlog.get` and any other MCP-mechanism resolvers stay as-is (they're not the source of the silent-failure mode).
- **Renaming `idea.list` to `idea.list-by-label`.** Could clarify intent but breaks downstream consumers. The skill-prose anti-pattern note is sufficient.
- **`/idea list` command behavior.** Continues to filter by `label=idea` (that's its purpose — the idea inbox view). No change.
- **Routing config doc updates.** `.ccanvil/guide/configuration.md` (or wherever routing is documented) may want to mention the new fallback. Defer to after the substrate ships and the pattern is observed.

## Implementation Notes

- **Routing fallback shape.** At `operations.sh:883`, the `work` and `ticket` groups already inherit `routing.idea` when their own routing key is unset. Extend the same conditional to include `backlog`:
  ```bash
  if [[ -z "$routed_provider" && ("$group" == "work" || "$group" == "ticket" || "$group" == "backlog") ]]; then
    routed_provider=$(jq -r '.integrations.routing.idea // ""' "$CONFIG_FILE")
  fi
  ```
  Add a `state_ids.backlog` presence check inside the Linear `backlog.list` resolver — if missing, exit 1 with stderr `state_ids.backlog not configured for Linear provider`. Prevents the malformed-http-command failure mode.
- **http resolver shape.** Mirror the `idea.list` resolver at operations.sh:519 — same pattern, swap `--label` for `--state`:
  ```bash
  command: ("bash .ccanvil/scripts/linear-query.sh list-issues" +
            " --project " + ($project | @sh) +
            " --team " + ($team | @sh) +
            " --state " + ($state_id | @sh) +
            " --limit 250")
  ```
- **Skill prose pattern.** /recall step 0c's existing "If the mechanism is `bash` ... If the mechanism is `mcp`" branching extends to a third clause: `If the mechanism is "http", run "eval ${invocation.command}" to get the JSON array of items.` Same for /radar step 2 (which uses `exec` — but http resolvers are evaluable, so `exec` works transparently).
- **Anti-pattern phrasing.** Both skill prose updates should include the literal anti-pattern note (drift-guard searchable). Suggested: `**Do NOT use `idea.list` as a backlog proxy** — it filters by `label=idea` and silently hides scaffold-labeled tickets. Always reach for `backlog.list` when reasoning about "what's left to ship."`
- **Live-API risk.** AC-3 is the live-validation gate per `.claude/rules/tdd.md` — eval the resolved command against the real Linear API. Verifies `--state` filter shape matches the GraphQL contract (BTS-170-style risk: filter shape mismatches the API).
- **Drift-guard fixture pattern.** AC-1, AC-4, AC-5 use synthetic `.claude/ccanvil.local.json` fixtures via tmpdir + jq composition. Mirror existing operations.sh resolver tests in `hub/tests/`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
