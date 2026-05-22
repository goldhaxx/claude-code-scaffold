# Implementation Plan: test-suite-run end-to-end trace

> Feature: bts-560-test-suite-run-end-to-end-trace
> Work: linear:BTS-560
> Created: 1779478872
> Spec hash: e5685c6f
> Based on: docs/spec.md

## Objective

Instrument `bats-report.sh` so a `test-suite-run` invocation emits one rooted OpenTelemetry trace — a `test-suite-run` root span with `manifest pre-warm`, `bats suite`, and `otel-flatten` phase spans beneath it.

## Sequence

Each step is one red-green-refactor cycle. Tests live in the new `hub/tests/bats-report-end-to-end-trace.bats`, using the `OTEL_SPAN_CLI` recording-stub seam (a stub that appends its argv to a file) plus `OTEL_SPAN_INIT_DONE=1` / `OTEL_SPAN_LIVE=1` to force emission offline. Assertions use `grep` (never a non-final bare `[[ ]]` — BTS-127 strict-mode-bats discipline).

### Step 1: Root span — `test-suite-run`

* **Test:** Build the harness — recording-stub `otel-cli`, a 1-test stub `.bats` suite, and reuse `hub/tests/_helpers/bats-report-stub` (`stub_bats_report_prewarm`, as in `docs-check-test-suite-run-healthcheck.bats`). Invoke `bats-report.sh` under the stub seam; assert the recording holds a span `--name test-suite-run` with `--service ccanvil-test`, a `--force-trace-id`, and **no** `--force-parent-span-id`.
* **Implement:** Near the trace-id / suite-span-id block (`bats-report.sh` \~195-205), generate `BTS_TELEMETRY_RUN_SPAN_ID` (`openssl rand -hex 8`) and capture `BTS_TELEMETRY_RUN_START_EPOCH`. At end-of-script (after the flatten block, before `exit`) emit the root span via `otel_span_emit` — service `ccanvil-test`, name `test-suite-run`, start = run-start epoch, end = now, `--trace-id`/`--span-id` set, no parent. Gate on `command -v "${OTEL_SPAN_CLI:-otel-cli}"` (honor the test seam) + `no_telemetry == 0` + trace id set.
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-end-to-end-trace.bats` (new).
* **Verify:** targeted run of the new test file → AC-1 green.

### Step 2: Re-parent the `bats suite` span; hierarchy unchanged

* **Test:** Assert the `bats suite (...)` span's argv carries `--force-parent-span-id <root span id>` and keeps `--force-span-id <BTS_TELEMETRY_SUITE_SPAN_ID>`. Assert (AC-7) per-file spans still emit `--force-parent-span-id <suite span id>`.
* **Implement:** Add `--parent-id "$BTS_TELEMETRY_RUN_SPAN_ID"` to the existing suite-span `otel_span_emit` call (\~537-546). Do **not** modify `telemetry.bash`.
* **Files:** `.ccanvil/scripts/bats-report.sh`, test file.
* **Verify:** AC-4, AC-7 green.

### Step 3: `manifest pre-warm` phase span

* **Test:** Assert a span `--name "manifest pre-warm"` with `--force-parent-span-id <root span id>`, sharing the trace id. (Confirm `stub_bats_report_prewarm` fast-stubs the pre-warm rather than skipping it — AC-3 needs the pre-warm block to execute.)
* **Implement:** Capture start epoch immediately before the pre-warm block (\~211) and end epoch immediately after (\~218); emit a `manifest pre-warm` span (parent = root span id, attr `phase=manifest-prewarm`) only when the pre-warm actually ran.
* **Files:** `.ccanvil/scripts/bats-report.sh`, test file.
* **Verify:** AC-3 green.

### Step 4: `otel-flatten` phase span

* **Test:** Parallel-mode run → assert an `otel-flatten` span with `--force-parent-span-id <root span id>`. Serial-mode run → assert **no** `otel-flatten` span.
* **Implement:** Capture start/end epochs around the flatten block (\~556-564); emit an `otel-flatten` span (parent = root, attr `phase=otel-flatten`) only inside the `parallel_mode == 1` branch.
* **Files:** `.ccanvil/scripts/bats-report.sh`, test file.
* **Verify:** AC-5 green.

### Step 5: Cross-cutting — root covers all phases; one trace

* **Test:** Assert root `--start` ≤ `manifest pre-warm` span start AND root `--end` ≥ the last phase span's end. Assert root + `manifest pre-warm` + `bats suite` + `otel-flatten` all carry the same `--force-trace-id`. May be green-on-write if Steps 1-4 are correct; if red, fix epoch capture / trace-id propagation.
* **Implement:** Adjust root-span start/end epoch capture if the test reveals a gap.
* **Files:** `.ccanvil/scripts/bats-report.sh`, test file.
* **Verify:** AC-2, AC-6 green.

### Step 6: Edge — graceful skip + pre-warm skipped

* **Test:** AC-8 — invoke with `--no-telemetry` → assert zero `test-suite-run` / `manifest pre-warm` / `otel-flatten` spans recorded AND the bats exit code unchanged. AC-9 — invoke with `BTS_MANIFEST_VALIDATE_CACHE` preset → assert no `manifest pre-warm` span, root + `bats suite` spans still form a valid single-rooted trace.
* **Implement:** Confirm each new span block is gated on `no_telemetry == 0` and emits only when its phase ran.
* **Files:** `.ccanvil/scripts/bats-report.sh`, test file.
* **Verify:** AC-8, AC-9 green.

### Step 7: Manifest block, SCHEMA.md, guide docs

* **Test:** `module-manifest.sh validate` clean; `git diff main...HEAD | module-manifest.sh diff-vs-manifest --diff -` clean.
* **Implement:** Update `bats-report.sh`'s `# @manifest` block — declare any new `@side-effect`/`@failure-mode` marker introduced, add `# anchor: BTS-560`. Add a "Root & phase span schema" section to `.ccanvil/observability/SCHEMA.md` (additive). Update `.ccanvil/observability/README.md` if it describes the trace structure.
* **Files:** `.ccanvil/scripts/bats-report.sh` (manifest block), `.ccanvil/observability/SCHEMA.md`, `.ccanvil/observability/README.md` (as needed).
* **Verify:** `module-manifest.sh validate` + `diff-vs-manifest` both clean.

