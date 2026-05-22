# Implementation Plan: pytest dispatcher arm for test-suite-run

> Feature: bts-558-pytest-test-suite-dispatcher
> Work: linear:BTS-558
> Created: 1779421069
> Spec hash: e6445207
> Based on: docs/spec.md

## Objective

Add a `pytest` arm to `cmd_test_suite_run` (`.ccanvil/scripts/docs-check.sh`) so a
node with `test-provider: pytest` routes `test-suite-run` to its real pytest suite
with honest exit-code propagation — no error, no false green.

## Sequence

Each step is one red-green-refactor cycle. Targeted test file only per cycle
(`.claude/rules/tdd.md`); the full suite is the pre-merge gate, not a per-cycle run.

### Step 1: Gate the OTel healthcheck to the bats provider (AC-6)

* **Test:** In `docs-check-test-suite-run-healthcheck.bats`, add a test: a project
  with `test-provider: pytest` + `CCANVIL_TELEMETRY_URL=http://127.0.0.1:1`
  (unreachable) → output does NOT contain the `Collector|healthcheck|unreachable`
  error. (At this step it still exits 2 via the `*)` arm — assert the healthcheck
  message is absent, not the exit code.)
* **Implement:** Wrap the healthcheck block (`docs-check.sh:8225-8242`) in
  `if [[ "$provider" == bats ]]; then … fi`. Add a `# BTS-559:` comment marking the
  carve-out as temporary.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/docs-check-test-suite-run-healthcheck.bats`
* **Verify:** `bats hub/tests/docs-check-test-suite-run-healthcheck.bats` — new test
  green, existing AC-2 bats tests still green (bats path keeps the healthcheck).
* **Why first:** removes the Collector dependency for every pytest test in Steps 2-5.

### Step 2: pytest arm skeleton + missing-test-command error (AC-4)

* **Test:** In `test-suite-run.bats`, REPLACE the obsolete `pytest provider exits 2 with not-yet-implemented stderr` test (line 44) with: `test-provider: pytest` and
  NO `test-command` key → exit 2, stderr names the missing `test-command` key.
* **Implement:** Add a `pytest)` arm to the `case "$provider"`. Read
  `test-command` via `jq -r '.["test-command"] // ""'` from the resolved `$config`.
  Empty → print an actionable stderr error naming `test-command`, `return 2`.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/test-suite-run.bats`
* **Verify:** `bats hub/tests/test-suite-run.bats` — new test green; the `vitest`
  exit-2 test untouched and still green.

### Step 3: Happy path — run the node pytest command + test-path (AC-1)

* **Test:** `test-provider: pytest`, `test-command` points at a stub that echoes its
  argv and `exit 0`, `test-path: src/` set → dispatcher exits 0 and the stub argv
  contains `src/`. Second test: no `test-path` key → stub runs, argv has no path arg.
* **Implement:** In the `pytest)` arm, read `test-path` (`// ""`). Build the argv:
  word-split `test-command`, append `test-path` when non-empty. Run inside a
  `cd "$project_dir"` subshell. Capture rc with the set -e-safe pattern:
  `if ( cd "$project_dir" && eval "$cmd" ); then rc=0; else rc=$?; fi` — `set -euo pipefail` is on (`docs-check.sh:9`), so a bare `( … ); rc=$?` aborts before capture.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/test-suite-run.bats`
* **Verify:** `bats hub/tests/test-suite-run.bats` — AC-1 tests green.

### Step 4: Exit-code propagation — failure + no-tests normalization (AC-2, AC-5)

* **Test:** stub `exit 1` → dispatcher exits non-zero. stub `exit 5` → dispatcher
  exits 1 (normalized) and stderr contains `no tests collected`.
* **Implement:** After rc capture: `5` → set rc=1, emit the `no tests collected`
  stderr line; `0` → 0; any other non-zero → pass through unchanged. `return $rc`.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/test-suite-run.bats`
* **Verify:** `bats hub/tests/test-suite-run.bats` — AC-2/AC-5 tests green.

### Step 5: forward_args interpretation — --parallel translation + bats-only drops (AC-3, AC-8)

* **Test:** stub echoes argv. `--parallel` → argv contains `-n auto`, not literal
  `--parallel`. `--json --timings --progress --no-telemetry --slow-top 5` → none of
  those tokens (nor the `5`) reach the stub; dispatcher does not crash. `-- -k foo`
  → `-k foo` reaches the stub verbatim.
* **Implement:** Before building argv, walk `forward_args` (use the
  `"${forward_args[@]+...}"` set -u-safe expansion already in the function): `--parallel`
  → collect `-n auto`; `--json|--timings|--progress|--no-telemetry` → skip;
  `--slow-top` → skip it and the next token; `--` → forward the remainder verbatim;
  bare positionals → forward verbatim.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/test-suite-run.bats`
* **Verify:** `bats hub/tests/test-suite-run.bats` — AC-3/AC-8 tests green.

### Step 6: Manifest sync (drift-guard gate)

* **Test:** none (deterministic) — the verify step IS the test.
* **Implement:** In `cmd_test_suite_run`'s `# @manifest` block, add `# failure-mode:`
  lines for `missing-test-command` (exit=2) and `pytest-no-tests-collected` (exit=1).
  Add matching `# @failure-mode: missing-test-command` / `# @failure-mode: pytest-no-tests-collected` code markers at the two new failure sites in the pytest
  arm.
* **Files:** `.ccanvil/scripts/docs-check.sh`
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate --json` clean for
  the function; `git diff main...HEAD | bash .ccanvil/scripts/module-manifest.sh diff-vs-manifest --diff -` returns `status: ok`.

### Step 7: Document the node-config keys (hub guide)

* **Test:** none (doc-only) — drift-guarded by the existing `configuration.md`
  content assertions in `test-suite-run.bats` (AC-5 block); confirm they still pass.
* **Implement:** In `.ccanvil/guide/configuration.md` (hub section, above
  `NODE-SPECIFIC-START`), document `test-command` and `test-path` — what they are,
  that pytest nodes set them, and the fieldnation-toolbox example.
* **Files:** `.ccanvil/guide/configuration.md`
* **Verify:** `bats hub/tests/test-suite-run.bats` — the configuration.md content
  tests still green.

## Risks

* **set -e rc capture.** `docs-check.sh` runs `set -euo pipefail`. A bare
  `( cmd ); rc=$?` aborts before capture — use `if ( … ); then rc=0; else rc=$?; fi`
  (anchored: prior `set -e` rc-capture incident).
* **Stubbed pytest, not live.** Tests stub `test-command`, so the exit-code mapping
  (esp. `5` → no tests) and `-n auto` are verified against documented pytest
  behavior, not a live pytest run — there is no Python suite in this hub repo. pytest
  exit codes are a stable documented contract; the true live integration test is
  fieldnation-toolbox BTS-552 flipping its config. If `python3 -m pytest` is
  available in the dev env, optionally run a 2-test throwaway in Step 4 to confirm
  `exit 0` and `exit 5` empirically.
* **Obsolete test.** The line-44 `pytest provider exits 2 / not-yet-implemented` test
  becomes wrong — Step 2 REPLACES it (does not add alongside), or the suite fails.
* **Manifest drift-guard blocks the PR.** New failure modes must be declared in the
  `@manifest` block AND have matching code markers (Step 6), or BTS-268 diff-vs-manifest
  blocks `/review` and `/pr`.

## Definition of Done

- [ ] All 8 acceptance criteria from spec pass
- [ ] All existing tests still pass — incl. AC-7 (bats arm byte-for-byte unchanged)
- [ ] Manifest validate + diff-vs-manifest clean
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
