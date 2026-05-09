# Implementation Plan: Test execution velocity — bats observability + manifest incremental

> Feature: bts-383-test-execution-velocity
> Work: linear:BTS-383
> Created: 1778354214
> Spec hash: 5b9c790b
> Based on: docs/spec.md

## Objective

Ship two substrate observability fixes (`bats-report.sh --progress` + `--json failures` + `module-manifest.sh validate --changed-only`) so iteration test cycles drop from 30 min full-suite to <30s targeted, with streaming heartbeats eliminating the "is it hung?" failure mode that drove the 1-2 hour idle-wait incident on BTS-316.

## Sequence

Each step is one R-G-R cycle. Targeted bats only (BTS-383 own discipline). Full-suite reserved for the `/pr` step (AC-12).

### Step 1: AC-1 — `--progress` flag emits per-file completion lines (RED)

* **Test:** Add `hub/tests/bats-report-progress.bats` with one failing test: a 2-file fixture tree (one fast, one slow), assert `bash bats-report.sh --progress hub/tests/fixtures/bats-progress/*.bats` stdout contains `[1/2]` and `[2/2]` markers each followed by `<file>:` and `PASS X/Y in T.Ts`.
* **Implement:** None yet — assert RED.
* **Files:** `hub/tests/bats-report-progress.bats` (new), `hub/tests/fixtures/bats-progress/fast.bats` + `slow.bats` (new fixtures).
* **Verify:** `bats hub/tests/bats-report-progress.bats` reports 1 failure (flag not implemented).

### Step 2: AC-1 — implement per-file orchestrated `--progress` (GREEN)

* **Test:** Re-run Step 1 test; expect green.
* **Implement:** Add `--progress` arg parser to `bats-report.sh`. When set, replace the single `bats <files>` invocation with a per-file orchestrated loop: iterate file list, run `bats --tap <file>` per file (foreground or background-with-bounded-pool when `--parallel` also set), capture each file's exit + stdout, emit `[N/M] <file>: PASS X/Y in T.Ts` (or `FAIL X/Y in T.Ts`) to stderr after each file completes. Aggregate the captured TAP into the same final summary today's path produces (so `--json` and `bats-runs.jsonl` paths stay identical at end-of-run).
* **Files:** `.ccanvil/scripts/bats-report.sh`.
* **Verify:** Step 1 test passes; existing non-`--progress` runs unchanged (regression check by re-running `bats hub/tests/bats-report*.bats`).

### Step 3: AC-1 — heartbeat at 30s+ idle (RED → GREEN)

* **Test:** Extend `bats-report-progress.bats` with a second test: a fixture file that sleeps 35 seconds, assert `--progress` stdout contains a `[heartbeat]` (or equivalent) marker between the file-start and file-end emissions.
* **Implement:** When `--progress` enabled, spawn a background `(while sleep 30; do printf '[heartbeat] still working — %ds elapsed\n' $((SECONDS-start)) >&2; done) &` keyed on no per-file emission in the last 30s. Cleanup trap ensures the heartbeat process dies on EXIT/INT/TERM.
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/fixtures/bats-progress/slow.bats` (extended to sleep 35s when `BATS_PROGRESS_TEST_SLOW=1`).
* **Verify:** Second progress test passes; cleanup verified (no zombie sleep processes after run).

### Step 4: AC-2 — `--json` preserves per-failure detail (RED)

* **Test:** Add `hub/tests/bats-report-failures-preserved.bats`: forced-fail fixture (one passing, one failing test), run `--json`, assert envelope shape `{ok, not_ok, total, failures: [{test_name, file, line_number, error_excerpt}]}`. Empty array case: all-pass fixture → `failures == []`.
* **Implement:** None yet — RED.
* **Files:** `hub/tests/bats-report-failures-preserved.bats` (new), `hub/tests/fixtures/bats-progress/fail.bats` (new — single deliberate-failure).
* **Verify:** Test fails because current `--json` envelope lacks `failures` key.

### Step 5: AC-2 — implement TAP parsing for failure detail (GREEN)

* **Test:** Step 4's failure-shape test passes.
* **Implement:** In `bats-report.sh`, after capturing TAP output, parse for `not ok N - <name>` lines + accumulate the next 3-5 indented `#` lines as `error_excerpt`. Extract `file` and `line_number` from `# (in test file <path>, line N)` comments emitted by bats. Emit as `failures: []` array in the JSON envelope.
* **Files:** `.ccanvil/scripts/bats-report.sh`.
* **Verify:** Step 4 test passes both branches (fail-fixture has correct shape; all-pass fixture has `failures: []`).

### Step 6: AC-3 — `bats-runs.jsonl` carries failure detail (RED → GREEN)

* **Test:** Extend `bats-report-failures-preserved.bats` with a third test: after a `--json` run with failures, `tail -1 .ccanvil/state/bats-runs.jsonl | jq '.failures'` returns the same array.
* **Implement:** Update the BTS-277 jsonl writer block in `bats-report.sh` (\~line 262-285) to include `failures` in the appended record. Update the writer's `# @manifest` block + `output:` description to declare the new field.
* **Files:** `.ccanvil/scripts/bats-report.sh`.
* **Verify:** Test passes; backward-compat: older readers see `failures: []` on success runs (no breaking shape change).

### Step 7: AC-4 — `module-manifest.sh validate --changed-only` (RED)

