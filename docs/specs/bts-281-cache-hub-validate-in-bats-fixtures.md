# Feature: Cache hub-wide module-manifest validate in bats fixtures

> Feature: bts-281-cache-hub-validate-in-bats-fixtures
> Work: linear:BTS-281
> Created: 1777779636
> Subject: Cache hub-wide module-manifest validate in bats fixtures
> Status: In Progress

## Summary

Five bats files run `module-manifest.sh validate` against the full hub allowlist (189 entries). On M4 Max, a single hub-validate call is **~7 min wall / ~10 min CPU**. Profiler evidence (BTS-282 on full hub suite, 2026-05-02): `module-manifest.sh validate` accounts for **94% of all measured substrate CPU** (2,495,807 ms). Add `setup_file()` to each of the 5 affected bats files to run validate ONCE per file and stash the JSON envelope under `$BATS_FILE_TMPDIR`; the per-test `setup()` reads the stashed result instead of re-invoking validate. Test correctness is unchanged — the validate output is deterministic on a stable working tree, and none of the 5 tests mutate the hub substrate during the file's lifetime.

## Job To Be Done

**When** the bats suite runs against the full hub at j=12,
**I want to** spend the cost of `module-manifest.sh validate` exactly once per bats file (not per test),
**So that** total suite CPU drops by ~50% and wall-time drops measurably (target ≥20%), surfacing in the BTS-277 `bats-runs.jsonl` soak-tracking signal.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** **Given** any of the 5 affected bats files (`module-manifest-self-application.bats`, `module-manifest-seed-pending-replay.bats`, `module-manifest-seed-ship-finalize.bats`, `module-manifest-seed-artifact-write.bats`, plus the file the BTS-282 profiler newly identifies — confirmed via re-run against current main), **when** the file runs through `bats <file>`, **then** `module-manifest.sh validate` is invoked at most once during the entire bats-file lifetime (verified by running the file under `bats-profile.sh` and asserting the resulting JSON aggregation has at most 1 entry where `cmd == "module-manifest.sh"` and `verb == "validate"`).

- [ ] **AC-2:** When each affected bats file runs, every `@test` block that previously invoked `bash $SCRIPT validate --json` instead reads the stashed JSON envelope from `$BATS_FILE_TMPDIR/manifest-validate.json` (or equivalent path) and applies the same `jq -e` assertions. The functional intent of every existing test is preserved (asserts unchanged or trivially adapted to read-from-file). Verified by running each file's existing test names and asserting the same pass/fail outcomes pre- and post-refactor.

- [ ] **AC-3:** When the FULL bats suite runs (`bats-report.sh --parallel hub/tests/`), the `wall_ms` field appended to `.ccanvil/state/bats-runs.jsonl` (BTS-277) is at least 20% lower than the pre-refactor baseline of 638s (from the 2026-05-02 BTS-277 sweep at `--jobs 12`). Verified by capturing wall_ms before and after, recording both in the PR body. Acceptable failure: wall reduction below 20% is acceptable IF total CPU (user+sys) reduction is ≥40%, since CPU dominance is the operator's stated concern; document the actual numbers in the PR.

- [ ] **AC-4:** All 1992 currently-passing tests still pass after the refactor (verified by `bash .ccanvil/scripts/bats-report.sh --parallel hub/tests/` exiting 0 with `PASS: 1992 / FAIL: 0 / TOTAL: 1992`).

- [ ] **AC-5 (regression / drift-guard intent preserved):** **Given** the `module-manifest-drift-guard.bats` file (which intentionally MUTATES fixture-staged manifests to force drift, NOT the hub allowlist), **when** the refactor lands, **then** that file is NOT changed (it doesn't run hub-validate; it stages tiny PROJ fixtures). Verified by `git diff hub/tests/module-manifest-drift-guard.bats` returning empty diff. This protects the drift-guard's mutation-test discipline.

- [ ] **AC-6:** Manifest validate against the hub still passes (`bash .ccanvil/scripts/module-manifest.sh validate` exits 0, drift count 0). The refactor only touches bats files; no substrate primitives change, so manifest declarations remain unchanged.

## Affected Files

| File | Change |
|------|--------|
| `hub/tests/module-manifest-self-application.bats` | Modified — add setup_file() that runs validate once; rewrite the validate-using @test to read stashed JSON |
| `hub/tests/module-manifest-seed-pending-replay.bats` | Modified — same pattern |
| `hub/tests/module-manifest-seed-ship-finalize.bats` | Modified — same pattern |
| `hub/tests/module-manifest-seed-artifact-write.bats` | Modified — same pattern; covers two @test blocks |
| `hub/tests/_helpers/manifest-validate-cache.bash` | New — shared setup_file() helper sourced by the 5 files; centralizes the stash logic and avoids per-file duplication |

## Dependencies

- **Requires:** BTS-282 ships first (the profiler that proved validate is the bottleneck — already merged in PR #157).
- **Blocked by:** nothing.

## Out of Scope

- **Caching `ccanvil-sync.sh init` (~52s total across 163 calls).** Second-largest hotspot per the profile, but each call is only ~320ms — different optimization shape (likely needs in-script memoization, not bats fixture sharing). Capture as a follow-up if friction surfaces.
- **Caching `docs-check.sh activate` (~15s across 50 calls).** Mid-tier hotspot; same reasoning as above.
- **Generalizing the cache helper into a project-wide library.** This ticket ships a single-purpose helper for 5 files. If we end up with 15+ helper-using bats files later, refactor then.
- **Per-test correctness changes.** Tests adapted to read-from-stash must preserve their existing assertions verbatim except for the input source.

## Implementation Notes

- **Stash shape.** Helper writes the JSON envelope to `$BATS_FILE_TMPDIR/manifest-validate.json` once per file. Per-test `setup()` ensures the stash exists (it should, after `setup_file()`) and exposes `MANIFEST_VALIDATE_JSON=$BATS_FILE_TMPDIR/manifest-validate.json` to the test body.
- **Setup_file mechanics.** bats 1.5+ supports `setup_file()` natively (we already require minimum 1.5.0 in many files). Helper looks roughly:
  ```bash
  # hub/tests/_helpers/manifest-validate-cache.bash
  manifest_validate_cache_setup_file() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"
    bash .ccanvil/scripts/module-manifest.sh validate --json > "$BATS_FILE_TMPDIR/manifest-validate.json"
  }
  ```
  Per-file: `load _helpers/manifest-validate-cache; setup_file() { manifest_validate_cache_setup_file; }`
- **Per-test conversion.** Replace `run bash "$SCRIPT" validate --json; echo "$output" | jq -e ...` with `run cat "$BATS_FILE_TMPDIR/manifest-validate.json"; echo "$output" | jq -e ...`. The assertion shape is unchanged.
- **Live-API gate (TDD rule):** AC-3's wall-time delta is the load-bearing live verification — measure before (current state) and after (post-refactor) on the same M4 Max, document both numbers in the PR body. Stubs accept any shape; only a real run on the real hub proves the saving.
- **Risk: setup_file vs setup ordering.** bats invokes `setup_file()` once before the file's first test, after `BATS_FILE_TMPDIR` is established. If a per-test `setup()` cd's to a `$proj` tempdir (drift-guard pattern), the stash path remains absolute and unaffected — verify this for each affected file.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
