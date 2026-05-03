# Implementation Plan: Bats observability + perf-core default

> Feature: bts-277-bats-observability-and-perf-core-default
> Work: linear:BTS-277
> Created: 1777757296
> Spec hash: c9b9e29c
> Based on: docs/spec.md

## Objective

Extend `.ccanvil/scripts/bats-report.sh` with perf-core-aware `--jobs` defaulting, a `wall_ms`/`jobs`/`cpus` JSON envelope, and append-only run logging to `.ccanvil/state/bats-runs.jsonl` — without changing existing behavior for human mode or breaking the 1965-test suite.

## Sequence

Each step is one TDD cycle (red → green → refactor → commit). Tests use the existing `seed_bats` fixture pattern from `hub/tests/bats-report.bats` (TESTZ→@test substitution, temp `$WORK` dir).

### Step 1: AC-1 — perf-core jobs detection

* **Test:** New file `hub/tests/bats-report-perf-core-default.bats`. Stub `sysctl` via a PATH-prefixed shim in the test fixture (writes a fake `sysctl` script to `$WORK/bin/` that emits `12` for `hw.perflevel0.physicalcpu`, falls through for `hw.logicalcpu`). Assert the wrapper picks `--jobs 12`. Cover three cases: (a) sysctl returns positive perf cores → use that; (b) sysctl empty → fallback to `cpus/2`; (c) sysctl returns 0 or 1 → fallback (clamped min 2). Use the existing `BATS_REPORT_HAS_PARALLEL=1` testability hook so tests don't depend on real `parallel`.
* **Implement:** Add helper above the existing parallel branch:

  ```bash
  perf="${BATS_REPORT_PERF_CORES:-}"
  [[ -z "$perf" ]] && perf=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "")
  if [[ "$perf" =~ ^[0-9]+$ ]] && (( perf >= 2 )); then
    jobs="$perf"
  else
    jobs=$((cpus / 2))
    (( jobs < 2 )) && jobs=2
  fi
  ```
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-perf-core-default.bats` (new).
* **Verify:** New bats file passes. Live-API gate: run `BATS_REPORT_HAS_PARALLEL=1 bash -x .ccanvil/scripts/bats-report.sh --parallel /dev/null 2>&1 | grep -- '--jobs'` on this M4 Max host; assert it shows `--jobs 12` before commit.

### Step 2: AC-2 — wall_ms / jobs / cpus envelope fields

* **Test:** New file `hub/tests/bats-report-metrics-envelope.bats`. Run `--json --parallel` against a 2-test seeded bats; `jq -e` assert (a) `wall_ms` is integer and `>= 0`, (b) `jobs == 12` (with `BATS_REPORT_PERF_CORES=12` set for determinism), (c) `cpus` is integer `>= 1`, (d) all existing fields still present + same shape.
* **Implement:** Capture wall-time via portable shape — `start_ms=$(perl -MTime::HiRes -e 'printf "%d", Time::HiRes::time()*1000')`, repeat after the bats invocation. Add `--argjson wall_ms`, `--argjson jobs_used`, `--argjson cpus_total` to the existing jq compose. Default `jobs_used=1` when `--parallel` not requested.
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-metrics-envelope.bats` (new).
* **Verify:** Bats passes. Manual run: `bash .ccanvil/scripts/bats-report.sh --parallel --json hub/tests/bats-report.bats | jq '{wall_ms, jobs, cpus}'` shows non-null integers.

### Step 3: AC-3 — append run to `.ccanvil/state/bats-runs.jsonl`

* **Test:** Same file as Step 2 (`bats-report-metrics-envelope.bats`). Set `BATS_REPORT_STATE_DIR="$WORK"` (new env override). Capture `wc -l < "$WORK/bats-runs.jsonl"` before two consecutive runs; assert delta == 2 after; assert last 2 entries parse as JSON with all required keys; assert epochs are monotonically non-decreasing.
* **Implement:** Add at end of script (after envelope emit, before exit): resolve state dir = `${BATS_REPORT_STATE_DIR:-.ccanvil/state}`; `mkdir -p` it; compose entry via `jq -c -n --argjson ...`; append with `>> "$state_dir/bats-runs.jsonl"`. Boolean `parallel` derived from the `parallel_mode` flag.
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-metrics-envelope.bats` (extend).
* **Verify:** Bats passes. After this step, also live-run `bash .ccanvil/scripts/bats-report.sh --parallel hub/tests/bats-report.bats` and confirm `.ccanvil/state/bats-runs.jsonl` exists in the repo (expected — gitignored in Step 6).

### Step 4: AC-5 — unwritable state-dir graceful WARN

* **Test:** New file `hub/tests/bats-report-jsonl-write-failure.bats`. Create `$WORK/state/`, `chmod -w "$WORK/state"`, run wrapper with `BATS_REPORT_STATE_DIR=$WORK/state`. Assert: stderr contains `WARN: bats-runs.jsonl append skipped`, exit code mirrors bats (0 on the seeded passing fixture), stdout still emits the human/JSON envelope normally.
* **Implement:** Wrap the append in a guarded shape — try `mkdir -p` + write, on failure emit the WARN to stderr without flipping `bats_exit`. Treat any non-zero from the append pipeline as the warn trigger (covers ENOSPC, EROFS, EACCES uniformly).
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report-jsonl-write-failure.bats` (new).
* **Verify:** Bats passes. Skip teardown chmod restoration (BATS_TEST_TMPDIR is auto-cleaned).

