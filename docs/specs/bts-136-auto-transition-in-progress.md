# Feature: Auto-Transition to In Progress on Activate

> Feature: bts-136-auto-transition-in-progress
> Work: linear:BTS-136
> Created: 1777069198
> Status: Complete

## Summary

Today Linear tickets sit in Backlog from triage to merge. BTS-119 covers the end (merge → Done). BTS-128 gave us `ticket.transition`. BTS-130 gave us `Work:` extraction. Fill the mid-lifecycle gap: when `docs-check.sh activate` creates the feature branch + draft PR, the Linear ticket should auto-transition to **In Progress**. Also add `Todo` as a valid role so future `/spec` work (spec written, not yet activated) can mark the ticket Todo.

Minimum-viable scope: wire **`activate` → In Progress** end-to-end via the same AUTO-CLOSE emit/scan pattern BTS-119 uses. Adding the Todo hook in `/spec` is a small extension of the skill prose; also included in this ship.

## Acceptance Criteria

- [ ] **AC-1:** `.claude/ccanvil.local.json` gains `state_ids.todo` and `state_ids.in_progress` entries (UUIDs from `list_issue_statuses`).
- [ ] **AC-2:** `operations.sh resolve ticket.transition <id> todo` emits `params.state = <todo-uuid>`. Same for `in_progress`. Error messages list the expanded role set.
- [ ] **AC-3:** `cmd_activate` emits `AUTO-TRANSITION: {"provider":"linear","id":"<ID>","role":"in_progress"}` on stdout at the end of a successful activation when the active spec carries `Work: linear:<ID>`. Silent for legacy specs (no Work:), local-provider specs (Work: local:<uid>), and other providers.
- [ ] **AC-4:** New helper subcommand `docs-check.sh auto-transition-emit <branch> <role> [docs-dir]` — pure logic mirroring `cmd_auto_close_emit`. Takes role ∈ {todo, in_progress, ...}. Same branch → spec → Work: extraction.
- [ ] **AC-5:** `.claude/commands/activate.md` (or equivalent skill prose) documents: after running `docs-check.sh activate`, scan stdout for `AUTO-TRANSITION:` and dispatch the Linear `save_issue` with the embedded id + the resolver's `state`. Mirrors `/land`'s AUTO-CLOSE handling.
- [ ] **AC-6:** `.claude/skills/spec/SKILL.md` step 10 prose updated: after writing the spec, if `Work: linear:<ID>` is present, dispatch `ticket.transition <ID> todo` via operations.sh → MCP. Graceful MCP failure → `.ccanvil/ideas-pending.log` via existing ticket.transition op shape (BTS-119).
- [ ] **AC-7:** Existing ticket.transition tests still pass after the role-set expansion.
- [ ] **AC-8:** 5+ new bats cases in `hub/tests/ticket-transition.bats` and `hub/tests/auto-transition-emit.bats` (new file) covering: role=todo valid, role=in_progress valid, cmd_activate emits marker for linear Work, silent for local Work, silent for no Work (legacy).
- [ ] **AC-9:** Dogfood-close: BTS-136 itself auto-transitions to In Progress when `docs-check.sh activate bts-136-...` runs (Claude sees marker + dispatches MCP call). BTS-119's existing auto-close handles the final transition to Done on merge.

## Affected Files

| File | Change |
|------|--------|
| `.claude/ccanvil.local.json` | Modified — add `todo`, `in_progress` state_ids |
| `.ccanvil/scripts/operations.sh` | Modified — role validation expands; error messages updated |
| `.ccanvil/scripts/docs-check.sh` | Modified — new `cmd_auto_transition_emit` + `cmd_activate` wires it |
| `.claude/commands/activate.md` | NEW (or skill equivalent) — documents AUTO-TRANSITION scan/dispatch |
| `.claude/skills/spec/SKILL.md` | Modified — step 10 dispatches `ticket.transition <id> todo` when linear |
| `hub/tests/ticket-transition.bats` | Modified — new cases for todo/in_progress roles |
| `hub/tests/auto-transition-emit.bats` | NEW — 5+ cases for cmd_activate marker emission |

## Out of Scope

- "In Review" state (not configured in this workspace — out-of-scope until needed).
- Auto-transition on every commit. Single emission at activate is sufficient for ticket visibility.
- Reverse transitions (In Progress → Todo if branch is abandoned). Can be manual via `/idea triage` or Linear UI.
- Local-provider parity (`local:<uid>` JSONL doesn't have Todo/In Progress semantics — out-of-scope).

## Implementation Notes

- `cmd_auto_transition_emit` is almost identical to `cmd_auto_close_emit` — the only differences are the role parameter and the marker prefix (`AUTO-TRANSITION:` vs `AUTO-CLOSE:`). Consider generalizing, but inline duplication is clearer for now; DRY is cheap on 20 LOC.
- The AUTO-TRANSITION marker's role is written into the JSON body, so downstream skills don't need to know about it at marker-parse time.
- `cmd_activate` only emits on SUCCESS — a failed activate (e.g., spec missing) should NOT emit a transition (ticket stays where it is).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
