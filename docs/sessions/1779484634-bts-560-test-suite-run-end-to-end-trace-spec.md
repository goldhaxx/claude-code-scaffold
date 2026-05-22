# Feature: test-suite-run end-to-end trace

> Feature: bts-560-test-suite-run-end-to-end-trace
> Work: linear:BTS-560
> Created: 1779473997
> Subject: test-suite-run end-to-end trace
> Status: In Progress

## Summary

A `test-suite-run` invocation (the bats provider's `bats-report.sh`) runs three
phases — the BTS-281 manifest pre-warm, the bats suite, and the otel-flatten
post-step — but only the bats suite emits OpenTelemetry spans. The pre-warm runs
for minutes invisibly, and the suite-root span is emitted last, so mid-run the
trace has no root. This feature instruments every phase of a `test-suite-run` as
a span under one rooted trace, so the Grafana waterfall shows the complete
end-to-end run instead of a multi-minute blind spot followed by a rootless trace.

## Job To Be Done

**When** I run the bats test suite and watch the Grafana "Test observability" view,
**I want to** see every phase of the run — manifest pre-warm, the suite itself, the flatten step — as a labeled span in one trace,
**So that** I can see where the wall-time goes end-to-end and spot serialization that should be optimized (e.g. the pre-warm running before the suite instead of alongside it).

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** When `bats-report.sh` runs with telemetry enabled, exactly one root span named `test-suite-run` (service `ccanvil-test`) is emitted, carrying the run's `trace_id` and **no** parent span id. This span's span id is the *root span id* referenced by AC-3/AC-4/AC-5; tests identify each span by its emitted `--name` and assert linkage by comparing the emitted span-id / parent-span-id values.
- [ ] **AC-2:** The root span's `--start` is at or before the `manifest pre-warm` span's start and its `--end` is at or after the last phase span's end — it covers the whole process wall time.
- [ ] **AC-3:** The BTS-281 manifest pre-warm (`module-manifest.sh validate`, `bats-report.sh` \~211-218) is wrapped in a span named `manifest pre-warm`, with `parent_span_id` = the root span id (AC-1), sharing the run's `trace_id`.
- [ ] **AC-4:** The existing `bats suite (<run-id>)` span sets `parent_span_id` = the root span id (AC-1); its own span id stays `BTS_TELEMETRY_SUITE_SPAN_ID` so file spans still nest under it.
- [ ] **AC-5:** When the otel-flatten post-step runs (parallel mode), it is wrapped in a span named `otel-flatten` with `parent_span_id` = the root span id (AC-1); in serial mode (flatten skipped) no `otel-flatten` span is emitted and the remaining spans still form a valid single-rooted trace.
- [ ] **AC-6:** Every span emitted by one `test-suite-run` invocation — root, `manifest pre-warm`, `bats suite`, `otel-flatten`, and the per-file/per-test spans — shares one `trace_id`.
- [ ] **AC-7 (hierarchy regression):** File spans still set `parent_span_id` = the `bats suite` span id, and test spans still set `parent_span_id` = their file span id — `telemetry.bash` is not modified and the suite→file→test drill-down is unchanged.
- [ ] **AC-8 (graceful skip):** **Given** `--no-telemetry` is passed or the OTel Collector is unreachable, **when** `bats-report.sh` runs, **then** zero spans are emitted and the script exits with the unchanged bats exit code — phase instrumentation never alters the exit code.
- [ ] **AC-9 (edge: pre-warm skipped):** **Given** the manifest pre-warm is skipped (`BTS_MANIFEST_VALIDATE_CACHE` already set, or `module-manifest.sh` absent), **when** `test-suite-run` runs, **then** no `manifest pre-warm` span is emitted and the root + `bats suite` (+ `otel-flatten`) spans still form a valid single-rooted trace.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/bats-report.sh` | Modified — generate the root span id at process start; wrap pre-warm + flatten in spans; re-parent the `bats suite` span under the new root; emit the root span at end. `# @manifest` block updated. |
| `.ccanvil/observability/otel-span.sh` | Unchanged — consumed as-is via `otel_span_emit`. |
| `hub/tests/bats-report-end-to-end-trace.bats` | New — AC tests using the `OTEL_SPAN_CLI` recording-stub seam. |
| `.ccanvil/observability/SCHEMA.md` | Modified — document the root + phase span attributes (additive minor bump). |

## Dependencies

* **Requires:** `otel-span.sh` (BTS-543, shipped) — `otel_span_emit`.
* **Blocked by:** none.
* Child of BTS-542 (Workflow Observability umbrella).

## Out of Scope

* Real-time visibility *during* the pre-warm (sub-phase spans inside `module-manifest.sh validate`) — needs per-entry instrumentation, tracked under BTS-545 (C3).
* Running the pre-warm concurrently with the suite to collapse the blank window — BTS-561.
* Tuning the D1 "Test observability" dashboard for the new span names (`test-suite-run` / `manifest pre-warm` / `otel-flatten` will appear in span lists) — BTS-533.
* Instrumenting the pytest arm of `cmd_test_suite_run` — pytest has no pre-warm/flatten phases; see BTS-559.

## Implementation Notes

* All span emission goes through `otel_span_emit` (`otel-span.sh`), mirroring the existing suite-span block at `bats-report.sh:525-548`. Capture each phase's start/end with `date +%s.%N` around the phase (same pattern as `BTS_TELEMETRY_SUITE_START_EPOCH`).
* Generate the root span id at process start next to `BTS_TELEMETRY_TRACE_ID` / `BTS_TELEMETRY_SUITE_SPAN_ID` (\~`bats-report.sh:195-204`) — e.g. `BTS_TELEMETRY_RUN_SPAN_ID`. The root span *record* is emitted last (its true duration is known only at completion); establishing the id early lets every phase span parent under it. The mid-run rootless window is inherent to completed-span emission — BTS-561 is what removes the operator-visible blank dashboard.
* Gate every new span on the same conditions as the existing suite-span block (`no_telemetry == 0`, trace id set, `otel-cli` present). `otel-span.sh` is already a silent no-op when the Collector is down.
* Phase spans carry a `phase=<manifest-prewarm|bats-suite|otel-flatten>` attribute for dashboard filtering.
* Tests use the `OTEL_SPAN_CLI` recording-stub plus the `OTEL_SPAN_INIT_DONE=1` / `OTEL_SPAN_LIVE=1` pin seam (see `otel-span.sh` header) to assert span emission offline.
* The new root span changes the trace's root name from `bats suite (...)` to `test-suite-run` — flag any `rootTraceName` use for BTS-533 when it tunes D1.
