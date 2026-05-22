# Stasis: session-2026-05-22-bts-560-end-to-end-trace-ship

> Feature: session-2026-05-22-bts-560-end-to-end-trace-ship
> Kind: session
> Session: 72
> Boundary: 2026-05-21T22:59:07-07:00
> Last updated: 1779486426
> Session objective: Triage BTS-560 to priority and ship it — instrument test-suite-run as one end-to-end OTel trace.

## Accomplished

* **BTS-560 SHIPPED — PR #195 merged** (squash `159fd99`; BTS-560 → Done). `test-suite-run` (bats provider → `bats-report.sh`) now emits ONE rooted OpenTelemetry trace: a `test-suite-run` root span with `manifest pre-warm`, `bats suite` (re-parented), and `otel-flatten` phase spans beneath it. New `hub/tests/bats-report-end-to-end-trace.bats` — 11 tests, all 9 ACs.
* **Full lifecycle ran clean:** `/idea triage` → `/spec BTS-560` (validate-clean; critic caught a real AC-4 "root span id" term-ambiguity — fixed the AC-1/3/4/5 class) → `/activate` → `/plan` (7 TDD steps) → 7 red-green cycles → `/review` → `/pr` → `/ship`.
* `/idea triage` cleared the 4-item Triage queue: BTS-560→Backlog P2, BTS-533/561→P3, BTS-559→P3 (operator chose backlog over icebox). Captured **BTS-562** — the recurring `legacy-refs-scan` runtime-artifact false-positive, finally ticketed.
* **Quality gates:** full suite 2558/2558; manifest 203/203 drift 0; live-verified the trace renders in Tempo (rooted, 3 phase spans nested under `test-suite-run`).
* **First** `/pr` **suite run caught 3 real failures** (env-leak ×2 + a SCHEMA.md version-bump misstep) — all root-caused to BTS-560, fixed, re-run green. The full-suite gate caught a regression 11 green stub tests missed.

## Current State

