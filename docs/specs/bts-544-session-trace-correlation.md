# Feature: Workflow Observability C2 — session-trace correlation

> Feature: bts-544-session-trace-correlation
> Work: linear:BTS-544
> Created: 1779648721
> Status: In Progress
> Subject: session-trace correlation via SessionStart/SessionEnd hooks

## Summary

Every Claude Code session produces ONE rooted `ccanvil-session` trace in Tempo, so every per-script span (C3) and per-tool-call span (C5) emitted during the session can later parent under it. The trace is **rooted** — a real synthetic root span is emitted at SessionEnd carrying the true wall-clock duration — not rootless (Tempo's `rootTraceName` is documented-unstable for rootless traces, which would break the planned C6 Session Timeline dashboard). A reaper handles abnormal exits where SessionEnd never fires.

## Job To Be Done

**When** a Claude Code session opens,
**I want to** establish a stable session trace context that every deterministic ccanvil operation can parent under,
**So that** the future C6 Session Timeline dashboard can answer "where did this session's wall-time go" for one operator session as a single coherent trace.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1 (terms):** "Session trace state" is `.ccanvil/state/session-trace.json` containing `{trace_id, root_span_id, started_at_epoch, session_id, claude_session_id}` where `trace_id` matches `^[0-9a-f]{32}$`, `root_span_id` matches `^[0-9a-f]{16}$` (W3C Trace Context), and `started_at_epoch` is an **epoch-second float** captured via `date +%s.%N` at SessionStart (format `<unix_seconds>.<fractional>` — the exact form `otel_span_emit --start` accepts; no unit conversion required at emit time). "Session id" (the operator-meaningful primary key) is `<counter>-<epoch>` where `<counter>` is the integer at `.ccanvil/state/session-counter` (post-bump by `session-boundary.sh`) and `<epoch>` is `date +%s` at SessionStart. "Claude session id" (the secondary correlation key for pivoting from Claude Code logs to the ccanvil session trace) is the `session_id` UUID field from the SessionStart hook's stdin JSON payload — empty string `""` when the field is absent or empty.
- [ ] **AC-2 (open writes state):** Given `.ccanvil/state/session-trace.json` does NOT exist, when `session-otel-open.sh` runs with the SessionStart stdin JSON payload on fd 0, then it (a) reads stdin once and extracts `claude_session_id` from the payload's `.session_id` field via `jq -r '.session_id // ""'` (falling back to `""` on missing/empty/malformed-JSON without failing the hook), and (b) atomically writes `.ccanvil/state/session-trace.json` (mktemp+mv, AC-1 shape) and exits 0. No span is emitted at open time (the root emits at close).
- [ ] **AC-3 (close emits rooted span):** Given a valid `.ccanvil/state/session-trace.json` written by AC-2, when `session-otel-close.sh` runs, then it emits exactly ONE span via `otel-span.sh` with `service=ccanvil-session`, `name=ccanvil-session`, `--trace-id` and `--span-id` matching the state file, NO `--parent-id` (rooted), attrs include `session.id=<id>` and `git.sha=<sha>` and — when non-empty — `claude_session_id=<uuid from state file>` (the attr is omitted entirely when the stored value is `""`, never emitted as `claude_session_id=`), `--start=<started_at_epoch from state file>` and `--end=$(date +%s.%N)` (both epoch-second floats — same clock domain, no conversion), with `end ≥ start`. The state file is removed on success.
- [ ] **AC-4 (reaper — abnormal exit):** Given `.ccanvil/state/session-trace.json` exists at SessionStart (prior SessionEnd never fired), when `session-otel-open.sh` runs, then it FIRST emits one best-effort `ccanvil-session` span for the stale trace (attrs include `reaper=true` and the original `session.id`; the original `claude_session_id` is carried as an attr when non-empty under the same omit-when-empty rule as AC-3; `--start=<stale started_at_epoch from state file>`; `--end=$(date +%s.%N)` at SessionStart — same epoch-second-float clock as AC-3, no unit conversion), THEN overwrites the state file with the new session's trace state.
- [ ] **AC-5 (bats suite linkage):** When `bats-report.sh` runs with `.ccanvil/state/session-trace.json` present, the existing `test-suite-run` and `bats suite` spans carry `session.id=<id from state file>` in their attrs, plus `claude_session_id=<uuid>` when non-empty (omit-when-empty rule from AC-3 applies). The suite spans MUST NOT inherit the session `trace_id` — they keep their own trace_id; only the `session.id` and `claude_session_id` attributes link them (per the plan's decision-5: link, do not merge).
- [ ] **AC-6 (settings wiring):** `.claude/settings.json` `SessionStart` hooks array contains both entries in this order: (1) `session-boundary.sh` (existing — must run first to bump the counter), (2) `session-otel-open.sh` (new — reads the post-bump counter). A new top-level `SessionEnd` hooks block contains `session-otel-close.sh`.
- [ ] **AC-7 (graceful-skip, never blocks):** Given `CCANVIL_TELEMETRY_DISABLED` is set OR the Collector is unreachable OR `otel-cli` is absent, when either hook runs, then it exits 0, emits no span, prints a `WARN:` line to stderr, and appends one JSONL entry to `.ccanvil/state/hook-failures.log` via `_hook_record_failure`. Session lifecycle is never blocked by telemetry failure.
- [ ] **AC-8 (manifest + allowlist):** Both new hooks carry complete `# @manifest` blocks (purpose, input, output, caller, depends-on, side-effect, failure-mode, contract, anchor: BTS-544 — following `session-boundary.sh:14-38`). Both paths land in `.ccanvil/manifest-allowlist.txt`. `module-manifest.sh validate` exits 0; `--json` reports `coverage.covered == coverage.total` and `drift_count == 0` with both totals incremented by 2 vs HEAD.
- [ ] **AC-9 (live verification, in-session smoke):** A documented smoke procedure: bring up the observability stack → open a fresh Claude Code session (or simulate via `bash .claude/hooks/session-otel-open.sh` then `.../session-otel-close.sh` with the `hook_event_name` stdin payload) → assert one `ccanvil-session` span appears in Tempo with `name=ccanvil-session`, `session.id` matching `.ccanvil/state/session-counter`-derived value, and a non-zero duration. Live-API gate per the plan (the reaper is the safety net for "didn't fire" reality).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/session-otel-open.sh` | New — SessionStart open + reaper |
| `.claude/hooks/session-otel-close.sh` | New — SessionEnd close + emit rooted span |
| `.claude/settings.json` | Append second SessionStart entry; new SessionEnd block |
| `.ccanvil/scripts/bats-report.sh` | Add `session.id` attr to `test-suite-run` + `bats suite` spans |
| `.ccanvil/manifest-allowlist.txt` | Add the two new hook paths |
| `hub/tests/session-otel-hooks.bats` | New — covers AC-2..AC-7 |

## Dependencies

- **Requires:** BTS-543 (`otel-span.sh` helper) — shipped. C1 of the umbrella.
- **Requires:** BTS-206 (`session-counter` + `session-boundary.sh`) — shipped. Provides the counter the session-id format reuses.
- **Blocked by:** none.

## Out of Scope

- Per-tool-call instrumentation (C5 / BTS-547) — Stop-hook flusher is its own ship.
- Per-script instrumentation (C3 / BTS-545) — instruments the 5 deterministic scripts to parent under this session trace.
- Dashboards (C4/C6) — BTS-546 and BTS-548.
- Multi-session interleaving / nested-Claude-Code sessions — single-session-at-a-time assumed (the state file is the single hand-off).

## Implementation Notes

- **Hook shape:** mirror `.claude/hooks/session-boundary.sh` line-for-line — `set +e`, `CLAUDE_PROJECT_DIR` fallback, source `_lib/record-failure.sh` with no-op fallback, atomic mktemp+mv writes, always `exit 0`.
- **Span emission:** source `.ccanvil/observability/otel-span.sh`, call `otel_span_cache_invariants` then `otel_span_emit --service ccanvil-session --name ccanvil-session ...`. Init failure (Collector down, otel-cli missing) is silent — `otel_span_emit` already returns 0 in that case (`otel-span.sh:138`). Hook's failure-log line is in addition: record the skip reason.
- **Reaper detection:** the existence of `.ccanvil/state/session-trace.json` at SessionStart is the abnormal-exit signal. No timestamp comparison needed — the close hook's contract is "remove the file on success."
- **State file shape:** JSON, written via `jq -n` (no inline shell interpolation — same discipline as `session-boundary.sh:130`).
- **Bats linkage seam:** `bats-report.sh` reads `.ccanvil/state/session-trace.json` near where it caches the trace/run IDs (lines ~190-220 currently). Resolve `session.id` and `claude_session_id` once into shell vars; append them to the `--attrs` strings on the suite spans only (do NOT propagate `trace_id`).
- **Stdin payload reading (AC-2):** Claude Code's SessionStart/SessionEnd events deliver a JSON payload on fd 0 — read it ONCE near the top of `session-otel-open.sh` (e.g., `payload="$(cat -)"`) before any other read on fd 0. `claude_session_id` is the only field extracted from the payload in v1 (`jq -r '.session_id // ""'`); the close hook does not read stdin (the value is sourced from the state file).
- **Hook-chaining model (load-bearing assumption):** the spec assumes Claude Code delivers an independent stdin copy of the event payload to each hook in the `SessionStart` array — `session-boundary.sh` (entry 1, doesn't consume stdin) and `session-otel-open.sh` (entry 2, consumes stdin) each see the full JSON payload on their own fd 0. This matches the observed Claude Code hook contract. If that model is wrong (shared-fd, first reader drains), AC-2's empty/malformed fallback covers the failure mode by construction: `claude_session_id` stores `""`, the omit-when-empty rule drops the attr from emitted spans, and the `session.id` primary key (derived from state files, not stdin) is unaffected. AC-9's simulated invocation must explicitly pipe the payload via `bash .claude/hooks/session-otel-open.sh < <(echo '{"hook_event_name":"SessionStart","session_id":"<uuid>","source":"startup"}')` to exercise the live contract.
- **Live-API gate (AC-9, per `.claude/rules/tdd.md`):** the Claude Code SessionEnd contract is the unknown; AC-9 is the gate. The reaper covers the failure mode.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
