# Feature: ticket.transition operation verb

> Feature: bts-128-ticket-transition
> Work: linear:BTS-128
> Created: 1776992519
> Status: In Progress

## Summary

Add a provider-neutral `ticket.transition` operation verb to `operations.sh`. It collapses the recurring stochastic pattern "look up a state UUID in `.claude/ccanvil.local.json:state_ids.<role>`, hand-assemble an `mcp__claude_ai_Linear__save_issue` payload with that UUID, paste" into a single deterministic call: `operations.sh resolve ticket.transition <id> <role>`. On Linear-configured nodes it emits a resolution JSON with `stateId` pre-populated from the configured role, ready for the caller to dispatch the MCP `save_issue` call. Also extends the Linear state-ids vocabulary with a `done` role, enabling BTS-119 (auto-close-on-merge) and making last session's 3× manual "Done" UUID paste a one-shot operation.

## Job To Be Done

**When** I need to move a Linear ticket to a named workflow state (triage, backlog, icebox, canceled, duplicate, done),
**I want to** invoke `operations.sh resolve ticket.transition <id> <role>` and have the role → state-UUID lookup + MCP payload shape be deterministic,
**So that** Claude never pastes raw state UUIDs by hand, and any agent can transition tickets programmatically without memorizing provider-specific state IDs.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `operations.sh` accepts `ticket.transition` as a valid operation (`is_valid_operation` returns true).
- [ ] **AC-2:** `operations.sh resolve ticket.transition BTS-128 backlog` on a Linear-configured node emits JSON with `.provider == "linear"`, `.mechanism == "mcp"`, `.invocation.tool == "mcp__claude_ai_Linear__save_issue"`, `.invocation.params.id == "BTS-128"`, and `.invocation.params.stateId` equal to the configured `state_ids.backlog` UUID.
- [ ] **AC-3:** The resolver supports all six roles — `triage`, `backlog`, `icebox`, `canceled`, `duplicate`, `done` — looking each one up via the existing `linear_state_id` helper.
- [ ] **AC-4:** `.claude/ccanvil.local.json:integrations.providers.linear.state_ids.done` is populated with the Blocktech "Done" UUID `bc6aa160-258d-4eae-b3b5-a2575732a188` as part of this ship.
- [ ] **AC-5:** When the requested role is not present in `state_ids` (e.g., an unconfigured node), the resolver exits non-zero with a clear error message naming both the role and the config file path. It does NOT silently emit a payload with an empty `stateId`.
- [ ] **AC-6:** When the `<id>` argument is missing, the resolver exits non-zero with a usage-style error. When the `<role>` argument is missing, it exits non-zero with a "role required" error distinct from the id error.
- [ ] **AC-7:** Unknown role names (e.g., `ticket.transition BTS-128 nonsense`) exit non-zero with an error listing the valid role vocabulary. No MCP payload is emitted.
- [ ] **AC-8:** The argument parser in `operations.sh` accepts a second positional argument after the operation name so that `resolve ticket.transition <id> <role>` works without quoting tricks. Existing single-arg operations (e.g., `backlog.get BTS-42`) continue to parse unchanged.
- [ ] **AC-9:** On a local-provider (non-Linear) node, `ticket.transition` is a no-op/unsupported at the adapter level — exits non-zero with "provider local does not support ticket.transition". This preserves the provider-neutral contract while being explicit about the capability gap.
- [ ] **AC-10:** `/idea` skill's triage/defer/dismiss/merge dispatches are refactored to invoke `ticket.transition` internally rather than resolve `idea.promote`/`defer`/`dismiss`/`merge` + stitch `save_issue` manually. The refactor is documented in `SKILL.md` and verified by running an existing triage operation end-to-end.
- [ ] **AC-11:** `.ccanvil/guide/command-reference.md` documents the `ticket.transition` verb with its arg shape, supported roles, and one example invocation.
- [ ] **AC-12:** Full bats suite remains 836+ green; the new suite adds at least 6 tests covering AC-2 (happy path per role), AC-5 (missing role config), AC-6 (missing args), AC-7 (unknown role), and AC-9 (local provider).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — add `ticket.transition` to `is_valid_operation`, add linear_mcp_adapter branch, extend arg parser for second positional |
| `.claude/ccanvil.local.json` | Modified — add `done` UUID to `state_ids` |
| `.claude/skills/idea/SKILL.md` | Modified — refactor dispatch examples to use `ticket.transition` wrapper |
| `.ccanvil/guide/command-reference.md` | Modified — document `ticket.transition` verb |
| `hub/tests/ticket-transition.bats` | New — 6+ tests covering AC-2/5/6/7/9 |

## Dependencies

- **Requires:** `linear_state_id` helper in `operations.sh` (already exists, line 367). BTS-130's provider-neutral dispatch pattern (already shipped).
- **Blocked by:** Nothing. BTS-128 is unblocked as of this session.

## Out of Scope

- **Pending-log fallback on MCP failure.** The resolver emits routing; the caller dispatches. Failure-handling policy (append-to-pending, retry, etc.) belongs in BTS-123 (pending-log integrity) and the caller's skill flow — not in the resolver itself.
- **`ticket.find-by-title` wrapper.** Sibling verb tracked as BTS-129; ship separately.
- **Generalizing to other providers (GitHub, Jira).** Only the Linear adapter branch is in scope. Local provider returns "unsupported" per AC-9. Future providers will add their own adapter branches.
- **Auto-close-on-merge orchestration.** BTS-119 consumes this primitive once shipped; wiring it to PR-merge events is separate scope.

## Implementation Notes

- **Pattern to follow:** same conditional-merge dispatch pattern as `idea.promote`/`defer`/`dismiss`/`merge` in `linear_mcp_adapter` (lines 530-597). Each of those resolves a state UUID via `linear_state_id` and emits `params: (if $state_id != "" then {"stateId":$state_id} else {} end)`. The new `ticket.transition` case does the same but also pre-populates `params.id` because the caller passes the id explicitly (unlike idea mutations where the skill stitches id in at dispatch).
- **Argument parsing:** the current loop (operations.sh:80-86) consumes exactly one positional after the operation name. Extend to consume a second positional into a new variable (`OP_ARG2`) — minimal, backward-compat. Do NOT refactor to an array; keeps the blast radius small.
- **Strict role validation happens at resolve time, not exec time.** The resolver owns "is this role known + configured?" — if it silently emitted a payload with empty `stateId`, Linear would reject it with an opaque server error. Fail loud at the resolver boundary.
- **`done` UUID authority:** Blocktech Solutions workspace, confirmed from the three manual transitions in the BTS-130 session (`bc6aa160-258d-4eae-b3b5-a2575732a188`). Also captured as a memory candidate in the last stasis.
- **No changes to `cmd_exec`.** For mcp-mechanism resolutions, `cmd_exec` already prints the resolution JSON for the caller to dispatch — the existing code path handles this cleanly.
- **TDD ordering:** add operation-validity test → add happy-path resolver test → add arg-parsing tests → add error-path tests → implement adapter branch → add config `done` role → refactor /idea skill to use it → update command-reference.md.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
