# Feature: Test execution velocity — bats observability + agent invocation discipline

> Feature: bts-383-test-execution-velocity
> Work: linear:BTS-383
> Created: 1778291503
> Subject: Test execution velocity — bats observability + agent invocation
> Status: In Progress

## Summary

Test execution is currently the highest single source of operator-idle time outside of operator availability. A single feature session burned \~1-2 hours waiting on bats theater: 8+ full-suite invocations (some in parallel), 10+ manifest validates stacked, premature wait-loops firing, and a 40-minute zombie `until [[ -s ... ]]` shell still alive when surfaced. Substrate buffers output (looks hung), agent re-spawns thinking it's hung, oversubscription cascades. This spec ships substrate observability fixes AND behavioral discipline rules so this never recurs.

The behavioral half (full-suite-only-at-/pr + wait-loop discipline) ships immediately as `.claude/rules/` additions in the BTS-316 PR. The substrate half ships in this dedicated session: bats progress streaming, per-test failure preservation, manifest incremental mode.

## Job To Be Done

**When** I'm iterating on a feature with the agent and need confidence that recent edits didn't regress,
**I want to** get fast (sub-30s) targeted feedback on the surfaces I touched, with full-suite reserved for /pr,
**So that** test execution is a measurement step, not a debugging exercise that costs operator attention.

**When** a long-running test or validate is buffering output,
**I want to** see streaming progress signals so I can distinguish "working" from "hung",
**So that** the agent doesn't assume hang and re-spawn duplicate invocations.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Substrate: bats observability

- [ ] **AC-1:** `bats-report.sh --parallel --progress` emits one line per test file as it completes (e.g. `[12/140] hub/tests/foo.bats: PASS 8/8 in 0.3s`). Heartbeat at minimum every 30s when no file completes (so 0-byte output is impossible).
- [ ] **AC-2:** `bats-report.sh --json` output preserves per-test failure detail when `not_ok > 0`. Each failure entry carries `{test_name, file, line_number, error_excerpt}` (last 3 lines of bats output for that test). Empty array when all pass.
- [ ] **AC-3:** `bats-runs.jsonl` history records the same per-failure detail (BTS-277 envelope extension). `tail -1 .ccanvil/state/bats-runs.jsonl | jq '.failures'` returns the array.

### Substrate: manifest incremental

- [ ] **AC-4:** New `module-manifest.sh validate --changed-only [--since <ref>]` flag scans only files in `git diff --name-only <ref>` (default ref = `HEAD~1`). Returns same JSON envelope shape as the full validate. Runs in <5s on a 1-3 file diff.
- [ ] **AC-5:** `--changed-only` mode emits `{coverage, drift, scanned_files: [...]}` so callers can verify the right files were checked. Drift detection only reports for files in scanned_files set.

### Behavioral: rules

- [ ] **AC-6:** `.claude/rules/tdd.md` adds a "Test execution discipline" section forbidding full-suite bats during iteration. Reserved for /pr step. Anchors back to BTS-383. **(LANDED in BTS-316 PR — verify present before BTS-383 closes.)**
- [ ] **AC-7:** `.claude/rules/background-task-discipline.md` exists and documents: (a) the wait-loop anti-pattern with `until <ps-grep>; do sleep N; done`; (b) the parallel-runs-of-same-command anti-pattern; (c) buffered-output-vs-hang distinction; (d) anti-pattern catalog table. Anchors back to BTS-383. **(LANDED in BTS-316 PR — verify present before BTS-383 closes.)**

### Tests + manifests

- [ ] **AC-8:** New bats fixture `hub/tests/bats-report-progress.bats` covers: `--progress` emits one-line-per-file output; heartbeat fires at 30s+ idle interval; no behavioral change to non-`--progress` runs.
- [ ] **AC-9:** New bats fixture `hub/tests/bats-report-failures-preserved.bats` covers: `--json` output's `failures` array shape on a forced-fail fixture; empty array when all pass; `bats-runs.jsonl` carries the same.
- [ ] **AC-10:** New bats fixture `hub/tests/module-manifest-changed-only.bats` covers: `--changed-only --since HEAD~1` runs in <5s; drift detection limited to changed files; `scanned_files` JSON field accurate.
- [ ] **AC-11:** All new `cmd_*` and helper functions carry `@manifest` blocks. Manifest validate exits 0 with drift 0.
- [ ] **AC-12:** Full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel`. Test count grows by N (the count from AC-8 + AC-9 + AC-10).

### Velocity verification

- [ ] **AC-13:** A subsequent feature session demonstrates: ≤1 full-suite invocation (at /pr only), no zombie wait-loops at session-end (`/stasis` security review verifies), peak background task count ≤3 simultaneous bats/manifest jobs.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/bats-report.sh` | Add `--progress` flag (streaming output); preserve per-test failure detail in `--json` output and `bats-runs.jsonl` |
| `.ccanvil/scripts/module-manifest.sh` | Add `--changed-only [--since <ref>]` flag |
| `.claude/rules/tdd.md` | LANDED in BTS-316 PR — verify only |
| `.claude/rules/background-task-discipline.md` | LANDED in BTS-316 PR — verify only |
| `hub/tests/bats-report-progress.bats` | New |
| `hub/tests/bats-report-failures-preserved.bats` | New |
| `hub/tests/module-manifest-changed-only.bats` | New |

## Dependencies

* **Requires:** BTS-118 (`bats-report.sh` substrate baseline), BTS-277 (`bats-runs.jsonl` envelope), BTS-137 (per-test timing format precedent for output format).
* **Blocked by:** BTS-316 PR (the rules half ships there; full BTS-383 close blocks until BTS-316 merges).

## Out of Scope

* Reducing test count or migrating off bats. Orthogonal concern.
* Harness-level limits on max concurrent background tasks. Harness changes are outside ccanvil substrate scope.
* Per-test parallelization beyond bats's existing `--jobs N`. Substrate-level optimization (BTS-294, BTS-295) handles that.
* Removing the buffering at the kernel level (would require shell-level configuration). The fix is at the application layer (emit progress lines explicitly).

## Implementation Notes

* `--progress` implementation: wrap bats invocation with a tee + line-buffered stream. Use `awk` or `python -u` to detect file boundaries from bats's TAP output. Heartbeat via background `while sleep 30; do ...; done` loop killed at end.
* **Per-failure detail preservation:** parse the bats TAP output for `not ok N <name>` lines, accumulate the next 3-5 indented `#` comment lines as the error_excerpt, emit as `{test_name, file (from current scope), line_number (from `# (in test file ... line N)` comment), error_excerpt}`.
* `--changed-only` implementation: `git diff --name-only $SINCE_REF...HEAD` produces the file list. Filter manifest-allowlist intersection. Run extract+validate only on intersected files. The `_extract_manifests` helper is already file-keyed; just feed it the subset list.
* **Test stub for** `--progress`: create a minimal 2-file fake bats tree with one slow (sleep) test; assert `--progress` output contains `[1/2]` and `[2/2]` lines emitted at file-boundary moments.

## Related

* BTS-316 (origin session — the actual cost incurred; rules half landed there)
* BTS-382 (changelog filter — sibling discipline issue from same session)
* BTS-118 ([bats-report.sh](<http://bats-report.sh>) BTS predecessor)
* BTS-277 (`bats-runs.jsonl` envelope extension)
* BTS-281, BTS-282, BTS-294, BTS-295 (adjacent perf surfaces)
