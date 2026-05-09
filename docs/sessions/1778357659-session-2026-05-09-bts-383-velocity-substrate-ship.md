# Stasis: session-2026-05-09-bts-383-velocity-substrate-ship

> Feature: session-2026-05-09-bts-383-velocity-substrate-ship
> Kind: session
> Last updated: 1778357659
> Session: 35
> Boundary: 2026-05-09T12:04:36-07:00

## Accomplished

Resumed from session 33's pause and shipped BTS-383 end-to-end in a single arc:

* **PR #172 (BTS-383) — SHIPPED** at 2026-05-09 \~12:50 PT. 7 commits, squash-merged, branch deleted, BTS-383 → Done in Linear (auto-close fired).
* **Substrate landed:**
  * `bats-report.sh --progress` two-mode design — with `--parallel`, defers to native `bats --jobs N` for speed and emits periodic heartbeats only (parallel TAP interleaves so per-file boundaries are not extractable). Without `--parallel`, per-file orchestration emits `[N/M] <file>: PASS X/Y in T.Ts` to stderr after each file completes. Heartbeat fires in both modes; configurable via `BATS_PROGRESS_HEARTBEAT_SECS` (default 30s).
  * `bats-report.sh --json` envelope and `bats-runs.jsonl` records carry `failures: [{test_name, file, line_number, error_excerpt}]` parsed from TAP via perl + `JSON::PP` (additive — backward-compatible).
  * `module-manifest.sh validate --changed-only [--since <ref>]` — scopes drift detection to `git diff --name-only <ref>` ∩ allowlist. \~6 min full validate → \~3s on a 1-line diff. Adds `scanned_files[]` to JSON envelope.
  * `/pr` skill wired to `--parallel --progress` so every future ratification has streaming visibility for free.
* **Self-application proof:** /pr's full-suite ran `bash bats-report.sh --parallel --progress` and emitted heartbeats every 30s for the full \~6 min. PASS 2106 / FAIL 0 / TOTAL 2106. AC-12 satisfied directly via the new substrate.
* **Velocity discipline held:** zero stacked bats invocations, zero wait-loops, one full-suite at /pr time per the BTS-383 own discipline rule. The atomized `background-task-discipline.md` rule held — exactly the pattern AC-13 predicted for the next session.

## Current State

