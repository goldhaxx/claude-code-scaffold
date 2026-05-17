# Implementation Plan: Bats-Report Pre-Warm Stub Helper

> Feature: bts-507-bats-report-stub-helper
> Work: linear:BTS-507
> Created: 1778974762
> Spec hash: 6c7b2de3
> Based on: docs/spec.md

## Objective

Codify the BTS-281 pre-warm bypass into a shared helper, then gate future regressions via a mechanical drift-guard — turning 6 ad-hoc inline bypasses into one canonical `load` + function call, with an enforcement test that catches any new `.bats` file forgetting the pattern.

## Sequence

### Step 1: Helper substrate (AC-1)

* **Test:** Write `hub/tests/bats-report-stub-helper.bats` with one `@test` asserting that after `stub_bats_report_prewarm`:
  * `$BTS_MANIFEST_VALIDATE_CACHE` is set + non-empty
  * The file at that path exists + is non-empty
  * File content satisfies `jq -e '.coverage.covered == 0 and .coverage.total == 0 and (.drift | length) == 0 and .status == "ok"'`
  * The path starts with `$BATS_FILE_TMPDIR`
* **Implement:** Create `hub/tests/_helpers/bats-report-stub.bash` with `stub_bats_report_prewarm()` — header comment anchors BTS-507; function writes envelope to `"$BATS_FILE_TMPDIR/bats-report-stub-cache.json"` and exports `BTS_MANIFEST_VALIDATE_CACHE`.
* **Files:** NEW `hub/tests/_helpers/bats-report-stub.bash`, NEW `hub/tests/bats-report-stub-helper.bats`.
* **Verify:** `bats hub/tests/bats-report-stub-helper.bats` → green.

### Step 2: Helper idempotency (AC-2)

* **Test:** Add `@test "idempotent at file scope"` to the helper test file — calls `stub_bats_report_prewarm` twice, asserts both calls succeed, captures `$BTS_MANIFEST_VALIDATE_CACHE` after each call, asserts equality.
* **Implement:** Guard re-entry: `[[ -n "${_BATS_REPORT_STUB_CACHE:-}" ]] && { export BTS_MANIFEST_VALIDATE_CACHE="$_BATS_REPORT_STUB_CACHE"; return 0; }` at top of function; export `_BATS_REPORT_STUB_CACHE` on first write.
* **Files:** Modify `hub/tests/_helpers/bats-report-stub.bash`, extend helper test.
* **Verify:** Both `@test` blocks pass.

### Step 3: Drift-guard scan logic + synthetic fixtures (AC-5, AC-6)

* **Test:** Write `hub/tests/bats-report-stub-drift-guard.bats` with three `@test` blocks driven by synthetic per-test fixtures created in `$BATS_TEST_TMPDIR`:
  * `compliant: bats-report.sh invocation + load _helpers/bats-report-stub → no violations`
  * `exempt-marker: bats-report.sh invocation + "# bats-report-stub: exempt" → no violations`
  * `non-compliant: bats-report.sh invocation + no load + no exempt → violation; output names the offending file path` (AC-5)
* **Implement:** Inside the bats file, define `_scan_dir <dir>` that iterates `<dir>/*.bats` (one level), greps each file for `bash[^\n]*bats-report\.sh`, and for any match emits a violation line unless the file also contains `load _helpers/bats-report-stub` (via `grep -F`) OR `# bats-report-stub: exempt` (via `grep -F`). Returns 0 with empty stdout when no violations; returns 1 with violations on stdout otherwise.
* **Files:** NEW `hub/tests/bats-report-stub-drift-guard.bats`.
* **Verify:** All three synthetic-fixture tests pass.

### Step 4: Drift-guard production check (AC-4 wired) — expected RED

* **Test:** Add `@test "production scan: hub/tests/*.bats all compliant"` that calls `_scan_dir "$BATS_TEST_DIRNAME"` (= `hub/tests/`) and asserts empty violations output + exit 0.
* **Implement:** No code — this is the failing test that drives Step 5. Initial run is RED: 6 files violate (the 6 known stub-pattern-bearing call-sites). Confirm the violation list exactly matches the known 6 — if grep surfaces a 7th, expand Step 5 to cover it.
* **Files:** Modify `hub/tests/bats-report-stub-drift-guard.bats` (add production-check `@test`).
* **Verify:** Confirm RED with the expected file list; do not commit RED, proceed to Step 5.

