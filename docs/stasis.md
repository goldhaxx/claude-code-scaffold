# Stasis

> Feature: bts-507-bats-report-stub-helper
> Work: linear:BTS-507
> Kind: feature
> Last updated: 1778980487
> Session: 58
> Boundary: 2026-05-16T15:05:03-07:00
> Plan hash: c95f8240
> Session objective: Ship BTS-507 — codify the BTS-281 pre-warm bypass into a shared bats helper + mechanical drift-guard. Eliminate the silent ~7-min toll across all `.bats` files that invoke `bats-report.sh` in a subshell.

## Accomplished

* `hub/tests/_helpers/bats-report-stub.bash` (AC-1): single-function helper writes the canonical zero-coverage manifest envelope to `$BATS_FILE_TMPDIR` and exports `BTS_MANIFEST_VALIDATE_CACHE`. Idempotent via overwrite (AC-2).
* `hub/tests/bats-report-stub-drift-guard.bats` (AC-4/5/6): scans `hub/tests/*.bats` (one level, non-recursive) for non-comment-line mentions of `bats-report.sh`; flags any without `load _helpers/bats-report-stub` OR `# bats-report-stub: exempt` marker. 5 @tests cover compliant / exempt / non-compliant / non-recursive / production-scan.
* 10 caller files refactored to use the helper (AC-3): 6 inline-bypass files (collapsed ad-hoc `BTS_MANIFEST_VALIDATE_CACHE=…` blocks) + 4 silent toll-payers (newly bypassed: `bats-report.bats`, `bats-report-jsonl-write-failure`, `bats-report-metrics-envelope`, `bats-report-perf-core-default`).
* 2 false-positive files (`rule-vocabulary-leak.bats`, `test-suite-run.bats`) carry the exempt marker — they mention `bats-report.sh` only as string-literal data, not invocation.
* Race-fix in `bats-report-metrics-envelope.bats` (5.1): the Step 5 refactor sped up 2 inner `--parallel` invocations ~7 min each, exposing a pre-existing OTel Collector flush race in the BTS-497 flatten step. Added `--no-telemetry` to the 2 affected inner invocations — envelope assertions unchanged, flatten skipped.
* Spec scope-up mid-implementation: original spec listed 6 in-scope files; production scan revealed 11. AC-4 detection regex broadened from `bash[^\n]*bats-report\.sh` (direct-only) to non-comment-line containing `bats-report.sh` (catches variable-indirect + dispatcher-forwarded). Spec + Linear Document re-dispatched in Step 4.
* /review pass: 0 BLOCKING, 2 WARN (helper EXIT-trap contract dependency, drift-guard dispatcher-forwarded coverage gap), 2 INFO. Both WARNs addressed with documentation-only header comments (commit `c806a2c`).
* 1 follow-up idea captured: **BTS-509** — `Determinism: exercise-AC-mandated-regexes-against-codebase-pre-impl` (the critic-mode pass should validate AC-mandated regexes against the codebase before locking; the AC-4 regex shortfall went undetected until Step 4).

## Current State

* **Branch:** `claude/feat/bts-507-bats-report-stub-helper`
* **Tests:** 2,432 / 2,432 PASS at commit `b52d20b` (parallel-12, wall 342.7s). 2 doc-only commits since (`c806a2c`, this stasis pending) — no runtime path changed.
* **Uncommitted changes:** plan + this stasis (pending commit).
* **Build status:** clean. Manifest 198/198 covered, drift 0 (verified at /review Step 0).

## Blocked On

Nothing.

## Next Steps