## Risks

* **Test seam gating.** `bats-report.sh:528` gates the suite-span block on literal `command -v otel-cli`. New phase-span code must gate on `command -v "${OTEL_SPAN_CLI:-otel-cli}"` so the recording stub is honored without a real `otel-cli` on PATH. Resolved in Step 1 when the harness is built.
* **Pre-warm cost in tests.** AC-3 needs the pre-warm to execute; the real `module-manifest.sh validate` is multi-minute. The harness must fast-stub `module-manifest.sh` (verify `stub_bats_report_prewarm` does this, not a skip).
* **D1 dashboard root-name shift.** The new root changes the trace root from `bats suite (...)` to `test-suite-run`. D1 query tuning is out of scope (BTS-533), but the live check below must confirm D1 still renders the suite→file→test drill-down.

## Live verification (activation check — BTS-497 discipline)

After Step 7, before `/review`: with the OTel stack up, run the real suite via `test-suite-run --parallel`, then query Tempo for the run's trace and confirm it shows the `test-suite-run` root with `manifest pre-warm` + `bats suite` + `otel-flatten` children, and the suite→file→test drill-down beneath `bats suite`. Stub tests verify argv shape; only a live run verifies the trace renders and nests correctly.

## Definition of Done

- [ ] AC-1 through AC-9 pass
- [ ] All existing tests still pass (full suite — the `/pr` gate)
- [ ] `module-manifest.sh validate` + `diff-vs-manifest` clean
- [ ] Live Tempo check confirms the end-to-end trace renders
- [ ] Code reviewed (`/review`)
