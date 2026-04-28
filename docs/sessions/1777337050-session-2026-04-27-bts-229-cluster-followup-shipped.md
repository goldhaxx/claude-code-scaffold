# Stasis

> Feature: session-2026-04-27-bts-229-cluster-followup-shipped
> Kind: session
> Last updated: 1777337050
> Session: 8
> Boundary: 2026-04-27T16:35:57-07:00
> Session objective: ship the four BTS-229-cluster follow-ups (BTS-232/233/234) plus the highest-leverage OD candidate (BTS-235 ship-finalize wrapper) — closing the read-side resilience gap, the apostrophe-s friction, and the per-ship 4-step finalization tax in one sweep.

## Accomplished

* **4 ships back-to-back, all merged via tactical sweep on substrate already mature:**
  * **BTS-232** (PR #125) — `/recall` carry-forward determinism candidates. New `cmd_stasis_carry_forward` substrate parses prior-stasis `## Determinism Review` (tolerating bolded `**slug**:` and backticked `` `tok` `` shapes), queries idea listing, surfaces candidates whose dual-capture didn't land. Live dogfood during impl caught a metadata-skip bug (bolded `**operations_reviewed:**` was matching as a candidate); fixed in the same commit.
  * **BTS-233** (PR #126) — `/idea sync` replays from `dual-capture-emergency.log`. Refactored `cmd_idea_pending_replay` to extract per-log helper, called twice (pending log → emergency log). Output JSON adds `emergency_pending`. Closes BTS-205's read-side resilience loop.
  * **BTS-234** (PR #127) — `guard-workspace.sh` apostrophe-s tolerance. Three coordinated changes: removed global `tr -d "'"`, added `('s)?` to BTS-173 regex via `$'\'s'` ANSI-C quoting, added per-token leading/trailing apostrophe strip for path-shape security parity. Initial impl had a quoting bug (unmatched `"`) caught by the lint hook; fixed via cleaner ANSI-C variable.
  * **BTS-235** (PR #128) — `ship-finalize` substrate + `/ship` skill. Collapses post-`/pr` cycle (title-fix → ready → merge → land → ticket-close) into one verb. **Live-dogfooded on its own PR** — `{pr_merged: true, branch_deleted: true, ticket_closed: true, errors: []}`. The high-value addition is the auto-close: session 7+8 paid the manual `ticket.transition done` cost 7 times due to `gh pr merge --squash --delete-branch`'s switch-to-main bypass; now folded into the substrate.
* **BTS-236 captured to Triage** — surfaces the `derive-pr-title` mid-sentence truncation gap (BTS-181/182 fixes shipped but don't close the class; PR #128's subject `feat(bts-235-...): Every ship cycle ends with the same 4-step sequence: \`assert-pr-title\` (forces\` is the live evidence). Initially commented on the closed BTS-182 — operator caught: closed tickets aren't watched; fresh triage capture is the correct mechanism.
* **Triage cleared at session start** — operator promoted 4 of 4 candidates (BTS-232/233/234/235) at P3 in one batch. Ship list followed natural neighborhood: read-side resilience pair (232+233), substrate hardening pair (234+235).

## Current State

* **Branch:** `main`, fast-forwarded to origin via BTS-235's own ship-finalize verb. Working tree clean.
* **Tests:** **1826 / 1826 passing** (1787 baseline + 39 new this session: 12 BTS-232, 6 BTS-233, 14 BTS-234, 7 BTS-235).
* **Uncommitted changes:** none.
* **Build status:** clean.

## Blocked On

Nothing.

## Next Steps

1. **BTS-236 triage when convenient.** The fresh capture surfaces the derive-pr-title truncation gap with two paths forward (mechanical lookback widening to \~16 chars + comma/colon boundaries, OR structural pivot to `> Subject:` spec metadata field). Recommend the structural pivot — closes the class, not just the case. Run `/idea triage` to pick a path.
2. **BTS-163 spec when ready.** Delivery primitive multi-ship initiative remains the operator's call. The architectural sketch lives on BTS-163 as a comment with three candidate substrate shapes. Multi-ship — likely 4-5 ships once specced.
3. **BTS-217 flip-linear-routing dogfood follow-up.** Roadmap "Up Next" P2 — but stasis just dogfooded the routing path successfully (Linear Document writes for spec + stasis), suggesting BTS-217 may already be effectively validated. Re-read the BTS-217 spec to confirm the closing criteria.
4. **Linear backlog drainage status.** 13 Backlog (was 13 at start of session 8 → +4 from triage promotion → -4 closed → 13 net). Triage queue: 1 (BTS-236 just captured).

## Context Notes

* `/ship` skill validates a new pattern: substrate + skill ship together, dogfood the substrate on the same ship's PR. The auto-close path that session 7+8 paid manually is now permanent. Any future ship that uses `/ship` will exercise the path.
* **Concurrent-edit retry on activate fired 4 times this session** — every spec dispatch hit the race because /spec writes the spec Document via `artifact-write`, then `activate` writes a status-flipped revision, racing its own write. Workaround: `ALLOW_CONCURRENT_EDIT_OVERRIDE=1 artifact-write` retry. Determinism candidate (see Review below).
* **Live-dogfood during BTS-232 impl caught a parser bug** — bolded metadata bullets (`**operations_reviewed:**`) were matching as candidates because the bolded-shape regex captures everything between `**...**`, and the bullet's leading text included the bolded metadata. Fixed by post-extract metadata-name skip. The bug never showed up in fixture-only tests because the fixtures used the canonical non-bolded shape; live data forced the bolded-shape edge case.
* **The** `/ship` skill's first dogfood call used the JSON output directly — operator-readable summary rendering was deferred. Still cleaner than 4 manual gh commands. Future polish: skill prose can render the one-line status.
* **Rendering the auto-close result in /ship's output** — `ticket_closed: true` is a literal boolean; the skill prose should translate that to `ticket=closed | queued | n/a` for human readability. Minor follow-up; tracked in BTS-235's spec section as a UX consideration but not critical.

## Determinism Review

* **operations_reviewed:** \~60 (4 ship cycles × \~15 ops each: spec write + dispatch + retry, ticket transition todo + in-progress + done, activate, plan write, bats RED + GREEN, suite run, commit, push, pr-cleanup, push, gh edit + ready + merge, manual ticket-close until BTS-235, full-suite-verify)
* **candidates_found:** 1
* `spec dispatch + activate concurrent-edit race`: every spec ship this session hit the Linear concurrent-edit guard because `/spec` dispatches `artifact-write --kind spec` and then `activate` re-writes the spec Document with `Status: In Progress`, racing its own first write. Operator must retry with `ALLOW_CONCURRENT_EDIT_OVERRIDE=1`. **Should be deterministic**: either (a) `cmd_activate` skips the spec re-dispatch when only the Status header changed (using BTS-178-style content-hash comparison), or (b) `/spec` defers the dispatch to `activate` so there's only one writer. Impact: medium — every spec ship pays the cost.

## Evidence Gaps

No evidence gaps this session.

## Cross-Session Patterns

* **CONFIRMED RECURRING (sessions 4-8): dogfood-surfaces-substrate-correctness.** Session 8 added BTS-235's ship-finalize substrate dogfooded on its own PR with `ticket_closed: true` end-to-end. 5th consecutive session of dogfood-as-validation. Memory `feedback_dogfood_probe_as_thesis_test` reinforced.
* **CONFIRMED RECURRING (sessions 7-8): concurrent-edit retry on activate.** Hit 4 times session 7, 4 times session 8. Same workaround. Now flagged as OD candidate above.
* **CONFIRMED RECURRING (sessions 7-8): substrate-fix paired with data-recovery.** BTS-228 in session 6 fixed IssueRelation API + recovered lost relation. Session 7 used the substrate for legitimate transition (BTS-231 → BTS-163 dup). Session 8 used BTS-235's substrate to auto-close BTS-235 itself — substrate is dogfooded on the very ship that introduces it.
* **NEW (session 8): WIP-limit lesson held.** Memory `feedback_finish_open_release_before_new_architectural_work` (saved end-of-session-7 after BTS-163 misorder) informed this session — operator's "do 232, 233, 234" was a tactical neighborhood within the BTS-229 cluster, not a competing multi-ship initiative. No scope drift.
* **NEW (session 8): post-shipping triage discipline.** Operator caught the misplaced comment on closed BTS-182; correct move was fresh triage capture (BTS-236). Pattern: closed tickets aren't watched; new evidence requires new tickets. Memory candidate below.
* **No legacy-refs surfaces.** `legacy-refs-scan` returned `[]`. The 5 audit-session findings (4 git-C, 1 jq) are the deterministic substrate code patterns — same false-positive set as session 7 (consistent baseline).

## Security Review

* All 4 ships were substrate + skill-prose changes. No new auth surfaces.
* BTS-232's `stasis-carry-forward` reads stasis via `cmd_artifact_read` (same auth as `/recall`); reads idea listing via `operations.sh resolve idea.list` (same auth as `/idea list`).
* BTS-233's `idea-pending-replay` extension reuses the http substrate — same auth as the pending-log replay path.
* BTS-234 is a regex/strip-logic change in `guard-workspace.sh`; no auth surface.
* BTS-235's `ship-finalize` orchestrates existing `gh` + `cmd_assert_pr_title` + `cmd_land` + `ticket.transition`; no new auth surfaces; ticket-close auth via `LINEAR_API_KEY` (already proven). `GH_OVERRIDE` env var is TEST-only — production path uses bare `gh`.
* All 39 new bats tests use stubs (`LINEAR_QUERY_OVERRIDE`, `GH_OVERRIDE`, fixture JSON) — no live API in CI.
* **Verdict: PASS.**

## Memory Candidates

* **NEW MEMORY:** `feedback_no_comments_on_closed_tickets_for_new_evidence` — when surfacing new evidence (regressions, gaps, follow-ups), don't comment on closed tickets — they're not watched. Capture a fresh triage ticket so it surfaces in the next `/idea triage`. Anchored on session 8 BTS-236 capture after operator caught a misplaced comment on closed BTS-182. **Save as feedback memory.**
* **REINFORCE:** `feedback_dogfood_probe_as_thesis_test` — BTS-235 ship-finalize ran on its own PR with full success including the previously-broken auto-close path. 5th consecutive session of dogfood-validates-substrate.
* **REINFORCE:** `feedback_finish_open_release_before_new_architectural_work` — held this session. Operator's directive was tactical-neighborhood-shaped, not a new multi-ship initiative. Memory's first cross-session validation as an active behavioral guide.
* **No new external references** this session.