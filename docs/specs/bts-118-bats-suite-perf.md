# Feature: Bats suite perf audit — stop triple-invocation + parallelize

> Feature: bts-118-bats-suite-perf
> Work: linear:BTS-118
> Created: 1777054322
> Status: Complete

## Summary

`/pr` currently runs `bats hub/tests/` three times in sequence (one for the tail output, one for `ok` count, one for `not ok` count), taking ~9 min when the suite itself takes ~3 min. `/recall`, `/stasis`, and `/review` do the same. Short-term fix: capture bats output once, derive all three pieces from the capture. Long-term fix: audit the 883-test suite for parallelism + fixture reuse opportunities, apply `bats --jobs N`, shared setup via `bats_load_library`, and fixture caching for repeated git-init cycles.

## Job To Be Done

**When** I run `/pr` (or any skill that reports test counts),
**I want to** have the bats suite execute once per invocation and finish in under half the current wall time,
**So that** `/pr` is fast enough to run routinely and doesn't tax session budgets.

## Acceptance Criteria

- [ ] **AC-1:** `/pr`, `/recall`, `/stasis`, `/review` each run `bats hub/tests/` at most once per invocation. Verified by inspecting skill prose (no multi-invocation pipelines like `bats ... && bats ...`) and by instrumenting a single dry-run.
- [ ] **AC-2:** The skill patterns capture bats output once (to a tempfile or variable) and derive tail + `ok` count + `not ok` count from the capture.
- [ ] **AC-3:** `bats --jobs N` (or equivalent parallelism mechanism) is applied. N defaults to a sensible concurrency (e.g., `--jobs 4` or `$(sysctl -n hw.logicalcpu)`). Verified by timing `bats hub/tests/` before and after and confirming measurable wall-time improvement.
- [ ] **AC-4:** The suite remains green under parallelism — no test-isolation regressions. Verified by running 3 consecutive parallel runs and confirming all pass with identical test counts.
- [ ] **AC-5:** Wall-time baseline (pre-optimization) and post-optimization numbers are captured in the PR body or spec addendum. Target: ≥50% wall-time reduction for the full suite.
- [ ] **AC-6:** Shared setup reduction: at least one fixture that repeats across tests (git-init + bare-remote setup pattern in multiple files) is consolidated into a helper or `bats_load_library` loaded file.
- [ ] **AC-7:** Error: if a single test leaks state (e.g., stray file in `$TMPDIR`, process handle, env var), it does not fail other parallel tests. Verified by running the suite with `--jobs 4` and ensuring each test's `$BATS_TEST_TMPDIR` is honored.

## Affected Files

| File | Change |
|------|--------|
| `.claude/commands/pr.md` | Modified (single-invocation bats capture) |
| `.claude/skills/recall/SKILL.md` | Modified (single-invocation bats capture) |
| `.claude/skills/stasis/SKILL.md` | Modified (single-invocation bats capture) |
| `.claude/skills/review/SKILL.md` | Modified (single-invocation bats capture) |
| `hub/tests/*.bats` | Modified (fixture sharing, if applicable) |
| `hub/tests/helpers/*.bash` (new) | New (shared setup library, if needed) |
| `.ccanvil/guide/command-reference.md` | Modified (document `--jobs` convention if surfaced) |

## Dependencies

- **Requires:** bats-core 1.5.0+ with `--jobs` support (already pinned).
- **Blocked by:** BTS-127 (strict-mode). Parallelization on already-strict tests avoids churn. However, if BTS-127 ships in a sibling branch, BTS-118 can rebase off main once that's merged.

## Out of Scope

- Moving to a different test framework.
- Opt-out tags / `TEST_TAGS` for slow tests. Considered but rejected unless specific tests demonstrably can't parallelize — prefer fixing isolation issues over tagging around them.
- Distributed test execution across machines. Local parallelism only.

## Implementation Notes

- **Part A (short-term, skill prose):** the current `/pr` command line is:
  ```bash
  bats hub/tests/ 2>&1 | tail -3 && echo --- && bats hub/tests/ 2>&1 | grep -cE "^ok " && bats hub/tests/ 2>&1 | grep -cE "^not ok "
  ```
  Replace with:
  ```bash
  BATS_OUT=$(bats hub/tests/ 2>&1)
  echo "$BATS_OUT" | tail -3
  echo "---"
  echo "$BATS_OUT" | grep -cE "^ok "
  echo "$BATS_OUT" | grep -cE "^not ok "
  ```
  Or capture to tempfile for cross-tool sharing. Zero behavior change; 3× speedup floor before any parallelism.
- **Part B (long-term, parallelism):** bats-core's `--jobs N` uses GNU parallel under the hood. Each test gets its own `$BATS_TEST_TMPDIR`, so test isolation is already supported — failures under parallelism indicate real isolation bugs, not bats limitations.
- **Fixture sharing:** multiple test files do `git init -q -b main; git commit -q --allow-empty -m init; git init --bare -q; git remote add origin`. Extract into `hub/tests/helpers/seed-repo.bash` and `load helpers/seed-repo` in each file. Saves per-test I/O on hot paths.
- **Risk: test-isolation bugs.** Parallelism may expose tests that write to hardcoded paths, reuse PIDs, or share env vars. Mitigation: run `bats --jobs 4` a few times; any flakiness is a test-isolation bug to fix in this ticket.
- **Metric discipline:** measure wall time (`time bats hub/tests/`) before and after. Report both in PR body. The 50% target is a floor — real outcomes may vary based on test composition.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
