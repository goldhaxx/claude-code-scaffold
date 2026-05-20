# Implementation Plan: Generic otel-span.sh helper library

> Feature: bts-543-otel-span-helper
> Work: linear:BTS-543
> Created: 1779311751
> Spec hash: 22d4105a
> Based on: docs/spec.md

## Objective

Extract OTel span mechanics from the bats telemetry helper into a standalone, sourceable `otel-span.sh` library, and refactor `telemetry.bash` + `bats-report.sh` to consume it — with byte-identical emitted spans.

## Sequence

### Step 1: Capture the behavior-preservation baseline
- **Test:** n/a — prep step for AC-8.
- **Implement:** ensure the observability stack is up; run the full bats suite telemetry-enabled; run `otel-flatten.sh`; snapshot the `(test_name, test_file, test_outcome)` tuple set and the record-key set from `test-runs.jsonl` to a scratch baseline file outside the repo tree.
- **Files:** none committed — the baseline snapshot is a scratch artifact.
- **Verify:** the baseline snapshot is non-empty and holds the expected ~2500 test tuples.

### Step 2: otel-span.sh scaffold + ID generation (TDD)
- **Test:** new `hub/tests/otel-span.bats` — `otel_span_new_trace_id` returns 32 lowercase hex chars; `otel_span_new_span_id` returns 16; both still work with `openssl` removed from PATH (AC-2). Confirm red first.
- **Implement:** create `.ccanvil/observability/otel-span.sh`; lift the trace/span ID generation (openssl + shasum fallback) verbatim from `telemetry.bash` lines 96-102.
- **Files:** `.ccanvil/observability/otel-span.sh` (new), `hub/tests/otel-span.bats` (new).
- **Verify:** `bats hub/tests/otel-span.bats` — green.

### Step 3: otel_span_sanitize (TDD)
- **Test:** `otel-span.bats` — input with commas yields semicolons; input without commas is unchanged (AC-3).
- **Implement:** lift `_telemetry_sanitize` (telemetry.bash 117-122) as `otel_span_sanitize`.
- **Files:** `.ccanvil/observability/otel-span.sh`, `hub/tests/otel-span.bats`.
- **Verify:** targeted bats green.

### Step 4: otel_span_cache_invariants + otel_span_init (TDD)
- **Test:** `otel-span.bats` — `otel_span_cache_invariants` exports git.sha / project-root / run-id; `otel_span_init` resolves the endpoint from `CCANVIL_OTLP_ENDPOINT` and sets a live-or-skip flag; `CCANVIL_TELEMETRY_DISABLED` forces the skip flag with no probe.
- **Implement:** lift the generic half of `_telemetry_cache_invariants` (telemetry.bash 80, 85-87, 96-102); write `otel_span_init` (endpoint resolution + one healthcheck probe + cached live flag; disabled means skip with no probe).
- **Files:** `.ccanvil/observability/otel-span.sh`, `hub/tests/otel-span.bats`.
- **Verify:** targeted bats green.

### Step 5: otel_span_emit (TDD)
- **Test:** `otel-span.bats` — with `CCANVIL_TELEMETRY_DISABLED` set, emits nothing and returns 0 (AC-4); with the Collector unreachable, returns 0 (AC-5); the constructed otel-cli argv carries every expected flag (assert via an `otel-cli` stub on PATH that records its argv).
- **Implement:** `otel_span_emit` — parse named flags, build the otel-cli argv as a byte-identical 1:1 flag mapping to telemetry.bash 262-274 / 178-190, graceful-skip when not live, `|| true` on the call.
- **Files:** `.ccanvil/observability/otel-span.sh`, `hub/tests/otel-span.bats`.
- **Verify:** targeted bats green.

### Step 6: otel_span_run (TDD)
- **Test:** `otel-span.bats` — wraps a command and returns the wrapped exit code (0 and non-zero cases); emits a span with `duration_ms` + `exit.code` attributes (verified via the otel-cli stub); under `CCANVIL_TELEMETRY_DISABLED` the wrapped command still runs (AC-6, AC-4).
- **Implement:** `otel_span_run` — capture start, run the wrapped command, capture end + exit, call `otel_span_emit`, return the wrapped exit code.
- **Files:** `.ccanvil/observability/otel-span.sh`, `hub/tests/otel-span.bats`.
- **Verify:** targeted bats green.