1. Commit plan hash update + this stasis.
2. Re-run lifecycle-state to confirm `pr-ready` (or equivalent legal-next).
3. /pr cleanup + push + mark draft PR ready (#189).
4. /ship 189.

## Context Notes

* **Spec scope-up was the right call.** Original AC-4 regex `bash[^\n]*bats-report\.sh` matched only direct invocation. The mid-implementation grep revealed 4 silent toll-payers using `$REPORT`/`$SCRIPT` variable indirection (matching the spec's spirit but not its letter). Scope-up + re-dispatch took ~30 min vs ~5 min of pre-impl regex validation against the codebase — captured as BTS-509 for the substrate to prevent recurrence.
* **The 5.1 race-fix is the right call vs substrate retry.** `--no-telemetry` is exactly the flag BTS-497 Step 14 designed for. The 2 affected tests verify `.jobs` and `.parallel` envelope fields — flatten skipping doesn't change what's tested. Substrate-side flatten retry is a heavier change for a problem that only manifests inside flatten-irrelevant tests.
* **Perf-core isolation behavior was already broken.** The 4 `--parallel` tests in `bats-report-perf-core-default.bats` use a shim bats that emits no spans; in isolation, inner flatten always fails. AC-7 only requires full-suite green; isolation is out of contract. Refactor didn't introduce the fragility, just removed the coincidental timing window that masked it.
* **WARN-1 (helper EXIT-trap deletion).** bats-report.sh's EXIT trap deletes the stub cache file on every subshell exit; the env var persists in the parent. Overwrite-on-call (rewrite the file every helper invocation) keeps multi-invocation tests safe. If bats-report.sh ever extends to READ the cache content, this helper's design needs to track that. Documented in the helper header.
* **WARN-2 (drift-guard dispatcher gap).** `docs-check.sh test-suite-run` forwarding to `bats-report.sh` doesn't surface as a literal in the calling file; the drift-guard misses such cases. `docs-check-test-suite-run-healthcheck.bats` was correctly classified by hand. Documented in the drift-guard header.

## Determinism Review

* **operations_reviewed:** ~30 (across the spec/plan/impl/review/stasis flow)
* **candidates_found:** 1

* **exercise-AC-mandated-regexes-against-codebase-pre-impl**: Claude wrote AC-4 specifying detection regex `bash[^\n]*bats-report\.sh` and ran two critic-mode passes that returned PASS. The critic looked for semantic ambiguity, not regex coverage. The under-specified regex was discovered at Step 4 (production scan flagged 2 files instead of expected 6), forcing a mid-implementation spec scope-up + Linear re-dispatch (~30 min). Should be: /spec --review critic agent runs the AC-mandated regex against the current codebase + reports match count + 3 example matches; OR a `.claude/rules/tdd.md` addition that requires the spec author to enumerate the expected match set OR provide a one-line grep recipe when an AC contains a regex. Impact: medium — regex-bearing ACs are uncommon, but each occurrence has asymmetric cost (5-min validation vs ~30-min scope-up). Captured as BTS-509.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

198 / 198 (allowlist), drift incidents: 0

## Cross-Session Patterns

* The substrate-driven scope-up pattern from BTS-497 session 57 recurred here: in-flight discovery reveals the spec under-counted the universe of affected files, and the right move is to update the spec + Linear Document + continue, not to ship narrow-and-defer-the-rest. Captured during BTS-497 as a feedback memory (scope-up-on-reveal); BTS-507 validates the rule.
* `feedback_test_discipline_state_intent_logic.md` (captured BTS-497) successfully governed test-run cadence this session: 1 full-suite at Step 6 (RED-then-fix-then-GREEN), 1 re-run after the race-fix, no reflexive intermediate full-suites. Targeted single-file bats runs at Steps 1/2/3 only. The discipline saved ~25-30 min vs the prior session's pattern.

## Security Review

PASS for this branch. /review's security-audit surfaced 17 findings (1 CRITICAL, 6 HIGH, 10 MEDIUM) — all in files this branch does not touch (stasis archives, `hub/meta/operations.md`, prior specs). Pre-existing, not introduced.

## Memory Candidates

* Already-captured: scope-up-on-reveal (BTS-497 memory; validated here).
* Already-captured: test-discipline state/intent/logic (BTS-497 memory; governed this session's test cadence successfully).
* New: BTS-509 idea body covers the regex-pre-impl-validation pattern — that's the substrate response, not a memory candidate. No new memories from this session.