* **Test:** Add `hub/tests/module-manifest-changed-only.bats` with first failing test: `bash module-manifest.sh validate --changed-only --since HEAD~1 --json` accepts both flags, emits envelope `{coverage: {covered, total}, drift: [...], info: [...], scanned_files: [...]}`. The `scanned_files` array equals the intersection of `git diff --name-only HEAD~1` ∩ allowlist.
* **Implement:** None yet — RED.
* **Files:** `hub/tests/module-manifest-changed-only.bats` (new).
* **Verify:** Test fails with "unknown flag: --changed-only" or similar.

### Step 8: AC-4/AC-5 — implement git-diff-scoped extract+validate (GREEN)

* **Test:** Step 7 test passes.
* **Implement:** Add `--changed-only` and `--since <ref>` flag parsing to `cmd_validate` (default ref = `HEAD~1`). Compute `git diff --name-only <ref>...HEAD` filtered by the allowlist, store in a scoped `_files_to_scan` array. Pass that array down to `_extract_manifests` (already file-keyed). Drift detection iterates only the scoped subset. Emit `scanned_files` in JSON envelope. Empty diff → `coverage: {covered:0, total:0}, scanned_files:[]` (not an error).
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** Step 7 test passes; full validate (no `--changed-only`) emits identical envelope shape as before (regression check via existing `hub/tests/module-manifest.bats`).

### Step 9: AC-4 — perf assertion <5s on 1-3 file diff (RED → GREEN)

* **Test:** Extend `module-manifest-changed-only.bats` with a second test: edit-stage one fixture file, run `--changed-only --since HEAD`, capture wall time, assert <5000ms.
* **Implement:** If perf already passes, no change. If not, audit the inner loop for full-tree scans that should be subset-aware (likely candidates: caller-index build at line 485, target-body-index at line 347).
* **Files:** `.ccanvil/scripts/module-manifest.sh` (only if optimization needed).
* **Verify:** Perf test passes consistently across 3 runs.

### Step 10: AC-6/AC-7 — verify rules already present on branch

* **Test:** None new — read-only verification.
* **Implement:** Read `.claude/rules/tdd.md` on this branch, confirm "Test execution discipline" section exists and anchors back to BTS-383. Read `.claude/rules/background-task-discipline.md`, confirm wait-loop / parallel-runs / buffered-output sections + anti-pattern catalog table all present.
* **Files:** None modified — verification only.
* **Verify:** Manual read confirms presence. AC-6 + AC-7 stay unchecked-then-checked in spec; the rules half landed in the BTS-316 PR.

### Step 11: AC-11 — manifests for new functions

* **Test:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json`. Expect `drift: []` and `coverage.covered == coverage.total` after the new `--progress` heartbeat helper, the `--changed-only` flag handler, and any internal helpers we added are manifest-blocked.
* **Implement:** Add `# @manifest` blocks to any new top-level functions or major helpers we created in steps 1-9. Update `.ccanvil/manifest-allowlist.txt` if we added new `cmd_*` surfaces (likely none — we extended existing `cmd_validate`).
* **Files:** `.ccanvil/scripts/bats-report.sh`, `.ccanvil/scripts/module-manifest.sh`, possibly `.ccanvil/manifest-allowlist.txt`.
* **Verify:** Validate passes with drift 0.

### Step 12: AC-12/AC-13 — full-suite verification at /pr only

* **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel` ONE TIME at the `/pr` step's pre-flight (BTS-118 single-call discipline). Expect test count grew by 3 fixture files (Steps 1, 4, 7), tests pass.
* **Implement:** None — verification only.
* **Files:** None.
* **Verify:** Full-suite green; `bats-runs.jsonl` tail entry shows expected counts.

## Risks

* `--progress` × `--parallel` interaction: bats's native `--jobs N` interleaves stdout, breaking per-file boundary detection. Mitigation: `--progress` mode replaces `bats --jobs N` with our own per-file parallel orchestration (bounded subprocess pool). Net effect on parallel run-time should be ≤ 5% slower than native `--jobs` because the bounded-pool semantics match.
* **Heartbeat zombie risk:** the background heartbeat process must die when the parent exits. Mitigation: install `trap 'kill $HEARTBEAT_PID 2>/dev/null' EXIT INT TERM` immediately after spawn. Verified by Step 3's cleanup check.
* **Empty-diff edge case in** `--changed-only`: `git diff --name-only` may return empty if no allowlisted files changed. Must emit zero-coverage envelope (not error). Mitigation: explicit empty-array short-circuit in Step 8 implementation.
* `bats-runs.jsonl` schema evolution (BTS-277): adding `failures` field to the appended record is additive, so older readers tolerate it (extra-field rule). New readers expecting the field on older entries get `null` and must handle. Mitigation: Step 6 documents the additive shape; no migration needed.
* **Live-API gate:** none — spec is shell-only, no external API contracts.

## Definition of Done

- [ ] AC-1 through AC-13 all pass per spec
- [ ] `module-manifest.sh validate` exits 0 with drift 0
- [ ] Full suite (`bats-report.sh --parallel`) green at /pr step
- [ ] No new shellcheck warnings in modified scripts
- [ ] Code reviewed (run `/review` before `/pr`)
- [ ] `bts-runs.jsonl` last entry has `failures` array (smoke check)
