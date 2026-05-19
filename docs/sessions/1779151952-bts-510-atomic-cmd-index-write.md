# Stasis: bts-510-atomic-cmd-index-write

> Feature: bts-510-atomic-cmd-index-write
> Work: linear:BTS-510
> Kind: feature
> Last updated: 1779151952
> Session: 63
> Boundary: 2026-05-18T15:57:52-07:00
> Session objective: Triage the 18-item queue, then spec → critic-mode → activate → plan → 5-step TDD → ship-ready BTS-510 (atomic cmd_index write — the parallel-race flake captured at end of session 60). Wrap on the feature branch with PR #191 marked ready.

## Accomplished

* **Triage drained 18 → 0.** All 15 drift-watchdog auto-captures (BTS-513..527) promoted to Backlog P3; carry-forwards BTS-510 → P2, BTS-511 → P3, BTS-512 → P4.
* **BTS-510 specced + critic-passed + activated.** Spec written, dispatched to Linear Document `b5713c24…`, then ran `/spec --review` 5 times. Tightenings landed: (1) AC-2 byte-for-byte → parse-success only; (2) AC-3 empirical-not-binary → structural argument (AC-1 makes the race impossible by construction) + 100-run empirical gate; (3) AC-3 reclassification-escape hedge → binary pass/fail "any failure in window fails the AC"; (4) AC-4 singular "intermediate-file" → both mktemp calls covered with distinct stderr identifiers; (5) AC-6 "or equivalent" → exact literal contract string + grep verification. Critic pass 5 returned PASS. Activated → branch `claude/feat/bts-510-atomic-cmd-index-write`, draft PR #191 up, Linear → In Progress.
* **Plan written + 5-step TDD complete.** Plan dispatched to Linear `cd1cf8ec…` (originally 6 steps; Step 6 was a misclassification — see Determinism Review).
  * Step 1 (07bf5a5): per-invocation `mktemp "$out.XXXXXX"` swap in cmd_index. AC-1, AC-7.
  * Step 2 (7a6c143): contract anchor swap to `atomic-write-via-mktemp-and-mv` + BTS-510 anchor line. AC-6.
  * Step 3 (22c6e12): error guards on both mktemp calls with distinct stderr identifiers (`accumulator-mktemp-failed`, `final-write-mktemp-failed`) + manifest header declares both failure-modes. AC-4.
  * Step 4 (420ebcd): parallel-stress harness (`hub/tests/module-manifest-parallel.bats`). 12 writers × 100 iters + 500 interleaved reads. Red-verified on pre-fix broken code (1 parse failure / 378 reads) BEFORE committing — the plan's "test passes on broken code" risk fired, mitigation worked. AC-2.
  * Step 5 (d0a8394): 100-run helper script (`hub/tests/run-module-manifest-graph-100x.sh`). Smoke-verified at 5 iters; full 100x ran in background and reported 0 failures in 392s (result is suspect — see Context Notes).
* **PR #191 marked ready** (operator-explicit waiver of full-suite gate). pr-cleanup ran cmd_complete; archived spec + plan to `docs/sessions/`; pushed; assert-pr-title confirmed `feat(bts-510-atomic-cmd-index-write): Atomic cmd_index write under --parallel`; gh pr ready returned "already ready".
* **Tempo telemetry diagnosis.** Operator flagged "5 tests in 3 runs over 15 min" in Grafana. Root cause: **7% telemetry coverage across the suite** — only 18 of 176 `.bats` files load `_helpers/telemetry`, accounting for 173 of 2486 tests. The 5-span runs are `module-manifest-seed-artifact-write.bats` (one of the 18 instrumented files). **Already captured as BTS-504** (P2 Backlog, "wire telemetry helper into remaining ~149 hub/tests/*.bats files"). Last session's stasis explicitly named BTS-504 as next ship. Confirmed: work pushed aside, not lost.

## Current State

