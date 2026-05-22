# Stasis: session-2026-05-21-bts-558-pytest-dispatcher-ship

> Feature: session-2026-05-21-bts-558-pytest-dispatcher-ship
> Kind: session
> Last updated: 1779429164
> Session: 71
> Boundary: 2026-05-21T22:14:23-07:00
> Session objective: Triage BTS-558 to P1 and ship it (the pytest dispatcher arm for test-suite-run); diagnose the test-run observability gap the operator raised.

## Accomplished

* **BTS-558 SHIPPED — PR #194 merged** (squash `3006e69`; BTS-558 → Done). Adds the `pytest` arm to `cmd_test_suite_run` (`.ccanvil/scripts/docs-check.sh`): reads `test-command` + `test-path` from node config, translates `--parallel` → `-n auto`, normalizes pytest exit 5 (no tests collected) to a loud failure, gates the OTel healthcheck to the bats provider. Unblocks fieldnation-toolbox BTS-552.
* **Full lifecycle ran clean:** `/idea triage` (BTS-558→P1; BTS-557→P2, BTS-549→P3 to backlog) → `/spec` (validate-clean; critic pass caught an AC-3 translate-vs-forward ambiguity — fixed the whole class incl. AC-8) → `/activate` → `/plan` (7 TDD steps) → 7 red-green cycles → `/review` (0 CRITICAL; 2 WARN fixed) → `/pr` → `/ship`.
* **Quality gates:** full suite 2547/2547 pass (wall 379.8s); manifest 203/203 drift 0; security audit 0 findings introduced by the changeset.
* **Observability gap diagnosed + 3 tickets captured.** Operator flagged "no Grafana data for the first \~4 min of a run." Root-caused from the live Tempo trace. Captured: BTS-559 (non-bats OTel test tooling), BTS-560 (test-suite-run end-to-end trace — child of BTS-542), BTS-561 (run the manifest pre-warm concurrent with the suite, \~2 min/run). `project_workflow_observability_umbrella.md` memory updated.

## Current State

* **Branch:** `main` (PR #194 merged + landed; feature branch deleted local + remote)
* **Tests:** full suite 2547 / 2547 pass — the `/pr` pre-merge gate
* **Uncommitted changes:** none
* **Build status:** clean. Manifest 203 / 203, drift 0.
* **Linear:** BTS-558 Done. Triage queue 4 — BTS-533 (carried) + the 3 new captures BTS-559/560/561.
* **Observability stack:** running (brought back up after a host reboot mid-session).

## Blocked On

Nothing.

## Next Steps

1. **Triage the 3 new captures** — BTS-559/560/561 sit in Triage. BTS-560 (child of BTS-542) is the operator's stated priority: full end-to-end test-run visibility. Run `/idea triage`.
2. **BTS-544 (C2)** remains next on the Workflow Observability umbrella's critical path (session-trace correlation).
3. **fieldnation-toolbox BTS-552** is unblocked — node-side `test-provider: pytest` config flip; a handoff update was drafted for that node's agent.
4. **Ticket the recurring** `legacy-refs-scan` **gap** (see Cross-Session Patterns) — flagged 5 sessions running, still not captured.

## Context Notes

* **BTS-558 design — config-driven, no hub script.** Operator chose the config-driven seam: the pytest arm reads `test-command`/`test-path` from `.claude/ccanvil.json`; no `pytest-report.sh` analog. pytest's own ecosystem (xdist, exit codes, progress) covers what `bats-report.sh` hand-rolls.
* **bats** `[[ ]]` **mid-test gotcha (cost \~6 probes to rediscover).** bats 1.13 here only fails a test on `[ ]`, `grep`, and regular-command non-zero exits — a mid-body `[[ ]]` is silently skipped; only the LAST command's status counts. Use `[ ]`/`grep` for assertions; never rely on a non-final bare `[[ ]]`. This is the BTS-127 strict-mode-bats discipline. The new pytest tests use `grep`. Latent weakness across the wider suite (many tests place `[[ ]]` non-last) — noted, not ticketed.
* **End-to-end without interim commits.** Went `/spec`→`/ship` in one pass without committing during TDD. `cmd_complete` (pr-cleanup) committed only the lifecycle docs; the 4 implementation files had to be committed manually before push. Next end-to-end run: commit per TDD step, or expect the manual commit.
* **Host reboot mid-session** killed the first `/pr` suite run and wiped `/private/tmp`. Recovered: restarted the OTel stack, re-ran the suite. Working-tree changes survived intact (uncommitted).
* **Observability root cause (for BTS-560).** [run.id](<http://run.id>) stamped 22:16:00, first test span 22:20:07 — the 4m07s gap is the BTS-281 `module-manifest.sh validate` pre-warm (`bats-report.sh:207-213`), un-instrumented; the suite-root span is emitted only at `bats-report.sh:519` (rootless trace mid-run). Operator principle: a composite automated operation should be ONE end-to-end trace covering all phases.

## Determinism Review

* **operations_reviewed:** \~28 (triage transitions, spec + critic pass, plan, 7 TDD cycles, review + security + manifest, pr suite + cleanup + push, ship, Tempo diagnostic queries, 3 captures, memory update).
* **candidates_found:** 0.

No candidates this session. The work was TDD implementation (judgment), live-trace diagnosis (judgment — not computable), and the already-scripted lifecycle substrate. The observability diagnosis surfaced a substrate gap, but that is captured as BTS-560 — not a determinism candidate.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

203 / 203 (allowlist), drift incidents: 0

## Cross-Session Patterns

* `legacy-refs-scan` **runtime-artifact gap — RECURRING (5th session).** The scan again flags `.ccanvil/observability/raw-traces.jsonl` — a gitignored runtime artifact — `node-specific` scope, false positives on `docs/checkpoint.md` / `/catchup` strings inside captured test-span names. Flagged 4 prior sessions; the prior stasis said it "should finally become a real ticket." Still not ticketed. Fix: `legacy-refs-scan.sh` should exclude gitignored runtime-artifact dirs (`observability/`, `state/`). Hub-owned.
* **audit-session:** 0 findings since `ac0794b`. No recurring stochastic pattern.
* **Determinism:** prior session 0 candidates, this session 0 — no recurring determinism candidate.

## Security Review

PASS. `/review`'s security audit reported 17 findings — all pre-existing in files NOT touched by BTS-558 (`docs/sessions/*`, `hub/meta/operations.md`, `docs/specs/bts-395-*`, `docs/specs/bts-72-*`). Zero introduced by the BTS-558 changeset; `docs-check.sh`, `configuration.md`, and the two bats files carry no secrets, PII, or credentials.

## Memory Candidates

1. **Workflow Observability umbrella — memory UPDATED this session.** `project_workflow_observability_umbrella.md` now records BTS-560 (new child of BTS-542), BTS-561 (related optimization), and the operator principle (composite automated operation = one nested end-to-end trace).
2. **bats** `[[ ]]` **mid-test gotcha** — candidate for a `reference` memory: in this repo's bats 1.13, a non-final bare `[[ ]]` does not fail the test; use `[ ]`/`grep`. Anchored to the BTS-127 strict-mode-bats discipline (`docs/research/tdd-foundations.md`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->