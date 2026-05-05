# Stasis

> Feature: session-2026-05-05-bats-perf-chain-ship
> Kind: session
> Last updated: 1778000439
> Session: 21
> Boundary: 2026-05-05T10:00:39-07:00
> Session objective: Resolve the bats-suite "FOREVER" pain (operator's 2026-05-01 directive) — ship BTS-277 (observability) end-to-end, then chase the substrate hotspots the new profiler surfaces.

## Accomplished

**Five PRs merged in one session — full lifecycle each (spec → activate → TDD → /pr → /ship).** All wins compound on the same suite-perf axis.

* **BTS-277 (PR #156) — bats observability + perf-core default.** Bumps `bats-report.sh` `--jobs` default from `cpu/2` (8) to `hw.perflevel0.physicalcpu` (12 on M4 Max), adds `wall_ms`/`jobs`/`cpus` to `--json` envelope, appends each run to `.ccanvil/state/bats-runs.jsonl` (NDJSON, gitignored). 1965 → 1983 tests (+18 new). Live-API gate confirmed `--jobs 12` on M4 Max.
* **BTS-282 (PR #157) — bats subprocess profiler.** New `.ccanvil/scripts/bats-profile.sh` intercepts `bash <path>/<wrapped-script>` calls via PATH-prefixed bash shim with re-entry guard (`BTS_PROFILE_INSIDE`), aggregates into `[{cmd, verb, count, total_ms, mean_ms}]` JSON. Default wrap targets observed heavy-hitters (ccanvil-sync.sh = 241 calls in hub/tests/). 1983 → 1992 tests.
* **BTS-281 (PR #158) — cache hub-validate via suite-level pre-warm.** Profile said `module-manifest.sh validate` = 94% of substrate CPU, 5 hub-validate calls × ~7 min each. Two-layer cache: `bats-report.sh` pre-warms validate JSON ONCE before invoking bats; helper consumes cache via `BTS_MANIFEST_VALIDATE_CACHE` env var. Suite wall: 646.7s → 579.2s (-10.4%).
* **BTS-293 (PR #159) — Phase 1: caller-resolution cache.** Original capture framed as "cmd_extract caching" — source-walk found the actual bottleneck was `_caller_actually_calls_primitive` re-walking source dirs ~7,500× per validate run. Pre-built TSV index of (file, function, body), bash 3.2 / awk only. Validate wall 6:55 → 5:52 (-15.2%).
* **BTS-296 (PR #160) — Phase 1.5: target-body cache for markers.** `_target_body_grep` was re-extracting the same function body per depends-on / failure-mode / side-effect marker — ~2,800 awk re-walks per validate run. Pre-extracts every (path, id) → tempfile once, greps the cached body. Validate wall 5:52 → **3:39 (-37.8% over Phase 1, -47.2% cumulative).**

**Cumulative perf impact:**

| Surface          | Baseline | After BTS-296 | Δ |
|------------------|---------:|--------------:|--:|
| validate wall    | 6:55     | 3:39          | **-47.2%** |
| validate CPU     | 591s     | 294s          | **-50.3%** |
| suite wall (proj)| 647s     | ~410s         | **~-37%** |

**Substrate-perf queue extended:** captured BTS-281 (caching the calls), BTS-282 (profiler), BTS-293 (Phase 1 caller-cache), BTS-294 (Phase 2 parallelize), BTS-295 (Phase 3 incremental hash-skip), BTS-296 (Phase 1.5 target-body cache), BTS-283 (soak-tracking remote agent — consumes BTS-277's `.jsonl`).

## Current State

* **Branch:** `main`, fast-forwarded. Working tree clean.
* **Tests:** 1992 passing (was 1965 at session start, +27 from new test coverage in BTS-277/282).
* **Uncommitted changes:** none.
* **Build status:** clean.
* **Manifest coverage:** 189 / 189 (allowlist), drift 0.
* **Backlog:** 1 / **Triage:** 6 (BTS-294 Phase 2 parallel, BTS-295 Phase 3 incremental, BTS-283 soak-tracking, BTS-263 / BTS-264 / BTS-278 carry-forward determinism candidates) / **Icebox:** 2 (BTS-22, BTS-21).

## Blocked On

Nothing.

## Next Steps

**Operator's 2026-05-01 main-thread directive resurfaces:** "come back to the main working thread once we resolve the test bloat" — Phase 2 commit-or-rotate decision. Test-bloat is now mitigated meaningfully (-47% validate wall, -10.4% measured suite wall, est. -37% suite wall after the cache stack settles).

Decision options for next session start:

1. **Drain the substrate-perf queue (BTS-294 + BTS-295).** Phase 2 parallelizes the per-manifest validation loop now that Phase 1+1.5 caches are in place — should compound. Phase 3 (incremental hash-skip) is the largest remaining win for the PR-flow case where 1-3 files change. Target: validate wall <2 min, suite wall <5 min.
2. **Ship BTS-283 (soak-tracking remote agent).** Now that `.ccanvil/state/bats-runs.jsonl` exists from BTS-277 and the perf surface has clearly moved, a weekly remote agent that watches the median wall_ms drift catches the next regression cheaply. Low-risk, low-effort.
3. **Rotate to "Simplicity through leverage" theme** (per `roadmap.md`) — modular personality packs. Different value axis. The substrate-perf queue stays open as background.
4. **Triage remaining captures.** 6 in Triage, including 3 carry-forward determinism candidates (BTS-263 bats-output-flakiness, BTS-264 caller-conservativism rule, BTS-278 cmd_extract scaling pattern).

Recommended order: BTS-283 (cheap) → BTS-294 (compounds) → triage → BTS-295 / rotate.

## Context Notes

* **Live profiling drives the right optimization.** BTS-282 (profiler) was the load-bearing decision in the chain. Without it, BTS-281 was framed correctly but BTS-293's "cmd_extract caching" framing was wrong — only source-walk during impl revealed the actual hotspot was caller-resolution. Pattern: ship instrumentation BEFORE optimization specs commit. Mirrors `feedback_research_before_architectural_commit` and `feedback_lightweight_pattern_dogfoods_substrate_design`.
* **Re-spec-on-evidence is the correct discipline.** BTS-293 was activated with one framing, then mid-impl I source-walked the hot path and the actual bottleneck was different. The spec was tightened (Out of Scope: cmd_extract; In Scope: caller-resolution), the implementation matched evidence rather than the original capture. No friction — the operator's auto-mode flow and the lifecycle docs absorbed the shift cleanly.
* **One-liner function trap in awk extraction.** First implementation of `_build_caller_index`'s awk pattern didn't count opens/closes on the function-DECLARATION line itself — so one-line `die() { ...; }` swallowed hundreds of subsequent lines. Live-validation gate caught it via the production-allowlist regression test in `module-manifest-drift-guard.bats`. Memorialized in BTS-293 commit message; future awk-body-extraction primitives MUST count braces on the decl line. (Same gotcha applies to BTS-296's `_build_target_body_index`, which used the same pattern correctly the second time.)
* **Suite wall is gated by the slowest single call, not the call count.** BTS-281 caching (eliminate 4 of 5 hub-validate calls) only saved 67s wall because the pre-warm IS itself one hub-validate call (~7 min critical path). The substrate-fix (BTS-293 + 296) is what unlocks further wall savings — they cut the per-call cost. Architectural lesson: caching call-count is bounded by per-call wall-time; fixing per-call cost is unbounded.
* **Operator pattern: "tell me more about X".** Used twice this session (BTS-283 soak-tracking + BTS-293 validate perf). Both times this surfaced critical additional context that informed the spec scope. Don't skip the explanation step in auto-mode — operator-questions-before-approval are load-bearing decisions, not friction.
* **Capture flag friction at scale.** Captured 4 follow-up tickets via `/idea` mid-session (BTS-281, BTS-282, BTS-283 in earlier session; BTS-296 Phase 1.5 mid-BTS-293). Linear-routed dispatch worked cleanly. The `--family` flag was advertised in the `/idea` skill but I never used it — captures were framed via prose "## Family" sections in the body. Net result is the same; flag is unused infrastructure.

## Determinism Review

* operations_reviewed: ~80 (5 PR cycles × ~15 manual ops each + multiple bats runs + manifest validates + diff inspections)
* candidates_found: 1

* **bg-bats-output-truncation-recurrence**: Multiple times this session, `grep -c` against streamed bats output via the Bash tool returned partial counts (5 ok lines when bats actually ran 117 tests). Workaround: redirect to a tempfile, grep the file. Same root-cause pattern as BTS-263 (bats-report-parallel-output-flakiness) — appears to be the Bash-tool harness vs streamed multi-MB stdout interaction. Already captured as BTS-263; this session adds a third instance to the evidence pile. Should bats-report.sh write to a hardened tempfile internally, or should the harness ack stream-completion better? Decision pending. Impact: medium — costs 1-2 min per occurrence to retry with file-based capture.

## Evidence Gaps

* BTS-296 — Phase 1.5: target-body cache for cmd_validate (depends-on / failure-mode / side-effect markers) — missing-evidence-anchors

> Note: this evidence-gap flag is a likely false-positive from the BTS-201 heuristic — BTS-296 was a perf optimization with profile evidence baked into the spec body, not a bug-shape capture. The `failure-mode` substring in the title likely matched the heuristic. Not blocking; surfacing per protocol.

## Manifest Coverage

189 / 189 (allowlist), drift incidents: 0

## Cross-Session Patterns

* **CONFIRMED RECURRING (now 4 sessions): live-evidence-drives-the-right-optimization.** BTS-282 → BTS-281 → BTS-293 → BTS-296 chain. Each substrate fix surfaced the next one via measurement. Same pattern Sessions 9-11 (manifest rollout) demonstrated on the opposite axis (drift-guard surfacing substrate bugs).
* **CONFIRMED RECURRING (3 sessions): bg-bats-output-truncation.** Captured as BTS-263 in Session 16, recurred Session 18, recurred again this session. Has not been root-caused; remediation is operator-facing (use a tempfile for full-suite output capture).
* **NEW PATTERN this session: scope-up via source-walk.** When a capture's framing is "X is slow", source-walk before specing — the real hotspot may not match the prose. BTS-293's reframe (cmd_extract → caller-resolution) was a clean example.
* **No legacy-refs drift.** `legacy-refs-scan` returned `[]`.

## Security Review

PASS. Session diffs touched `.ccanvil/scripts/module-manifest.sh` (perf optimization), `bats-report.sh` (env-gated cache pre-warm), new bats fixtures and `_helpers/` directory, and `bats-profile.sh` (new profiling tool). No secret/PII patterns in diffs; no .env or credential files modified.

## Memory Candidates

* **Live-profile-before-perf-spec rule.** When committing to a perf optimization, ship instrumentation FIRST (BTS-282 pattern) and let the data drive the spec scope. Original BTS-293 capture framed "cmd_extract caching" — source-walk during impl proved the actual hotspot was caller-resolution. Memory candidate: extend `feedback_research_before_architectural_commit` with a perf-specific addendum.
* **Suite-wall vs call-count optimization.** Caching N calls down to 1 call is bounded by the wall-time of the surviving call. Per-call cost reduction is unbounded. Always ask: "is this caching CALL COUNT or CALL COST?" — different ceilings.
* **Awk function-body extraction must count braces on decl line.** One-liner `fn() { ...; }` will swallow subsequent file content if the depth counter doesn't process the declaration line itself. Reference primitive: `_build_caller_index` / `_build_target_body_index` in module-manifest.sh.
* **`--family` flag in /idea is advertised but unused.** Operator-friendly prose ("## Family" section in body) achieves the same result. Decision: leave the flag, but don't expect it to be the canonical path.

## Session ledger (2026-05-05)

| Phase | PR | Ticket | What |
|-------|----|--------|------|
| 1 | #156 | BTS-277 | bats observability + perf-core default |
| 2 | #157 | BTS-282 | bats subprocess profiler |
| 3 | #158 | BTS-281 | cache hub-validate via suite-level pre-warm |
| 4 | #159 | BTS-293 | Phase 1: caller-resolution cache |
| 5 | #160 | BTS-296 | Phase 1.5: target-body cache for markers |

Captured during the run: BTS-281, BTS-282, BTS-283, BTS-293, BTS-294, BTS-295, BTS-296.