### Step 5: AC-4 — `--help` documents the new shape

* **Test:** Modify `hub/tests/bats-report.bats`. Run `bash "$REPORT" --help`; assert (a) output contains string `perf-core` (or `hw.perflevel0`), (b) `wall_ms`, (c) `bats-runs.jsonl`. Use `grep -qF` for each anchor.
* **Implement:** Update the leading comment block in `bats-report.sh` (the `usage()` reads lines 2-28 currently — extend the doc lines, then bump the `sed -n` range if needed). Mention default-jobs derivation, JSON envelope additions, and jsonl append behavior.
* **Files:** `.ccanvil/scripts/bats-report.sh`, `hub/tests/bats-report.bats` (extended).
* **Verify:** Bats passes.

### Step 6: AC-6 — manifest declarations + drift-guard + .gitignore

* **Test:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json` and assert `status == "ok"`, `coverage.covered == coverage.total`, `(.drift | length) == 0`. (Drift-guard already exists as `hub/tests/module-manifest-self-application.bats` — ensure it stays green.)
* **Implement:** Update the `# @manifest` block in `bats-report.sh`:
  * New `side-effect: writes-bats-runs-jsonl` line.
  * New `failure-mode: jsonl-append-failed | exit=passthrough | visible=stderr-warn | mitigation=ensure-state-dir-writable` line.
  * New `input: env BATS_REPORT_PERF_CORES` line.
  * New `input: env BATS_REPORT_STATE_DIR` line.
  * Bump `anchor:` with `BTS-277 (perf-core default + metrics envelope + jsonl append)`.
  * Add `.ccanvil/state/bats-runs.jsonl` to `.gitignore` (line under existing `.ccanvil/` ignores; verify what's already there before editing).
* **Files:** `.ccanvil/scripts/bats-report.sh` (manifest only), `.gitignore`.
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate --json` returns `status:ok` with drift 0. `.ccanvil/state/bats-runs.jsonl` is gitignored (`git check-ignore -v .ccanvil/state/bats-runs.jsonl`).

### Step 7: Full suite + live-validation gate

* **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel hub/tests/` — must show `PASS: <N+9 or so> / FAIL: 0` (existing 1965 + new tests across Steps 1-5).
* **Implement:** No new code. Confirm the live live-API gate from Step 1 ran and showed `jobs=12` before commit.
* **Files:** none.
* **Verify:** Suite green, manifest validate green, branch ready for `/pr`.

## Live-API validation gate (BTS-171)

Step 1 has a contract uncertainty: the wrapper actually invokes `sysctl` at runtime. Stubs accept any shape; the live host must verify `hw.perflevel0.physicalcpu` returns `12` on this M4 Max and that the wrapper picks it up. Required command BEFORE Step 1 commit:

```bash
BATS_REPORT_HAS_PARALLEL=1 bash -x .ccanvil/scripts/bats-report.sh --parallel /dev/null 2>&1 | grep -E -- '--jobs [0-9]+'
```

Expected output: `+ bats_cmd+=(--jobs 12)` (or equivalent with 12). If it shows 8 (the old fallback), the perf-core branch isn't firing — debug before committing.

## Risks

* **Wall-time portability.** macOS `date +%s%N` returns literal `N`. Plan uses `perl -MTime::HiRes` (ships on macOS + Linux). If perl isn't present (rare), fallback to `python3 -c 'import time; print(int(time.time()*1000))'`. Final fallback: integer seconds (`date +%s` × 1000) — accept second-precision rather than failing.
* **JSONL contention under** `--parallel`. Multiple bats-report invocations writing concurrently to the same jsonl could interleave. POSIX append-mode writes are atomic for `<= PIPE_BUF` bytes (\~512 on macOS, 4096 on Linux). One run-summary line is \~250 bytes, well under the limit. Document the constraint in the manifest's `contract:` lines but no extra locking.
* **Manifest drift on missing depends-on.** Adding `perl` (for the wall timer) creates a new `depends-on:` requirement. Drift-guard will flag it if missed. Step 6 must include `depends-on: perl` in the manifest update.
* **Live-API gate forgetting.** Per `feedback_validate_plan_flagged_live_api`, stubs accept anything — only the live host proves the contract. The gate is mandatory before Step 1's commit.

## Definition of Done

- [ ] All 6 ACs from spec pass
- [ ] All existing tests still pass (1965 + new)
- [ ] Manifest validate green (`status:ok`, drift 0)
- [ ] Live-API gate executed for AC-1
- [ ] Code reviewed (`/review`)
- [ ] PR ready for merge
