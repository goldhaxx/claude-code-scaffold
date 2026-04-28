# Feature: provider integration strategy — codify http-canonical, sweep MCP dead code

> Feature: bts-183-provider-integration-strategy
> Work: linear:BTS-183
> Created: 1777343926
> Subject: provider integration strategy — codify http-canonical, sweep MCP dead
> Status: In Progress

## Summary

Linear integration in ccanvil migrated ad-hoc from MCP → http (BTS-164/166/167) one verb at a time. Daily-driver verbs (`idea.add`, `idea.list`, `idea.triage`, `idea.review-icebox`, `idea.count`, `idea.sync`, `backlog.list`, `ticket.transition`) are 100% on http. Six verbs (`idea.promote`, `idea.defer`, `idea.dismiss`, `idea.merge`, `backlog.get`, `ticket.find-by-title`) still have MCP-mechanism resolutions in `operations.sh` — but ZERO live callers in skills or scripts. They exist only as resolver branches and bats tests of those branches. \~200 LOC of dead code.

This ship: (a) codifies the canonical rule in `.claude/rules/provider-integration.md` — http for substrate, MCP for ad-hoc operator queries; (b) sweeps the 6 dead-code MCP branches from `operations.sh`; (c) deletes the bats tests that exclusively exercise those branches.

Future provider generalization (GitHub, Notion, etc.) is out of scope — premature; revisit when the next provider lands. The rule's framing (substrate=http, operator-tool=MCP) extends naturally.

## Job To Be Done

**When** I add a new substrate operation that integrates with an external provider,
**I want to** consult one rule that says "use http (or equivalent shell-to-API), not MCP",
**So that** I don't introduce mixed-mode drift, and the dead-code bloat from the Linear migration doesn't repeat for the next provider.

## Acceptance Criteria

- [ ] **AC-1:** New rule file `.claude/rules/provider-integration.md` codifies the canonical pattern: substrate ops (those reachable from `operations.sh`) use http or equivalent shell-to-API; MCP is reserved for operator-driven ad-hoc queries inside an interactive session. Documents the why (LLM-in-loop cost, batch ops, capability ceiling, test surface, auth model).
- [ ] **AC-2:** `is_valid_operation` in `operations.sh` no longer lists `idea.promote`, `idea.defer`, `idea.dismiss`, `idea.merge`, `backlog.get`, `ticket.find-by-title`. The case branches in both `cmd_resolve` (MCP-emitting paths) and any related dispatcher are removed.
- [ ] **AC-3:** Bats coverage updated — tests exclusively exercising the removed verbs are deleted: `hub/tests/ticket-find-by-title.bats` (entire file), removed dead-verb tests in `hub/tests/idea-triage-native.bats` and `hub/tests/operations.bats`, removed backlog.get reference in `hub/tests/ticket-transition.bats`.
- [ ] **AC-4:** Resolution call for any removed verb returns the canonical "unknown operation" error (existing fall-through behavior — no special handling needed; the `is_valid_operation` removal cascades).
- [ ] **AC-5:** Drift-guard: `BTS-183` referenced inline in `provider-integration.md` and `operations.sh` (near the resolver where the dead branches lived).
- [ ] **AC-6:** Full bats suite remains green at ≥ 1874 (post-BTS-208 baseline) MINUS the deleted-verb test count. The deletion lowers the count; the floor is the post-deletion total.

## Affected Files

| File | Change |
| -- | -- |
| `.claude/rules/provider-integration.md` | New rule file. |
| `.ccanvil/scripts/operations.sh` | Remove `is_valid_operation` entries + dead-code MCP branches for 6 verbs. |
| `hub/tests/ticket-find-by-title.bats` | DELETE (entire file). |
| `hub/tests/idea-triage-native.bats` | Remove tests on lines \~116-160, 162-180, 466-510 (dead-verb tests). |
| `hub/tests/operations.bats` | Remove backlog.get tests + the `backlog.get` token from the validation list. |
| `hub/tests/ticket-transition.bats` | Replace the backlog.get reference with a still-live verb (e.g. `idea.add`). |

## Out of Scope

* **Generalization to future providers.** Premature — revisit when GitHub/Notion/etc lands a substrate path.
* **Migrating** `claude_ai_Linear` MCP usage out of interactive sessions. Body explicitly notes this is the right shape for operator tools.
* **Deprecating MCP at the Claude Code level.** Not our call.
* **Refactoring how http vs other-shell-API mechanisms compose.** The current shape (mechanism field in resolution envelope) is sufficient.

## Implementation Notes

* The `operations.sh` resolver has MCP-emitting case branches at lines 256, 361, 365, 369, 373, 387 (`is_valid_operation` + `cmd_resolve` first-pass), and at lines 506, 633, 649, 665, 681, 800 (the actual MCP envelope emission). Trace each verb across both passes.
* The `is_valid_operation` line `idea.promote|idea.defer|idea.dismiss|idea.merge) return 0 ;;` collapses to nothing after deletion. `backlog.get` is in the line `backlog.list|backlog.create|backlog.prioritize|backlog.get` — split into the remaining three. `ticket.find-by-title` has its own line.
* The rule file should reference the post-mortem table from BTS-183's body (the http-vs-MCP comparison) verbatim — it's the case for the rule.