* **Branch:** `main` (PR #195 merged + landed; feature branch deleted local + remote).
* **Tests:** full suite 2558 / 2558 pass — the `/pr` pre-merge gate (wall \~366s).
* **Uncommitted changes:** none.
* **Build status:** clean. Manifest 203 / 203, drift 0.
* **Context budget:** CRITICAL — \~9072 est. tokens vs the 8000 ceiling (113%). Pre-existing; the always-on rules + CLAUDE.md + settings.json exceed the ceiling. Not BTS-560-introduced.
* **Linear:** BTS-560 Done. Triage queue 1 (BTS-562). Backlog 78.
* **Observability stack:** running (used for the live-verify).

## Blocked On

Nothing.

## Next Steps

1. **Triage BTS-562** — the `legacy-refs-scan` runtime-artifact-exclusion fix sits in Triage. Run `/idea triage`.
2. **Workflow Observability umbrella (BTS-542) continues.** BTS-561 (run the manifest pre-warm concurrent with the suite) is the optimization BTS-560's visibility now makes measurable. The C2–C6 critical path: BTS-544 (session-trace correlation) is next.
3. **BTS-533** (test-observability dashboard kinks) — note BTS-560 changed the trace root to `test-suite-run`; BTS-533 must account for the new span names (`test-suite-run` / `manifest pre-warm` / `otel-flatten`).
4. **Context-budget CRITICAL** — the always-on context is at 113% of the 8000-token ceiling. Consider a trim pass; `settings.json` is the largest single contributor (\~1539 tokens, 240 lines).

## Context Notes

* **BTS-560 design.** Root span id + start are established BEFORE the pre-warm so the root fully wraps every phase; the root span *record* emits at completion (true duration known only then). All phase spans emit via `otel_span_emit` ([otel-span.sh](<http://otel-span.sh>)), gated by a new `_otel_trace_live` helper. Span emission is best-effort — never alters the suite exit code.
* **The env-leak — the load-bearing lesson.** The pre-warm span emits BEFORE the bats subprocess; `otel_span_init` exports `OTEL_SPAN_INIT_DONE` / `OTEL_SPAN_LIVE`, which leaked into the bats subprocess and defeated the telemetry-disabled / Collector-unreachable paths in `otel-span.bats` AC-4 and the new AC-8. 11 green stub tests missed it — only the full PARALLEL suite reproduced it (an outer `bats-report.sh` running the pre-warm). Fix: emit the pre-warm span in a subshell so its init-exports stay contained.
* `grep` **is environment-dependent.** Inside bats, `grep` resolves to `/usr/bin/grep` (BSD); at the CLI it is `ugrep`. BSD grep mishandles `\|` BRE alternation differently — `observability-schema.bats` AC-9's `\|`-pattern counted the combined alternation as 1, not the union. My SCHEMA.md intro version-bump (`v1.0.0`→`v1.1.0`) — itself wrong, the consumed schema version did not change — dropped a `` `v1.0.0` `` marker below the test's threshold. Reverted the bump.
* **Critic mode earns its pass** even on a validate-clean spec — `/spec --review` caught "the root span id" used as an undefined term across AC-3/4/5.
* `/pr`'s `features.pr_review` flag is `false` — its optional code-review gate did not auto-run; `/review` was run manually.

## Determinism Review

* **operations_reviewed:** \~30 (recall, 4 triage transitions + 1 capture, spec + critic + validate, activate, plan, 7 TDD cycles, review + agent + security + manifest, 2 full-suite runs + cleanup + push + finalize, ship, Tempo live-verify).
* **candidates_found:** 1.

**concurrent-edit-verify-then-override**: Claude ran the `document-history` + `document-updated-at` verification, then `ALLOW_CONCURRENT_EDIT_OVERRIDE=1` force-write, THREE times this session (spec dispatch ×2, activate dispatch). The verification is mechanical — `document-history` empty AND `updatedBy` == the caller's own API-key identity means the only diverging edit is the caller's own prior write. `artifact-write` could auto-resolve that exact case instead of failing and requiring a manual 3-step verify-override each time. Should be substrate logic in `artifact-write` / the concurrent-edit guard. Impact: medium.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

203 / 203 (allowlist), drift incidents: 0

## Cross-Session Patterns

* `legacy-refs-scan` **runtime-artifact false-positive — RECURRING (6th session), now ticketed.** The scan flagged \~160 matches, ALL in `.ccanvil/observability/raw-traces.jsonl` — a gitignored OTel runtime artifact; the matches are `checkpoint` / `catchup` strings inside captured test-span names. `node-specific` scope. The count ballooned this session because BTS-560's work ran the full suite 3× and `raw-traces.jsonl` grew. Flagged unticketed for 5 prior sessions; **this session it was finally captured as BTS-562** ("legacy-refs-scan: exclude gitignored runtime-artifact dirs"). Fix is hub-owned: exclude `observability/` and `state/` from the scan.
* **Concurrent-edit-guard friction recurred.** The guard false-positived on the agent's own writes this session (×3) — and the BTS-558 session's stasis recorded the same friction. Now captured as a determinism candidate (above).
* **audit-session:** 0 findings since `1b68ddf`. No recurring stochastic pattern.

## Security Review

PASS. `/review`'s security audit reported 17 findings — all pre-existing in files NOT touched by BTS-560 (`docs/sessions/*`, `hub/meta/operations.md`, `docs/specs/bts-394/395/72`). Zero introduced by the BTS-560 changeset (`bats-report.sh`, `bats-report-end-to-end-trace.bats`, `SCHEMA.md`, `README.md` carry no secrets, PII, or credentials).

## Memory Candidates

1. `grep` **is environment-dependent in this repo** — inside bats it is `/usr/bin/grep` (BSD); at the CLI it is `ugrep`. BSD grep mishandles `\|` BRE alternation. Tests/scripts that rely on `\|` are fragile across the two. Candidate for a `reference` memory.
2. **Workflow Observability umbrella progress** — BTS-560 (a child of BTS-542) is SHIPPED. The existing `workflow-observability-umbrella` memory records BTS-560 as Triage; it should be updated to Done, with BTS-544 noted as the next critical-path child.
3. **Span-emission-before-subprocess leaks init state** — when a script emits an OTel span (or any `otel_span_*` call) before spawning a subprocess, `otel_span_init`'s env exports leak into that subprocess; isolate such emissions in a subshell. Candidate for a `reference` or `feedback` memory.