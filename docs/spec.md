# Feature: hook timing instrumentation primitive

> Feature: bts-208-hook-timing-instrumentation
> Work: linear:BTS-208
> Created: 1777343476
> Subject: hook timing instrumentation primitive
> Status: In Progress

## Summary

The BTS-206 SessionStart hook claimed sub-50ms runtime (AC-9), but no automated check verifies it. Performance regressions in any hook surface only at the human-perception threshold. This ship establishes the deterministic primitive for timing measurement: a `_timer_emit <kind> <name> <duration_ms>` helper that appends one JSONL line per measurement to `.ccanvil/state/execution-timing.log`. Wraps the two existing telemetry hooks (`post-compact-marker.sh`, `session-boundary.sh`) as the first instrumented surfaces.

Substrate primitives (`docs-check.sh`, `operations.sh`, `linear-query.sh`) are out of scope here — separate sweep. Stasis/radar surfacing is also out of scope — the log is the deterministic source; downstream consumers can read it when needed.

## Job To Be Done

**When** I'm investigating slow Claude Code session startup or compact behavior,
**I want to** read a JSONL log of every hook invocation with its duration_ms,
**So that** performance regressions are diagnosable post-hoc — without operator-perception thresholds being the only signal.

## Acceptance Criteria

- [ ] **AC-1:** New helper function in `.claude/hooks/_lib/record-failure.sh` (or a sibling file): `_timer_emit <kind> <name> <duration_ms>` appends one JSONL line `{ts:<epoch>, kind:<kind>, name:<name>, duration_ms:<duration_ms>}` to `.ccanvil/state/execution-timing.log`. Idempotent across invocations.

- [ ] **AC-2:** New helper function: `_timer_start` echoes the current epoch-ms (or epoch-seconds-with-fractional via `date +%s%3N` on Linux, fallback to `date +%s` on macOS). `_timer_duration_ms <start_ms>` computes elapsed ms.

- [ ] **AC-3:** `post-compact-marker.sh` wraps its main work with timer; on completion, emits `_timer_emit "hook" "post-compact-marker" $duration`.

- [ ] **AC-4:** `session-boundary.sh` similarly wraps + emits `_timer_emit "hook" "session-boundary" $duration`.

- [ ] **AC-5:** Bats: simulate hook invocation; assert that `.ccanvil/state/execution-timing.log` contains a JSONL line with the expected fields.

- [ ] **AC-6:** Bats: assert hook exits 0 even when timer-emit fails (never-block contract from BTS-209). Same fault-tolerance pattern as `_hook_record_failure`.

- [ ] **AC-7:** Drift-guard: `BTS-208` referenced inline in helpers and both hooks.

- [ ] **AC-8:** Full bats suite ≥ 1866 (post-BTS-209 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/_lib/record-failure.sh` | Add `_timer_start`, `_timer_duration_ms`, `_timer_emit` helpers (or split to `_lib/timer.sh` if file size warrants). |
| `.claude/hooks/post-compact-marker.sh` | Wrap with timer, emit duration. |
| `.claude/hooks/session-boundary.sh` | Wrap with timer, emit duration. |
| `hub/tests/hook-timing-instrumentation.bats` | Tests AC-5, AC-6 + drift. |

## Out of Scope

- **Substrate primitive timing.** docs-check.sh, operations.sh, linear-query.sh stay un-instrumented in this ship. Separate sweep.
- **Stasis/radar surfacing.** The log is the deterministic source; downstream skills can consume it. Reading + summarizing is its own concern.
- **Aggregation, percentile buckets, sampling.** Raw per-call records only. Aggregation is a downstream consumer concern.
- **Log rotation.** Same as BTS-209 — unbounded growth acceptable; revisit if it becomes a problem.
- **Drift-guard on duration thresholds.** No "max 50ms" assertion in CI yet — that's a downstream consumer of the log.

## Implementation Notes

- macOS `date +%s%N` is unsupported (BSD date doesn't have %N). Use `date +%s%3N` on Linux; on macOS, fall back to `python3 -c 'import time; print(int(time.time()*1000))'` if python3 is available, else seconds-only granularity (`date +%s` * 1000). Document the granularity caveat.
- Place helpers in the same file as `_hook_record_failure` for one-source-of-truth on hook helpers, OR split to `_lib/timer.sh` if the timer logic exceeds ~30 lines. Pick whichever produces clearer git diffs and easier sourcing for future hooks.
