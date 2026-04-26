# Stasis

> Feature: session-2026-04-26-bts-22-and-181-ship
> Kind: session
> Last updated: 1777221327
> Session objective: post-/recall continuation. Ship BTS-181 (the cosmetic determinism candidate from the prior stasis), then refresh + ship BTS-22 (the headline old ticket that needed substrate-fit review). Drain the actionable backlog to research-only items.

## Accomplished

**Two substrate ships, both single-session, both extending the substrate compounding pattern observably.**

- **BTS-181 (PR #103).** `derive-pr-title` substrate primitive — single source of truth for spec→PR-title derivation, factored from the duplicate sites in `cmd_activate` (line 983) and `cmd_assert_pr_title` (line 2446). Adds deterministic truncation: first period strips suffix; remaining suffix capped at 80 chars (trailing whitespace trimmed). 9 ACs in `derive-pr-title.bats` including drift-guards asserting both call sites delegate to the primitive. /review skipped per `feedback_skip_review_on_trivial_diffs` (substrate primitive + drift-guards). Live-validated against PR #103's own title — the substrate produced the expected 80-char-truncated form, but `assert-pr-title` no-op'd per its trust-user-edits semantics (BTS-178 contract — only repairs placeholder/missing-prefix shapes). PR #103 manually shortened once to the deterministic form for the squash merge.

- **BTS-22 (PR #104).** Stasis history directory + checkpoint cleanup. Original BTS-22 framing ("multi-file specs/plans/checkpoints") was largely superseded — `docs/specs/` already holds 100 archive files, Linear is canonical backlog (BTS-164/166/175), and substrate is densely coupled to single-file `docs/spec.md` (14 consumers, 18 references in docs-check.sh alone). Per Zach's instruction ("review and refresh"), reframed scope to the only sub-question with observed pain: stasis history. Two new substrate primitives — `archive-stasis` (idempotent copy of live stasis to `docs/sessions/<epoch>-<feature_id>.md`, errors on collision) and `sessions-list [--limit N]` (sorted-newest-first JSON, malformed-file resilient). 21 ACs across two bats files. `/stasis` and `/recall` skills updated. Checkpoint cleanup verified via drift-guard (no active producers; intentional legacy guards preserved). 1475 → 1496 tests, +21 net.

**Substrate compounding directly observable:** BTS-181's `derive-pr-title` fired correctly at BTS-22's activate time (PR #104's title was auto-truncated to the deterministic 80-char form, no manual `gh pr edit` needed). Less than 30 minutes elapsed between merging BTS-181 and seeing it pay off on the next PR.

## Current State

- **Branch:** `main` at `d43457c`, in sync with `origin/main`.
- **Tests:** **1496 / 1496 green** via `bats-report.sh --parallel` (1466 → 1496, +30 net across both ships).
- **Uncommitted changes:** none.
- **Build status:** clean.
- **Active spec:** none — between features.
- **Permissions audit:** `danger=0`, `promote-review.total=0`. Clean.
- **Linear backlog (canonical via `backlog.list` http resolver):**
  - **BTS-21** (P4) — GitHub Agentic Workflows (gh-aw) integration. `needs-research`.
  - **BTS-20** (P4) — Workflow engine / deterministic state machine. `needs-research`.
- **Untriaged ideas:** 0.
- **Pending log:** empty.
- **Context budget:** 234.2k / 1M tokens (23.4%) per `/context`. Plenty of room; cadence-driven boundary is the trigger.

## Blocked On

- Nothing. Two clean ships; cadence held; backlog drained to research-only items.

## Next Steps

The actionable backlog is **empty**. Remaining options:

1. **Research P4s — BTS-20 + BTS-21.** Both `needs-research`. Either re-evaluate priority based on current substrate fit, or do the research and let it inform the next set of shippable specs. BTS-21 (gh-aw integration) is concrete enough to scope in one session — could ship a research spike that produces a Draft spec or a "park / dismiss" decision. BTS-20 (workflow engine / QuantumBlack pattern) is research-shaped and may not converge in one session.
2. **Re-evaluate icebox** (2 stale items: BTS-163 release primitive, BTS-165 provider-onboarding). 60+ days old. `/idea review-icebox` worth a pass — may surface ship candidates or produce dismissals.
3. **Address the determinism finding from this session** (see Determinism Review below): word-boundary truncation in `derive-pr-title`. Small ship, ~5-line tweak, would make BTS-181's substrate cosmetically clean.
4. **Strategic pause.** Substrate is mature, backlog is research-only, stasis history is now persisted. A read-only `/radar` next session might surface direction shifts before more ships pile up.

## Context Notes

- **BTS-22 was a refresh, not a build.** Zach's framing — "old ticket, likely needs to be reviewed and refreshed to fit all of the changes that have happened to ccanvil over the past 2 weeks" — was correct. The original "multi-file specs/plans/checkpoints" framing turned out to be largely superseded by 2 weeks of Linear-as-backlog + single-file substrate maturity. The kernel of value left was stasis history, and the spec was scoped to that. Five things that the original BTS-22 framing implied but were correctly excluded: (a) multi-file specs (no observed pain — specs avg 70 LOC, max 141), (b) multi-file plans (same), (c) backfilling historical stases from git (forward-only is sufficient), (d) removing the legacy migrate-stasis-artifact helper (downstream nodes may still need it), (e) removing checkpoint references from `legacy-refs-scan` (defensive guard, costs nothing to keep).

- **Substrate compounding within a single session.** BTS-181 → BTS-22 was the tightest compounding loop observed yet: the substrate I shipped at minute ~30 paid off automatically at minute ~60. PR #104's title was correct-by-construction at activate time. This is the pattern the substrate-compounding memory describes, but the time scale is shrinking. Worth noting: each substrate ship reduces friction for the NEXT substrate ship in measurable ways now.

- **The `set -e` + `grep -m1` no-match pitfall.** Hit twice during BTS-22 implementation. `grep -m1 '^> Pattern:' file` returns non-zero when no match, which under `set -e` aborts the function before fallback logic can fire. Fix is mechanical (`|| true` after each grep). This is the kind of recurring bash gotcha that would be a candidate for a `bash-lint` substrate primitive — but the pattern is well-known and easily caught at first run, so the lift isn't justified.

- **Live-validation gate honored.** No live-API calls were required for either ship. BTS-181 was pure refactor + truncation. BTS-22 was pure file-write + drift-guards. Plan's "live-API validation gate" subsection correctly evaluated to "none required" for both.

- **PR title cosmetics from BTS-181's substrate.** The 80-char hard cap cut mid-word ("docs-c") on PRs #103 and #104 — both PRs whose specs open with long multi-clause sentences. The substrate is deterministic-correct; the cosmetic outcome is what the spec accepted under "Out of Scope" (configurable truncation policy). Captured as a determinism candidate below.

## Determinism Review

- **operations_reviewed:** ~14 (2 spec/plan/TDD cycles × ~5 lifecycle ops each, plus /idea triage, /recall, full-suite runs × 3, manual `gh pr edit` on PR #103, two-commit /stasis flow now under test).

- **candidates_found:** 1.

- **derive-pr-title-word-boundary.** `cmd_derive_pr_title` (BTS-181) caps the suffix at exactly 80 chars with no word-boundary awareness — produced mid-word truncation on PRs #103 (`...docs-c`) and #104 (`...feature_id>`). Spec accepted this under "Out of Scope" (configurable truncation policy). Should be: after the 80-char cap, walk backward to the nearest space or hyphen within ~8 chars; if none, accept the hard cut. Impact: low (cosmetic), but recurs on every PR with a verbose Summary opener — which BTS-181's dogfood + BTS-22's auto-application both confirm is most of them. ~5-line tweak inside the existing primitive. Will capture as a Linear idea below.

## Cross-Session Patterns

- **CONFIRMED RECURRING (positive — completion sweep, 4 sessions running):** the "capture-during-stasis → ship-next-session" cycle held again. The prior stasis (`e56f8e9`) flagged `activate-title-truncation` as the only determinism candidate; this session shipped it as BTS-181 in ~30 minutes. The cycle is now empirically robust at substrate-tier candidates: prior 4 stases each ended with 1+ candidates; each of the last 4 sessions opened with a clean shipping queue from those candidates.

- **CONFIRMED RECURRING: substrate compounding accelerating.** BTS-181 ship (~30 min) leveraged BTS-178's `assert-pr-title` indirectly (same call site refactored). BTS-22 ship (~45 min) leveraged BTS-181 immediately at activate time. Each ship was small (~50-200 LOC) AND each leveraged a primitive from a prior ship in this same session. Two-ship batch landed in roughly the time one substrate-tier ship took two weeks ago.

- **CONFIRMED RECURRING: skip-/review-on-trivial-diffs validates cleanly.** Both BTS-181 and BTS-22 skipped /review (substrate primitives + drift-guards in place). Neither surfaced defects post-merge. Memory `feedback_skip_review_on_trivial_diffs` is now empirically validated 4+ sessions running.

- **NEW (positive): refresh-old-tickets-before-shipping.** Zach's explicit guidance for BTS-22 — review and refresh the ticket given the past 2 weeks of substrate evolution — produced a smaller, sharper, ship-aligned spec. The original framing would have triggered a substrate-wide rewrite (multi-file specs/plans). The refreshed framing was a focused 10-AC ship. Generalizable: when a Linear ticket is >2 weeks old, do a substrate-fit-check before drafting the spec. Capture as memory candidate.

- **No recurring legacy-refs.** legacy-refs-scan returns empty (allowlist is up-to-date including the new `stasis-history.bats` entry).

- **No recurring audit-session findings.** This session's audit-session returns empty.

## Security Review

- **Two ships.** No new external attack surface introduced.
- BTS-181: pure refactor + truncation logic in shell. No new auth surface. No external paths.
- BTS-22: file-write primitive (`archive-stasis`) operating on project-local paths. New directory `docs/sessions/` is gitignored-aware (no `.gitignore` change required — the directory is committed history). No external surface. `cp` + `mkdir` on whitelisted paths only.
- Both substrate primitives respect the workspace fence (no paths outside the project).
- Verdict: **PASS**.

## Memory Candidates

- **NEW MEMORY: refresh-old-tickets-before-shipping.** When the user surfaces a Linear ticket older than ~2 weeks for shipping, check substrate-fit before drafting the spec. Recent ships may have superseded large parts of the original framing. Worked on BTS-22 — the original "multi-file specs/plans/checkpoints" framing was largely obsolete; the refreshed spec scoped to the residual real concern (stasis history) and shipped in one session. Without the refresh, the spec would have triggered a substrate-wide rewrite with no observed pain. The refresh is cheap (~5 min of analysis) and pays for itself immediately.

- **REINFORCE: feedback_dogfood_substrate_on_own_session_pr is real and tightening.** BTS-181 dogfooded against its own PR; BTS-22 dogfooded against the live `archive-stasis`. Both ships paid off within the same session. The pattern holds and the time scale is shrinking — BTS-181's substrate fired on BTS-22's activate at minute ~60. No new memory; reinforces the existing one.

- **REINFORCE: substrate-compounding cadence.** Two ships in ~75 minutes total. Backlog dropped from 4 → 2 (and the 2 remaining are P4 research-only). Substrate compounding is now an observable productivity multiplier; combined with the empty-actionable-backlog state, it suggests next sessions will shift from shipping cadence to research/strategy cadence.

Memories to save: **one new memory** — `feedback_refresh_old_tickets_before_shipping.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