### Step 7: Refactor telemetry.bash to consume the helper (behavior-preserving)
- **Test:** AC-7 — an `otel-span.bats` check that sourcing `telemetry.bash` defines the four lifecycle functions. Existing telemetry-touching tests (`observability-stack-smoke.bats`, telemetry-inject tests) stay green.
- **Implement:** `telemetry.bash` sources `otel-span.sh`; `_telemetry_sanitize` becomes a call to `otel_span_sanitize`; the `otel-cli span` blocks in `telemetry_teardown` (262-274) and `telemetry_teardown_file` (178-190) become `otel_span_emit` calls; `_telemetry_cache_invariants` delegates the generic part to `otel_span_cache_invariants` and keeps the bats-specific `BTS_TELEMETRY_*` exports. The four lifecycle function names are frozen. The hard-fail Collector healthcheck stays in `telemetry.bash`.
- **Files:** `hub/tests/_helpers/telemetry.bash`.
- **Verify:** run 2-3 telemetry-enabled bats files; confirm spans still emit (TraceQL spot-check) and the lifecycle functions behave.

### Step 8: Refactor bats-report.sh suite-root span (behavior-preserving)
- **Test:** AC-9 — the suite-root span still carries the `suite.*` attributes plus the forced trace/span IDs.
- **Implement:** replace the inline `otel-cli span` block in `bats-report.sh` (~519-545) with an `otel_span_emit` call sourcing `otel-span.sh`. Same `--service`, `--name`, attrs, forced trace/span IDs, `--timeout 5s`.
- **Files:** `.ccanvil/scripts/bats-report.sh`.
- **Verify:** a small telemetry-enabled `bats-report.sh` run emits a suite-root span with the expected attributes (TraceQL spot-check).

### Step 9: Manifest block + allowlist (TDD)
- **Test:** `module-manifest.sh validate --json` — after the change, coverage includes `otel-span.sh` and drift is empty (AC-10).
- **Implement:** add a complete file-level `# @manifest` block to `otel-span.sh` (purpose, input, output, caller listing `telemetry.bash` + `bats-report.sh`, depends-on otel-cli/curl/openssl/jq, side-effect, failure-mode, contract, anchor BTS-543); add the path to `.ccanvil/manifest-allowlist.txt` under a BTS-543 comment. Ordered after Steps 7-8 so the `caller:` entries grep-resolve.
- **Files:** `.ccanvil/observability/otel-span.sh`, `.ccanvil/manifest-allowlist.txt`.
- **Verify:** `module-manifest.sh validate --json` — status ok, otel-span.sh covered.

### Step 10: Behavior-preservation gate (AC-8) + full suite
- **Test:** AC-8 — run the full bats suite telemetry-enabled post-refactor; run `otel-flatten.sh`; diff the `(test_name, test_file, test_outcome)` tuple set and the record-key set against the Step 1 baseline — must be identical.
- **Implement:** none — verification only. A non-empty diff means the refactor is wrong; fix and re-run.
- **Files:** none.
- **Verify:** diff empty; full suite green; `module-manifest.sh validate` clean.

### Step 11: Documentation
- **Test:** n/a.
- **Implement:** add `otel-span.sh` to the `.ccanvil/observability/README.md` files table with a one-line purpose; if `.ccanvil/guide/` carries an observability or scripts reference, note the new helper there.
- **Files:** `.ccanvil/observability/README.md`, possibly `.ccanvil/guide/<section>.md`.
- **Verify:** README renders; doc references resolve.

## Risks

- **AC-8 wall-time.** A full telemetry-enabled suite run is ~10-15 min (manifest pre-warm + per-test span emission). Step 1 (baseline) and Step 10 (gate) are two such runs. Mitigation: Step 10's run doubles as the `/pr` pre-merge gate, so only the Step 1 baseline is genuinely extra.
- **Byte-identical argv drift.** If `otel_span_emit` reorders or renames a flag, AC-8 fails. Mitigation: map flags 1:1 from the telemetry.bash source blocks; the otel-cli stub test in Step 5 asserts argv shape.
- **Hidden bats coupling.** `_telemetry_compose_attrs` and the `BTS_TELEMETRY_*` env contract must stay in telemetry.bash. Mitigation: Step 7 explicitly keeps them; the four lifecycle function names are frozen (`inject-telemetry-source.sh` depends on them).
- **Observability stack down.** Steps 1, 7, 8, 10 need the Collector + Tempo up. Mitigation: bring the stack up first via the observability docker-compose.

## Definition of Done

- [ ] All 11 acceptance criteria from the spec pass
- [ ] All existing tests still pass (full suite, Step 10)
- [ ] Manifest validate clean (zero drift)
- [ ] Behavior-preservation diff (AC-8) empty
- [ ] Code reviewed (run /review)
