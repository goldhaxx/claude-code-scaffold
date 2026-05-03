# Feature: Bats observability + perf-core default

> Feature: bts-277-bats-observability-and-perf-core-default
> Work: linear:BTS-277
> Created: 1777754950
> Subject: Bats observability + perf-core default
> Status: Complete

## Summary

Make `bats-report.sh` ship the data we need to track suite performance over time, and bump its default parallelism from `cpu/2` to the host's perf-core count. The sweep evidence (BTS-277 research, 2026-05-02) shows `--jobs 12` saves 1:14 vs `--jobs 8` on M4 Max with no further gains past 12 — fork/IO bound at ~790% CPU. Operator's primary ask was observability ("bats runs are taking FOREVER"); the parallelism bump is a one-line incidental win the same data justifies.

## Job To Be Done

**When** I run `bash .ccanvil/scripts/bats-report.sh --parallel --json hub/tests/`,
**I want to** see wall-time + jobs + cpus alongside the existing pass/fail counts AND have the run appended to a soak-tracking log,
**So that** I can detect bats-suite regressions PR-over-PR and the upcoming BTS-283 remote-agent has a deterministic file to consume.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** **Given** a host where `sysctl -n hw.perflevel0.physicalcpu` returns a positive integer, **when** `bats-report.sh --parallel` resolves the `--jobs` value, **then** the value equals that integer (clamped to a minimum of 2). On hosts where the sysctl key is empty or non-positive (Intel Macs, Linux), it falls back to `max(2, hw.logicalcpu / 2)` — the existing formula. Verified by sourcing the wrapper with a stubbed `sysctl` and asserting the computed `jobs` value.

- [ ] **AC-2:** When `bats-report.sh --json` runs, the emitted JSON envelope contains the new fields `wall_ms` (integer ≥ 0), `jobs` (integer ≥ 1, equals the resolved jobs when `--parallel` is set, equals 1 otherwise), and `cpus` (integer ≥ 1, the value of `hw.logicalcpu` or `nproc`). All existing fields (`ok`, `not_ok`, `total`, `tail`, `raw_exit`, `timings`) remain present and unchanged in shape. Verified via `jq -e` assertions on the envelope.

- [ ] **AC-3:** When `bats-report.sh` finishes a run (any mode, any exit code), exactly one JSON object is appended to `.ccanvil/state/bats-runs.jsonl`. The object has shape `{epoch, wall_ms, ok, not_ok, total, jobs, cpus, raw_exit, parallel}` where `parallel` is a boolean reflecting whether `--parallel` was passed. The `.ccanvil/state/` directory is created if missing. Pre-existing entries in the file are preserved (append-only). Verified by capturing the file's line count before two consecutive wrapper runs, then asserting the delta equals exactly 2 and the last two parsed JSON objects have monotonically non-decreasing `epoch` values. The bats fixture must point the wrapper at a fresh `--project-dir` (or equivalent override) so it does not pollute the repo's real `.ccanvil/state/bats-runs.jsonl`.

- [ ] **AC-4:** When `bats-report.sh --help` runs, the output mentions (a) the new perf-core default for `--jobs`, (b) the `wall_ms`/`jobs`/`cpus` fields in the JSON envelope, and (c) the `.ccanvil/state/bats-runs.jsonl` append behavior. Verified by `grep -qF` on each anchor string against the help output.

- [ ] **AC-5 (error path):** When `.ccanvil/state/` exists but is not writable (e.g., permission stripped), the wrapper prints `WARN: bats-runs.jsonl append skipped — <reason>` to stderr and continues with the existing exit-code-mirrors-bats behavior. The wrapper does NOT fail the run on jsonl-write failure. Verified by `chmod -w .ccanvil/state/` in a test fixture and asserting `WARN:` on stderr + exit code matches bats's exit.

- [ ] **AC-6 (regression):** All existing `bats-report.sh` tests in `hub/tests/` continue to pass. The manifest entry for `bats-report.sh` is updated to declare the new `side-effect: writes-bats-runs-jsonl` and any new `failure-mode` entries; manifest validate passes with drift count 0. Verified by `bash .ccanvil/scripts/module-manifest.sh validate --json` returning `status: ok`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/bats-report.sh` | Modified — perf-core jobs detection, JSON envelope additions, jsonl append, --help update, manifest declarations |
| `hub/tests/bats-report.bats` | Modified — AC-4 help anchors + AC-6 regression coverage retained |
| `hub/tests/bats-report-perf-core-default.bats` | New — AC-1 jobs detection (stubbed sysctl) |
| `hub/tests/bats-report-metrics-envelope.bats` | New — AC-2 + AC-3 envelope + jsonl append |
| `hub/tests/bats-report-jsonl-write-failure.bats` | New — AC-5 unwritable .ccanvil/state/ |
| `.ccanvil/state/bats-runs.jsonl` | New — append-only NDJSON; gitignored |
| `.gitignore` | Modified — ignore `.ccanvil/state/bats-runs.jsonl` |

## Dependencies

- **Requires:** nothing. `bats-report.sh` and the manifest substrate are stable.
- **Blocked by:** nothing.

## Out of Scope

- Subprocess fork-pressure / shared per-file fixtures (captured as **BTS-281** — the ~5000s-CPU win that requires per-bats-file refactoring).
- Subprocess profiling tooling (captured as **BTS-282** — pre-req for BTS-281; produces the data that says which substrate calls to share-cache).
- Soak-tracking remote agent (captured as **BTS-283** — consumes the `.jsonl` this ticket emits).
- Replacing bats. Splitting tests across machines.
- Auto-promoting `--parallel` to default (still opt-in; this ticket only changes the value used when --parallel is passed).

## Implementation Notes

- **Jobs detection.** Add a small helper above the existing parallel branch:
  ```bash
  perf=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "")
  if [[ -n "$perf" && "$perf" -ge 2 ]]; then
    jobs="$perf"
  else
    jobs=$((cpus / 2))
    (( jobs < 2 )) && jobs=2
  fi
  ```
  Mirror the existing `BATS_REPORT_HAS_PARALLEL` testability hook with a `BATS_REPORT_PERF_CORES` override (env var that wins over the sysctl probe) so the bats fixture can assert deterministic outputs without depending on the host.
- **Wall timer.** Capture `start_ns=$(date +%s%N)` before the bats invocation and `end_ns` after; `wall_ms=$(( (end_ns - start_ns) / 1000000 ))`. macOS `date +%s%N` returns literal `N` — use `python3 -c 'import time; print(int(time.time()*1000))'` or `gdate` if installed; safest is `EPOCHREALTIME` (bash 5+) — but ccanvil runs on bash 3.2 too. Concrete: use `perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time()*1000'` (macOS ships perl). Validate in the fixture.
- **Jsonl append.** Compose the line via `jq -c -n --argjson <fields>` (deterministic shape, no string-interp). Write with `>> "$file" 2>/dev/null || echo "WARN: ..."`.
- **Manifest update.** Bats-report.sh's manifest gains a new `side-effect: writes-bats-runs-jsonl` declaration and any new failure-modes; the new perf-core branch is a refinement of the existing parallel-jobs path (no new caller/depends-on changes expected — verify via drift-guard).
- **Live-API gate (TDD rule):** AC-1 stubs sysctl, but the wrapper actually shells out — validate live by running on this M4 Max host and asserting `jobs=12` is computed before commit. Mirrors the BTS-171 live-validation discipline.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