### Step 5: Refactor all caller files (AC-3) — flip Step 4 GREEN

* **Test:** Step 4's production check is the test.
* **Implement:** For each of the 6 files, edit in place:
  * `hub/tests/bats-report-no-telemetry.bats`
  * `hub/tests/bats-report-stdout-config-line.bats`
  * `hub/tests/bats-report-otel-flatten.bats`
  * `hub/tests/docs-check-test-suite-run-healthcheck.bats`
  * `hub/tests/bats-report-failures-preserved.bats`
  * `hub/tests/bats-report-progress.bats`
    Replace inline `BTS_MANIFEST_VALIDATE_CACHE=…` blocks with: `load _helpers/bats-report-stub` (top-level) + `stub_bats_report_prewarm` (inside `setup` or `setup_file` per file's existing structure). Remove the now-dead `echo '{...}' > "$stub_cache"` lines and the `/tmp/bts-383-*-test-bypass` bare paths.
* **Files:** Modify the 6 caller files above.
* **Verify:** `bats hub/tests/bats-report-stub-drift-guard.bats` flips fully green. Each refactored file's pre-existing tests still pass: `bash .ccanvil/scripts/bats-report.sh hub/tests/bats-report-no-telemetry.bats hub/tests/bats-report-stdout-config-line.bats hub/tests/bats-report-otel-flatten.bats hub/tests/docs-check-test-suite-run-healthcheck.bats hub/tests/bats-report-failures-preserved.bats hub/tests/bats-report-progress.bats` → all pass.

### Step 6: Full-suite verification (AC-7)

* **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel` (single invocation per BTS-118 discipline; OTel stack runs as side-effect — fine).
* **Implement:** Nothing. This is the final-gate check before `/review`.
* **Files:** None modified.
* **Verify:** All bats tests pass (existing 2,425 + new helper tests + new drift-guard tests). Manifest validate is the LAST step before merge (per `feedback_test_discipline_state_intent_logic.md`).

## Risks

* **Hidden 7th caller.** Grep at spec-time confirmed 6 stub-pattern-bearing files, but the production check in Step 4 might surface additional `bash bats-report.sh` invocations I missed. Mitigation: Step 4 explicitly verifies the violation list and expands Step 5 if needed. No silent skip.
* **Bare-/tmp callers behavior change.** `bats-report-failures-preserved.bats` and `bats-report-progress.bats` currently set `BTS_MANIFEST_VALIDATE_CACHE` to a bare `/tmp/*` path WITHOUT writing valid JSON content — `bats-report.sh` only checks env-var presence, so they work today. The refactor switches them to the helper's canonical envelope under `$BATS_FILE_TMPDIR`. Behavior change is strictly better (no /tmp leakage; valid content for any future consumer) but the existing tests must still pass — Step 5's per-file verify covers this.
* **Exemption-marker grep precision.** `grep -F '# bats-report-stub: exempt'` matches literal substring anywhere in the file (including bodies of unrelated `@test` blocks). Risk: a future test could accidentally include the marker as a string literal in test data. Mitigation: convention says marker must be on a comment line at top of file; convention is documented in the helper header. Not enforced by the drift-guard itself — accepted as low-risk given the prose-only fingerprint of the exempt marker.
* **Helper test depends on** `$BATS_FILE_TMPDIR`**.** That variable is set by bats automatically for any `@test` running in the file. Standalone-execution of the helper (sourcing in a non-bats context) would fail. Out of scope — helper is bats-exclusive by design.

## Definition of Done

- [ ] All acceptance criteria (AC-1 through AC-7) pass.
- [ ] All existing tests still pass (full bats suite via `bats-report.sh --parallel`).
- [ ] No type errors (N/A — pure bash).
- [ ] Code reviewed (run `/review`).
- [ ] Manifest 198/198, drift 0 (no manifest-tracked files modified by this ship per spec Out of Scope).
