# Feature: cmd_session_info jq-fork reduction

> Feature: bts-207-cmd-session-info-jq-fork-reduction
> Work: linear:BTS-207
> Created: 1777341806
> Status: In Progress

## Summary

`cmd_session_info` runs four `jq` invocations against a single state file to read three fields, plus a fifth `jq -n` for the output assembly — five forks per call. /stasis and /recall both call this on every invocation. The pattern violates `.claude/rules/deterministic-first.md` (minimize subprocess work) without offering anything in return.

Replace the four-fork-then-assemble pattern with one `jq` invocation that reads the boundary file and emits the final envelope shape directly. Counter is passed via `--argjson`. Output JSON shape is preserved exactly; only the implementation collapses.

## Job To Be Done

**When** /stasis or /recall calls `session-info` to read session state,
**I want to** read the file in one fork, not five,
**So that** the substrate consumes the minimum subprocess work for a deterministic read — matching the deterministic-first principle.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cmd_session_info` makes at most ONE `jq` invocation per call when the boundary file exists and is valid JSON.

- [ ] **AC-2:** `cmd_session_info` makes at most ONE `jq` invocation per call when the boundary file is missing or corrupt (the no-op JSON-emit path).

- [ ] **AC-3:** Output JSON shape is preserved exactly: `{counter:int, epoch:int|null, iso:string|null, tz:string|null}`. All existing tests for `session-info` continue to pass without modification.

- [ ] **AC-4:** Bats fork-counter test: wrap `jq` with a counter (e.g., `JQ=$(write_jq_counter)`), run `cmd_session_info` against a valid boundary fixture, assert the counter shows ≤1 invocation. Run again against a corrupt fixture and a missing fixture — each ≤1.

- [ ] **AC-5:** Drift-guard: `BTS-207` referenced inline in `docs-check.sh` near the change site.

- [ ] **AC-6:** Full bats suite remains green at ≥ 1842 (post-BTS-237 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Collapse four jq calls in `cmd_session_info` to one. |
| `hub/tests/session-info-jq-forks.bats` | New file: fork-counter test for AC-4. |

## Out of Scope

- **Changing the substrate contract.** Output JSON shape stays identical.
- **Optimizing other multi-jq sites.** Audit + collapse is a separate sweep; this ship narrowly fixes `cmd_session_info`.

## Implementation Notes

- The validity check (`jq -e . < "$boundary_path" >/dev/null 2>&1`) doubles as the first stage of the read. Combine: a single `jq` that handles both validity and field-extraction in one pass. If the file is invalid JSON, jq's exit code propagates → the no-op fallback runs.
- Pattern: `jq --argjson counter "$counter" '{counter:$counter, epoch:(.epoch//null), iso:(.iso//null), tz:(.tz//null)}' < "$boundary_path"` — emits the envelope directly. If jq fails (file missing or invalid), the `||` branch emits `{counter:$counter, epoch:null, iso:null, tz:null}` via a separate single-fork `jq -n`.
