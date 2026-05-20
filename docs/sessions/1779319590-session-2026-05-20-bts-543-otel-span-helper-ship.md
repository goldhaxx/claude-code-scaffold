# Stasis: session-2026-05-20-bts-543-otel-span-helper-ship

> Feature: session-2026-05-20-bts-543-otel-span-helper-ship
> Kind: session
> Last updated: 1779319590
> Session: 68
> Boundary: 2026-05-19T23:30:38-07:00
> Session objective: Plan the Workflow Observability effort (generalize the OTel stack from test-only to workflow-wide) and ship its foundation child, C1.

## Accomplished

* **Workflow Observability planned + tracked.** Ultra-planned the effort (3 Explore + 2 Plan sub-agents); operator approved the plan. Created Linear umbrella **BTS-542** + 6 child issues **BTS-543–548** (Backlog). Plan file: `~/.claude/plans/synthetic-churning-zebra.md`. Operator decisions: full per-tool-call instrumentation (real durations, not counts-only); all 5 deterministic scripts instrumented in one child.
* **C1 (BTS-543) SHIPPED — PR #193 merged** (squash `df96a17`; BTS-543 → Done). New `.ccanvil/observability/otel-span.sh` — a generic sourceable span helper (7 functions: init / cache_invariants / new_trace_id / new_span_id / sanitize / emit / run). `telemetry.bash` + `bats-report.sh` refactored to emit via `otel_span_emit`. New `hub/tests/otel-span.bats` (14 tests).
* **Behavior-preservation proven (AC-8).** Captured a pre-refactor flatten baseline + an after-refactor run, diffed the `(test_name, test_file, test_outcome)` tuple sets: all **2495 pre-existing tests byte-identical**. The only 5 diffs were the new `otel-span.bats` itself.
* **Quality gates:** full suite 2539/2539; manifest 203/203 zero drift; code review caught 1 CRITICAL (unguarded `source` in `bats-report.sh` could corrupt the suite exit code) — fixed; security audit clean for C1.

## Current State

* **Branch:** `main` (PR #193 merged + landed; feature branch deleted local + remote)
* **Tests:** full suite 2539 / 2539 pass — the `/pr` pre-merge gate (`bats-report.sh --parallel`)
* **Uncommitted changes:** none
* **Build status:** clean. Manifest 203 / 203, drift 0.
* **Linear:** BTS-543 Done; umbrella BTS-542 open with C2–C6 (BTS-544–548) in Backlog.
* **Observability stack:** running; this session's 3 full suite runs are visible in Tempo (`bts543-baseline`, `bts543-after`, the `/pr` gate run).

## Blocked On

Nothing.

## Next Steps

1. **C2 (BTS-544)** — session-trace correlation: SessionStart/SessionEnd hooks giving every Claude Code session one rooted OTel trace. Next on the critical path (C1 → C2 → C3 → C5 → C6). Includes a live-verification of SessionEnd-hook reliability.
2. **2 untriaged ideas** — run `/idea triage`.
3. Remaining umbrella children after C2: C3 (BTS-545, instrument 5 scripts + SCHEMA v1.1.0), C4 (BTS-546, Deterministic Scripts dashboard), C5 (BTS-547, per-tool-call instrumentation), C6 (BTS-548, Session Timeline dashboard).

## Context Notes

* **Architecture record lives in the plan file** `~/.claude/plans/synthetic-churning-zebra.md` — the full 6-child design (helper API, file-based session-trace correlation, the rooted session-root span, dashboard designs, the decoupled-measurement Tier-2 design). Each child re-derives its detail at `/spec` time.
* **AC-8 method.** Behavior-preservation for an emission refactor was verified by a full telemetry-enabled suite run before AND after, `otel-flatten.sh` on each, then a diff of the flattened `(test_name, test_file, test_outcome)` tuple sets + record key-sets. Only per-run fields (run_id, span_id, timestamps) legitimately differ.
* **otel-span.bats self-telemetry.** A file that TESTS the telemetry helper inherently perturbs `OTEL_SPAN_*` / `CCANVIL_TELEMETRY_*` env, so its own suite-telemetry was non-deterministic (12 spans in the baseline run, 7 after). Fixed: the file's wiring force-disables its telemetry (`CCANVIL_TELEMETRY_DISABLED=1 telemetry_*`) — it now deterministically emits zero spans. A general rule for future telemetry-testing files.
* **Manifest file-level** `.sh` **id.** A file-level manifest in a `.sh` script infers its `id` from the next function unless the block carries an explicit `# id: <name>` line — `otel-span.sh` needed `# id: otel-span`. Also: every `failure-mode:` / `side-effect:` declared in the manifest needs a matching `# @failure-mode:` / `# @side-effect:` code marker.
* **C1 is foundation plumbing — no new visible dashboard.** The operator's "observability in everything" payoff becomes visible only at C4 (Deterministic Scripts dashboard) + C6 (Session Timeline). C1's visible result is that the existing test dashboard still works identically — itself the proof the refactor held.

## Determinism Review

* **operations_reviewed:** \~20 (planning sub-agents, spec + plan authoring, `otel-span.sh` + `otel-span.bats` authoring, the telemetry/bats-report refactor, 3 full-suite runs, the AC-8 tuple diff, manifest validate, code review, the git ship workflow, 7 Linear issue creates).
* **candidates_found:** 0.

No candidates this session. The work was planning (judgment), TDD implementation, and one-off verification. `otel-span.sh` IS the deterministic substrate — shipped code, not a session heuristic. The AC-8 diff was a one-off verification for a one-time emission refactor (C2–C6 add spans, they do not re-refactor emission); the judgment-heavy part — diagnosing the `otel-span.bats` env-leak — is not computable.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

203 / 203 (allowlist), drift incidents: 0

## Cross-Session Patterns

* `legacy-refs-scan` **runtime-artifact gap — RECURRING (4th session).** The scan again flags `.ccanvil/observability/raw-traces.jsonl` (a gitignored runtime artifact) for a `/catchup` string inside a test-span name. Prior stases flagged this 3×; `legacy-refs-scan.sh` still excludes neither `observability/` nor `state/`. Hub-owned. Four sessions of noting it IS the signal — this should finally become a real ticket: `legacy-refs-scan` should skip gitignored runtime-artifact directories.
* **audit-session — 9** `shasum` **hits, all benign.** `otel-span.sh`'s ID-generation fallback intentionally hashes `date+pid+RANDOM` (randomness is correct for unique IDs); the remaining hits are spec/plan doc text. Not a determinism defect.
* No recurring determinism candidates (prior session 0, this session 0).

## Security Review

PASS. The security audit (run at `/review`) reported 17 findings — all pre-existing in files NOT touched by C1 (`docs/sessions/*`, `hub/meta/operations.md`, `docs/specs/bts-395-*`, `docs/specs/bts-72-*`). Zero introduced by the BTS-543 changeset. `otel-span.sh` / `telemetry.bash` / `bats-report.sh` / `otel-span.bats` / the allowlist carry no secrets, no PII, no network egress beyond the localhost Collector.

## Memory Candidates

1. **Workflow Observability umbrella** — captured this session as `project_workflow_observability_umbrella.md` (BTS-542 + 6 children, C1 shipped, plan-file pointer), indexed in `MEMORY.md`.
2. `legacy-refs-scan` **runtime-artifact gap** — recurring 4 sessions; not a new memory (it is a backlog item that should be ticketed), but the cross-session recurrence is the signal to finally capture it.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->