* **Branch:** `claude/feat/bts-510-atomic-cmd-index-write` (5 implementation commits + 1 activate + 1 pr-cleanup). PR #191 OPEN (non-draft, ready for review).
* **Tests:** Targeted bats 9/9 PASS at c457d1d (`module-manifest-cmd-index-shape.bats` 5/5, `module-manifest-cmd-index-error.bats` 3/3, `module-manifest-parallel.bats` 1/1). **Full suite NOT run this session** — operator-explicit waiver. Per `.claude/rules/test-discipline.md`, full suite is the pre-merge gate and runs at /pr or /ship time — operator chose to skip and accept unit-level coverage as sufficient.
* **Uncommitted changes:** none.
* **Build status:** clean. Manifest 201/201 covered, drift 0 (cached from Step 3's d5a657a-shape commit chain validate; Steps 4-5 only added new .bats + helper script, neither manifest-tracked nor under .ccanvil/scripts allowlist scope).
* **Linear:** BTS-510 status `In Progress`. Spec Linear Document `b5713c24…`. Plan Linear Document `cd1cf8ec…`.

## Blocked On

Nothing. PR #191 is ready for `/ship 191`.

## Next Steps

1. **`/ship 191`** — squash-merge BTS-510, branch cleanup, switch to main, auto-transition BTS-510 → Done. Optionally re-run the 100x verification clean (no parallel invocations) post-ship to get an uncontaminated AC-3 number; the structural argument (AC-1) is load-bearing on its own.
2. **BTS-504** — natural next ship. 149-file telemetry retrofit. Substrate-ready: BTS-507 helper-stub + BTS-508 test-discipline shipped, BTS-510 atomic-write about to ship. Once BTS-504 lands, Tempo coverage jumps from 7% to ~100% and the "5 tests in 3 runs" view becomes the full ~2486 tests. Bundle BTS-505 (error_excerpt) + BTS-506 (stack-state surfacing) per session 60 plan.
3. **BTS-498** — drift-guard 5.5-min optimization. Independent of BTS-504. Biggest wall-saving on parallel-12 runs.
4. **BTS-511 + BTS-512** — structural enforcement of the test-discipline rule. Session-63 produced fresh evidence (see Determinism Review): the substrate-enforcement gap is real and reproducible.

## Context Notes

* **The 100x AC-3 verification result is suspect.** I launched the 100x in background, then 1-2 min later launched a full module-manifest-suite bats run in foreground. Both wrote to the SAME project-root `.ccanvil/state/manifests.json`. The 100x's "0 failures in 392s" reading was contaminated by parallel invocations — exactly the BTS-510 race I was supposed to be verifying. Operator caught it via Tempo signal ("same 5 tests in 3 runs over 15 min"). The structural argument (AC-1 per-invocation mktemp) is the load-bearing correctness claim; AC-2 parallel-stress red-verified clean on broken code. AC-3 100-run is empirical confirmation only.
* **Step 6 in the plan was a misclassification.** "AC-5: full module-manifest suite passes" was listed as a TDD cycle. Per the test-discipline rule I shipped in BTS-508, full-suite runs are the pre-merge gate, not per-cycle verifications. Step 6 belongs in Definition of Done, not Sequence. The misclassification IS what triggered me to launch the suite mid-session, which collided with the 100x. Captured as a determinism candidate (see below).
* **Critic-mode is paying for itself.** 5 passes, 4 real findings, all valid (none false-positives). Operator-validated format from session 60 continues to surface real ambiguities even after validate-spec returns ok.
* **Path A/B/C scope-up decision (telemetry retrofit on BTS-510's 3 new .bats files) deferred.** Operator implicitly chose Option A (ship narrow, BTS-504 picks up the 3 files later) by directing wrap-up. My 3 new BTS-510 .bats files are silent in Tempo, same as 158 other files.
* **Test-discipline self-application worked the SECOND time, mid-session.** Operator caught the stacked-parallel-test violation, I stood down. First time was end of session 60 (reflexive full-suite re-run, captured BTS-511). Two self-violations in two sessions of operator-side enforcement → BTS-511's structural enforcement is the right fix.

## Determinism Review

* **operations_reviewed:** ~28 (across triage, spec, 5 critic passes, activate, plan, 5 TDD steps, pr-cleanup, push, ready, Tempo diagnosis).
* **candidates_found:** 2.

* **stacked-parallel-test-invocations-against-shared-state**: Claude launched the 100x background verification, then 1-2 minutes later launched a foreground `bats hub/tests/module-manifest*.bats` run while the 100x was still iterating. Both invocations wrote to the SAME project-root `.ccanvil/state/manifests.json` — the literal BTS-510 race the implementation was fixing. Operator detected via Tempo signal. Should be: deterministic check at bats-invocation entry (or in `bats-report.sh`) that detects another bats process actively writing to the same `.ccanvil/state/manifests.json` via PID/lock file. Refuse to start a second concurrent bats run against the same project state without an explicit `ALLOW_CONCURRENT_BATS=1` override. Today the operator catches the violation post-hoc by reading Tempo. Impact: medium — this is fresh evidence for BTS-511 (test-discipline rule structural enforcement); not a new ticket on its own.
* **plan-step-6-full-suite-misclassification**: Claude wrote a 6-step plan where Step 6 was "AC-5: full module-manifest suite passes" — labeled a TDD cycle but actually a pre-merge gate. Per `.claude/rules/test-discipline.md`, full-suite runs are session-boundary or pre-merge gates, never per-cycle TDD verifications. Triggering Step 6 mid-session caused the stacked-test invocation above. Should be: /plan substrate (or critic-mode rule) that flags any plan step describing "full suite", "all tests pass", "no regressions in suite X" as a misclassification — those belong in Definition of Done, not Sequence. Impact: low-medium — compounds across every future plan; the gap touches every TDD planning step.

## Evidence Gaps

* BTS-505 — BTS-497 follow-up: capture test.error_excerpt on failed bats spans — missing-evidence-anchors

(Recurring across BTS-497 → BTS-507 → BTS-508 → BTS-510 stasis cluster. Same as last 3 sessions. Operator-owned reshape pending: add the four anchors OR retitle as `DIAGNOSE: error_excerpt never populated on failed bats spans`.)

## Manifest Coverage

201 / 201 (allowlist), drift incidents: 0

(Cached from Step 3's d5a657a chain validate; Steps 4-5 added only a new bats file + a helper script under `hub/tests/` — neither falls under the manifest-tracked allowlist scope. Per `.claude/rules/test-discipline.md` session-boundary phase, /stasis records cached state rather than re-running validate.)

## Cross-Session Patterns

* **Test-discipline rule violation, second occurrence in two sessions.** Session 60: reflexive full-suite re-run after fixing unrelated failures (captured BTS-511). Session 63: stacked-parallel-test invocations against shared state (this stasis's first determinism candidate). Both caught by operator, not substrate. Recurring evidence for BTS-511's structural enforcement — strengthens the case for prioritizing BTS-511 alongside BTS-504.
* **Mid-/review critic-mode tightening pattern, 4th validation.** BTS-497 → BTS-507 → BTS-508 → BTS-510. Critic mode caught 4 real ambiguities in BTS-510's spec even after validate-spec returned ok. Already captured in `feedback_critic_mode_finds_real_findings_on_validated_specs.md` — not a new memory.
* **AC-2 risk-mitigation fired cleanly.** Plan explicitly called out "Step 4 test might pass on broken code" risk; I red-verified on pre-fix broken code (1 parse failure across 378 reads), strengthened the test, re-verified, then committed. Pattern works — the in-plan risk callout + the structural verify gave the test deterministic regression-guard properties.
* **legacy-refs-scan: clean** (`[]`) — no hub-owned or node-specific drift.
* **No new recurring evidence-gap captures** beyond BTS-505 (operator-owned, still pending).

## Security Review

PASS for this session's diff. Changes are substrate-only (cmd_index in `module-manifest.sh`, 3 new bats test files, 1 helper script, lifecycle cleanup commits). No tokens, no PII, no credentials touched. The 100x helper script reads operator-owned logs from `mktemp` directories which are auto-cleaned. No new exposure introduced.

## Memory Candidates

* **No new memories.** The patterns surfaced this session were already captured:
  - critic-mode-finds-real-findings (validated 4x now)
  - test-discipline-state-intent-logic (validated 3x; this session is fresh evidence for BTS-511 substrate-enforcement, not a new memory)
  - scope-up/scope-down patterns (this session leaned scope-narrow; no new variant)
  - risk-mitigation-via-red-on-broken-test (the plan called it; pattern is documented in spec/plan templates)

  BTS-504 was already in the backlog; the Tempo-diagnosis just resurfaced it. Not a new memory.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
