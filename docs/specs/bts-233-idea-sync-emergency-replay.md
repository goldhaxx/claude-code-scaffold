# Feature: /idea sync replays entries from dual-capture-emergency.log

> Feature: bts-233-idea-sync-emergency-replay
> Work: linear:BTS-233
> Created: 1777335037
> Status: Complete

## Summary

BTS-205 added `.ccanvil/dual-capture-emergency.log` as a last-resort dead-letter when both the primary capture AND the pending log are unwritable. Currently entries in the emergency log require manual operator intervention (`cat` the log, replay each via `/idea`). The `/idea sync` skill replays `.ccanvil/ideas-pending.log` via `cmd_idea_pending_replay` (BTS-179) but does NOT touch the emergency log.

This ship extends `cmd_idea_pending_replay` to drain BOTH logs in a single invocation. Same per-op dispatch logic, separate snapshot + rewrite per log. Successful entries are cleared; failed entries are preserved for the next sync. Auto-recovery for the dead-letter case completes the BTS-205 dual-capture resilience loop.

## Job To Be Done

**When** I run `/idea sync` and the emergency log has entries (because both the primary log and the pending log were unwritable when those captures fired),
**I want to** have those entries automatically replayed and the log auto-cleared on success,
**So that** dual-capture resilience is fully self-recovering — no manual operator step required.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cmd_idea_pending_replay` reads `.ccanvil/dual-capture-emergency.log` in addition to `.ccanvil/ideas-pending.log`, dispatching each entry through the same per-op logic (`add` → `idea.add`, `promote/defer/dismiss/merge/ticket.transition` → `ticket.transition`). Both logs are processed in a single invocation; emergency log is processed AFTER pending log so a successful pending replay doesn't get clobbered by an emergency-log dispatch failure.

- [ ] **AC-2:** Output JSON gains an `emergency_pending` field reporting the count of failed entries remaining in the emergency log. Pre-existing fields (`synced`, `failed`, `pending`, `entries`) preserve their current semantics — `synced` and `failed` are aggregated across both logs; `pending` reports only ideas-pending.log remaining count (unchanged).

- [ ] **AC-3:** Empty/absent emergency log fast path — when `.ccanvil/dual-capture-emergency.log` doesn't exist or is zero-byte, `emergency_pending` is 0 and no per-entry processing fires. Pre-existing pending-log empty-state behavior preserved (synced=0, failed=0, pending=0).

- [ ] **AC-4:** Emergency log with one `add` entry, http dispatch succeeds → entry removed from log, `synced` incremented, `emergency_pending: 0`. Verified via stubbed `linear-query.sh` returning success.

- [ ] **AC-5:** Emergency log with one `add` entry, http dispatch fails → entry preserved in log, `failed` incremented, `emergency_pending: 1`. Verified via stubbed `linear-query.sh` returning non-zero exit.

- [ ] **AC-6:** Both logs populated (1 entry each), both succeed → `synced: 2`, `pending: 0`, `emergency_pending: 0`, both logs cleared. Verifies aggregation logic.

- [ ] **AC-7:** New bats `hub/tests/idea-pending-replay-emergency.bats` covers AC-3 through AC-6 plus a drift-guard for `BTS-233` inline in `docs-check.sh`. Reuses the `_with_linear_routing` and `_with_linear_stub` helpers from `idea-pending-replay.bats`.

- [ ] **AC-8:** Full bats suite remains green at ≥ 1799 (post-BTS-232 baseline). Existing `idea-pending-replay.bats` continues to pass — emergency log behavior is purely additive.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Refactor `cmd_idea_pending_replay` to extract a per-log iteration helper; call it for both `ideas-pending.log` and `dual-capture-emergency.log`. Add `emergency_pending` to output JSON. |
| `hub/tests/idea-pending-replay-emergency.bats` | New bats covering AC-3 through AC-7. |
| `.claude/skills/idea/SKILL.md` | Update Sync section prose to note emergency-log replay (one-line addition). |

## Dependencies

- **Requires:** BTS-179 (idea-pending-replay substrate); BTS-205 (emergency log dead-letter); BTS-164 (http substrate for ticket.transition); BTS-166 (http for idea.add). All shipped.
- **Blocked by:** Nothing.

## Out of Scope

- **Replaying entries with a different schema** — emergency log entries share JSONL shape with pending log entries (BTS-205 writes the same `$entry` to both). No schema migration needed.
- **Surfacing the emergency-log replay summary in `/idea sync` skill prose** — current rendering as `SYNCED: N / FAILED: M / PENDING: K` is sufficient. Adding `EMERGENCY: J` to the summary line is a UX consideration deferred to skill prose; the substrate emits the JSON field for any future skill update.
- **Atomic concurrent-safe replay across both logs** — same trade-off as BTS-179. Single-operator workflow assumed; multi-process replay races are out of scope.

## Implementation Notes

- **Refactor pattern:** extract the body of the existing `while IFS= read -r entry <&3` loop (lines ~3142–3236) into a helper `_idea_pending_replay_log <log_path> <project_dir>` that emits per-entry results to stdout (same shape as the current `results_file` JSONL records) and returns a `synced:N failed:M` line on stderr or via a sentinel. Call the helper for both logs, aggregate counts.
- **Log ordering:** ideas-pending.log first, emergency log second. Rationale: emergency log is the more recent + more failure-prone state; if a dispatch will succeed, processing pending first avoids the case where a transient dispatch failure on emergency contaminates the pending replay.
- **Output JSON additivity:** `emergency_pending` is a NEW field. Existing consumers (the `/idea sync` skill prose's `SYNCED: %d / FAILED: %d / PENDING: %d` rendering) are unaffected because they don't read the field. Future skill updates can surface it.
- **Test fixture pattern:** mirror `idea-pending-replay.bats`'s setup: `_with_linear_routing` + `_with_linear_stub <exit_code>` to control dispatch outcomes deterministically.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