* **Branch:** `main` (post-ship, fast-forward from squash-merge of #172).
* **Tests:** `PASS 2106 / FAIL 0 / TOTAL 2106` (\~6 min wall via `--parallel --progress`).
* **Uncommitted changes:** none.
* **Build status:** clean. PR #172 MERGED.

## Blocked On

Nothing.

## Next Steps

Per `/radar` and the prior session 33 stasis directives:

1. **BTS-387 PR #171 ratification** — the pause-state PR from session 33 (5 fails + 13 missing tests). Now diagnosable in seconds via the new `--json failures[]` envelope. Targeted bats with `--json` returns per-test detail; no need for grepping 140 files.
2. **BTS-384 — rule scope tags.** Composes with the BTS-385/387 frontmatter foundation (already merged on main once PR #171 ships). Distribution filter on top of `tier`/`scope`/`stack` peer keys.
3. **BTS-204 — SSOT-Linear.** Dedicated session, major effort. Routes specs/plans/stasis to Linear ticket bodies as primary surface. Listed in Triage on Linear.
4. **Untriaged ideas:** 1 in Triage state — run `/idea triage` when convenient.

## Context Notes

* **Initial** `--progress` impl had a `--parallel` regression — the first version did per-file serial orchestration regardless of `--parallel`, which would have made the /pr full-suite \~2-3x slower than parallel-no-progress (146 files serial vs 12-way parallel). Caught at the /pr step; fixed in commit 023f2c7 with the two-mode design (parallel=heartbeat-only, serial=per-file). Per `feedback_scope_up_on_live_api_reveal` — folded the fix into the same PR rather than splitting.
* **bash 3.2 macOS constraint** — avoided `declare -A` (associative arrays) and `wait -n` (Bash 4+ only) in the orchestration code. Used `grep -Fxq` for membership lookups and a serial for-loop.
* **Velocity expectation reset** — session 33 estimated 30-min full-suite. Actual on this session: \~6 min. Substantial perf work landed earlier (BTS-281 manifest pre-warm, BTS-293/296 caller/target-body indices). BTS-383 closes the *visibility* gap, not the *speed* gap (already good). The session 33 pause was therefore overpriced — the discipline failure was real, but the wall-time pressure was less severe than feared.
* **Initial** `tail -50` pipe defeated streaming — when first running `bash bats-report.sh ... 2>&1 | tail -50`, the `tail` buffered the entire stream until EOF. No streaming progress reached the output file. Fixed by dropping the `| tail -50` (the harness captures all output anyway). Operator-side mistake; not a substrate gap.
* `_parse_failures` perl + JSON::PP approach — chose perl over awk because gawk's `match()` with capture groups isn't on macOS BSD awk. Perl + JSON::PP is in core for both macOS and Linux; [bats-report.sh](<http://bats-report.sh>) already declares `depends-on: perl`.

## Determinism Review

operations_reviewed: 23
candidates_found: 0

No candidates this session. The discipline held: targeted bats per logical edit (zero full-suite invocations during iteration), one full-suite at /pr time, no parallel-duplicates, no wait-loops, no zombie processes. The only stochastic operations were narrative composition (commit messages, PR body) which is appropriately Claude work.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

194 / 194 (allowlist), drift incidents: 0 (verified at PR-time pre-flight; `--changed-only --since HEAD~3` post-merge confirms 70/70 scanned subset clean).

## Cross-Session Patterns

* **Recurring pattern: full-bats-runs-during-iteration — BROKEN this session.** Session 33's stasis surfaced this as the dominant discipline failure (5+ full-suite runs in one feature session, \~2.5 hours of test-theater). Session 35 ran exactly ONE full-suite invocation, at /pr time, per the atomized rule. The pattern is closed at the substrate level (--progress eliminates the buffer-vs-hung confusion that drove some of the duplicates) and at the discipline level (rule + new dogfood evidence).
* **Recurring pattern: substrate-collision-mid-PR — repeated this session.** Session 33 had 3 in-PR architectural corrections across BTS-385/386/387. Session 35 had 1: the `--progress`×`--parallel` regression caught at /pr step, folded into the same PR. Same pattern; appropriate handling per `feedback_scope_up_on_live_api_reveal`.
* **No legacy-refs drift.**
* **Compared against prior stasis** (session 33 BTS-387 archive at `1778353090-bts-387-rule-atomization-audit-stasis.md`): the test-theater pattern that drove the session 33 pause is now structurally closed.

## Security Review

PASS — no secret/PII patterns committed this session. All shipped files are substrate code (`bats-report.sh`, `module-manifest.sh`), test fixtures, skill markdown, and lifecycle archives. No `.env`, no credential refs.

## Memory Candidates

* **Project pattern:** `project_bts_383_substrate_landed` — BTS-383 SHIPPED 2026-05-09 PR #172. `--progress` + `--json failures[]` + `--changed-only` + /pr wiring all live on main. The visibility gap is closed; speed gap was already closed by BTS-281/293/296. No follow-up substrate needed for AC-1 through AC-12.
* **Project pattern:** `project_bts_383_velocity_thesis_validated_in_session` — same-session dogfood proof: substrate landed AND used to ratify itself (the /pr's bats-report invocation streamed heartbeats). AC-13's "subsequent feature session" predicate also satisfied directly because this session is BTS-383's own ratification AND the BTS-387 PR #171 ratification target.
* **Reference:** `reference_bts_383_two_mode_progress_design` — `--progress` × `--parallel` interaction: parallel=heartbeat-only (per-file lines impossible because of TAP interleave), serial=per-file. Both modes share the heartbeat. Documented in `bats-report.sh` lines 240-260; this is the design pattern future progress-style flags should follow.
* **Feedback (validated):** `feedback_velocity_substrate_dogfood_close_loop_in_one_pr` — when shipping a substrate that the /pr step depends on (like --progress), wire the /pr skill to use it in the SAME PR. Otherwise the substrate is unused-when-most-relevant. Validated this session by editing `.claude/commands/pr.md` in commit 53b5242 alongside the substrate code.