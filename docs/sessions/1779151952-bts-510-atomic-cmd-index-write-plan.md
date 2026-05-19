# Implementation Plan: Atomic cmd_index write under --parallel

> Feature: bts-510-atomic-cmd-index-write
> Work: linear:BTS-510
> Created: 1779146600
> Spec hash: 3e187b74
> Based on: docs/spec.md

## Objective

Replace the fixed-filename `$out.tmp` intermediate in `cmd_index` (`.ccanvil/scripts/module-manifest.sh`) with a per-invocation `mktemp "$out.XXXXXX"` so concurrent test workers can no longer clobber each other's partial writes, eliminating the 1/2462 `module-manifest-graph.bats` line-31 flake.

## Sequence

### Step 1: Grep guard + mktemp swap (AC-1, AC-7)

* **Test:** New bats `hub/tests/module-manifest-cmd-index-shape.bats`. Three assertions targeting the `cmd_index` block of `.ccanvil/scripts/module-manifest.sh`:
  * `grep -nF '"$out.tmp"' ` returns 0 matches inside cmd_index (lines 1271-1328 ± shift).
  * `grep -nE 'mktemp "\\$out\\.XXXXXX"'` returns ≥1 match inside cmd_index.
  * `grep -nF 'mkdir -p "$(dirname "$out")"'` returns ≥1 match (AC-7 preservation).
* **Implement:** In `cmd_index`, replace both `> "$out.tmp"` write sites + the `mv "$out.tmp" "$out"` with a per-invocation `out_tmp=$(mktemp "$out.XXXXXX")` + `mv "$out_tmp" "$out"`. Extend the `RETURN` trap to clean up `$out_tmp` too. Preserve the existing `mkdir -p "$(dirname "$out")"`.
* **Files:** `.ccanvil/scripts/module-manifest.sh` (cmd_index, lines 1271-1328); `hub/tests/module-manifest-cmd-index-shape.bats` (new).
* **Verify:** `bats hub/tests/module-manifest-cmd-index-shape.bats` green; `module-manifest.sh validate` clean.

### Step 2: Contract anchor swap (AC-6)

* **Test:** Extend `hub/tests/module-manifest-cmd-index-shape.bats` with two assertions on `cmd_index`'s manifest block:
  * `grep -F '# contract: atomic-write-via-mktemp-and-mv' .ccanvil/scripts/module-manifest.sh` returns exactly 1 match.
  * `grep -F '# contract: atomic-write-via-mv' .ccanvil/scripts/module-manifest.sh` returns 0 matches within cmd_index's block (use awk-based block extraction for boundary).
* **Implement:** Update the `# contract:` line in cmd_index's manifest header (line 1269).
* **Files:** `.ccanvil/scripts/module-manifest.sh` (cmd_index manifest block); `hub/tests/module-manifest-cmd-index-shape.bats`.
* **Verify:** Targeted bats green; `module-manifest.sh validate` clean.

### Step 3: Error-path guards on both mktemp calls (AC-4)

* **Test:** New bats `hub/tests/module-manifest-cmd-index-error.bats`. Two cases using a PATH shim to make `mktemp` fail:
  * Shim that fails on bare `mktemp` (accumulator call) → assert exit non-zero + stderr contains distinct accumulator identifier (e.g., `accumulator-mktemp-failed`).
  * Shim that fails on templated `mktemp "$out.XXXXXX"` call → assert exit non-zero + stderr contains distinct final-write identifier (e.g., `final-write-mktemp-failed`).
* **Implement:** Wrap each `mktemp` call in `cmd_index` with `|| { echo "module-manifest: <identifier>" >&2; return 2; }`. Distinct identifiers per call.
* **Files:** `.ccanvil/scripts/module-manifest.sh` (cmd_index); `hub/tests/module-manifest-cmd-index-error.bats` (new).
* **Verify:** Targeted bats green; existing module-manifest tests still green.

### Step 4: Parallel-stress harness (AC-2)

* **Test:** New bats `hub/tests/module-manifest-parallel.bats`. Single @test:
  * Setup: cd to `BATS_TEST_TMPDIR`; copy a minimal source-dir fixture (1-2 .sh files with manifest blocks).
  * Spawn 12 background `module-manifest.sh index` invocations against the shared `.ccanvil/state/manifests.json`.
  * Loop 100 iterations: `jq -e . < .ccanvil/state/manifests.json` between writes; count parse failures.
  * `wait` for all writers; assert parse-failure count == 0 across 1200 reads.
* **Implement:** No code change (fix is from Step 1). Test relies on the structural property already in place.
* **Files:** `hub/tests/module-manifest-parallel.bats` (new).
* **Verify:** Targeted bats green; run 3× consecutively to confirm non-flaky.

### Step 5: 100-run regression verification (AC-3)

* **Test:** New helper script `hub/tests/run-module-manifest-graph-100x.sh`. Loops 100 iterations of `bats --jobs 12 hub/tests/module-manifest-graph.bats`; greps each run's output for the line-31 test name; counts failures; exits 0 iff 0 failures, non-zero with count summary otherwise.
* **Implement:** No code change. Script is operator-runnable verification of AC-3's empirical gate.
* **Files:** `hub/tests/run-module-manifest-graph-100x.sh` (new); chmod +x.
* **Verify:** `bash hub/tests/run-module-manifest-graph-100x.sh` → 0/100 failures, exit 0. (Wall time \~5-10 min.)

### Step 6: Full module-manifest suite + manifest-validate (AC-5)

* **Test:** `bats hub/tests/module-manifest*.bats` and `bash .ccanvil/scripts/module-manifest.sh validate --json`.
* **Implement:** No code change. Pure verification step.
* **Files:** None.
* **Verify:** All module-manifest bats pass; manifest validate returns `status: ok` with drift 0.

## Risks

* **AC-3 wall-time.** 100 runs × \~5s = \~8 min. Acceptable for a one-shot verification but not for CI. Helper script is operator-runnable; AC-2 (single-suite parallel-stress) is the in-suite proof. If Step 5 wall-time becomes an issue, downscale to 50 iterations with same binary pass bar.
* **mktemp PATH-shim test fragility (Step 3).** Mocking `mktemp` via PATH shim is sensitive to which `mktemp` resolves in the bats subshell. Mitigation: explicitly export `PATH="$BATS_TEST_TMPDIR:$PATH"` in setup() so the shim wins; verify with `which mktemp` inside the @test.
* **RETURN trap evolution.** The existing trap (line 1280) cleans `$tmp` and `$tmp.merged`. Adding `$out_tmp` to the trap target list is mechanical but easy to forget. The Step 1 implement should explicitly include the trap update; AC-1 grep doesn't catch a missing trap — covered by AC-4's error-path tests (failed mktemp must leave no orphan tmps).
* **Bats parallel-stress non-determinism.** Step 4's parallel-stress test might pass on current code (race window narrow), giving a false-negative. Mitigation: confirm Step 4 test reliably fails on a deliberately-broken version (revert mktemp swap, re-run; expect parse failures) before committing the test.

## Definition of Done

- [ ] All 7 acceptance criteria from spec pass (deterministic via grep + targeted bats; empirical via parallel-stress + 100-run script).
- [ ] All existing tests still pass (`bats hub/tests/` + module-manifest validate).
- [ ] Manifest coverage holds: 201/201, drift 0.
- [ ] Code reviewed (run `/review`).
- [ ] AC-3 helper script run once with 0 failures captured in PR body.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
