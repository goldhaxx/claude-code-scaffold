# Stasis

> Feature: session-2026-04-26-bts-20-ship
> Kind: session
> Last updated: 1777244400
> Session objective: Ship BTS-20 (unified lifecycle-state primitive) end-to-end. After mid-session course correction, expand scope to absorb full skill migration + cmd_recommend refactor. Then capture SSOT-Linear as BTS-204 in spec mode.

## Accomplished

**One major ship + one strategic spec capture + two memory crystallizations.**

- **BTS-20 SHIPPED (PR #110, merged, landed, auto-closed).** Unified `lifecycle-state` substrate primitive composing `cmd_validate` + git/marker state into `{state, validate_result, legal_next_actions[], blockers[], suggestions[]}`. Codified transition graph in `.ccanvil/templates/lifecycle-graph.json` (10 states, 10 edges). Migrated ALL state-parse consumers in one ship: `/recall`, `/pr`, `/stasis`, `/spec`. `/plan` gained explicit pre-flight gate (refuses unless state ∈ {spec-activated, plan-written}). `cmd_recommend` refactored to delegate state derivation to `cmd_lifecycle_state`. Two code-reviewer passes (Sonnet); 4 WARNs addressed inline. Tests: 1575 → 1605 (+30; 14 lifecycle-state.bats + 6 recall-skill.bats + 10 lifecycle-skill-migrations.bats).

- **Mid-session scope expansion (operator-driven).** Original spec called Session-1 of multi-session ship (primitive + transition-graph + /recall only). After PR #110's first push, user pushed back on the "out of scope" deferrals: full skill migration, pre-flight gap audit, cmd_recommend refactor should have been in scope. Refresh-and-expand: rewrote spec ACs from 10 → 16, absorbed all out-of-scope items, shipped them in the same PR. Did NOT merge until expansion was complete. This reinforces `feedback_substrate_driven_pivot` (now 4x consecutive sessions) and adds a new generalizable principle: when substrate is mature and drift-guards are robust, scoping conservatively is the wrong default.

- **BTS-203 captured (Triage).** ODI-1 from prior stasis (`evidence-scan-session-needs-description-fetch`) had no Linear ticket — operator asked, I checked, BTS-115 dual-capture had silently failed (no entry in pending log either). Captured now via http substrate. Substrate gap: dual-capture failure is itself silent — should fail loud or queue. Captured as part of BTS-203's body.

- **BTS-204 captured (Triage) — SSOT-Linear effort.** Initial body had architectural shape, migration plan, friction mitigations, substrate impact analysis — operator course-corrected: "purely in spec mode. dial in the spec, jtbd, the functional side before we dive into its implementation." Rewrote in pure spec mode: Problem → JTBD → 10 functional ACs (operator-perspective) → 5 explicit Open Questions for spec session → Out of Scope → Anchors. Captured `feedback_capture_in_spec_mode.md` as the generalizable rule.

- **Memory crystallized (3 entries).**
  - NEW: `feedback_capture_in_spec_mode.md` — when capturing a major-effort ticket, stay in spec mode; defer architectural shape, migration plan, friction mitigations to the spec session.
  - NEW: `project_ssot_history_tensions.md` — captures the two operator-flagged history-loss tensions (git-tracked spec evolution; lifecycle docs backup/access) that BTS-204's spec session must address. Linked to BTS-204.
  - REINFORCED: `feedback_substrate_driven_pivot` (4 consecutive sessions running).

## Current State

- **Branch:** `main` at `fb518ad` (BTS-20 squash-merge); in sync with `origin/main`.
- **Tests:** **1605 / 1605 green** (no change post-land; expanded from 1575 baseline at session start).
- **Uncommitted changes:** none (per `git status`; this stasis will be the only commit).
- **Build status:** clean.
- **Active spec:** none — between features.
- **Permissions audit:** `danger=0`, `promote-review.total=0`. Clean.
- **Linear backlog (canonical via `backlog.list`):** **9 items.** 1 P3 (BTS-202 — guard-destructive cross-token regex) + 8 P4 (BTS-21 watchdog node sync drift + BTS-22 docs strategy + BTS-191..197 + others).
- **Linear Triage queue:** **2** — BTS-203 (Determinism: evidence-scan-session-needs-description-fetch), BTS-204 (SSOT-Linear). Both captured this session.
- **Watchdog status:** loaded from prior session's activation; next fire scheduled. BTS-200 self-verification subsection is in effect.

## Blocked On

- Nothing. BTS-20 shipped clean; substrate fan-in for SSOT-Linear is now in place; SSOT-Linear is captured and ready for its own spec session.

## Next Steps

**Operator's stated next move: clear the backlog, dedicate a session to BTS-204 SSOT eventually.**

Recommended sequence:

1. **`/recall`** to orient. Triage queue is 2; backlog is 9.
2. **Triage BTS-203 + BTS-204.** Both are in Triage from this session. BTS-203 is small substrate fix (P3 candidate — pairs naturally with BTS-202). BTS-204 is multi-session major effort (P3 candidate — schedule a dedicated session).
3. **Pick from current backlog:**
   - **BTS-202 (P3):** smaller-runway substrate fix to guard-destructive cross-token rm-rf regex. ~30 min ship per prior stasis. Could pair with BTS-203 (also a substrate fix to evidence-scan-session) for a "hardening" session.
   - **BTS-22 (Medium, needs-research):** docs directory strategy. Some of this likely subsumed by BTS-204; refresh against current substrate before drafting.
   - **BTS-21 (P4, watchdog drift sync):** BTS-191..197 — operator-mediated `ccanvil-pull` per node. Parallel work to feature shipping; do in a dedicated sync window.
4. **OR pivot to BTS-204 SSOT-Linear if ready for the dedicated session.** Per the captured spec, this is a major effort with 5 explicit open questions to resolve. Schedule it as a single super-long session per operator's prior framing.

## Context Notes

- **The user explicitly course-corrected on captured-ticket-shape.** Initial BTS-204 body included migration plan + architectural shape + friction analysis. User: "purely in spec mode." Rewrote → problem + JTBD + functional ACs + open questions. Memory `feedback_capture_in_spec_mode.md` codifies this rule.

- **Scope-up-on-reveal worked cleanly mid-session.** BTS-20 PR #110 was already pushed and reviewed when operator pushed back on the deferrals. Expanded the spec in place, added 6 new ACs, implemented all migrations, committed as a second commit on the same branch. PR body updated to reflect new scope. This is mirror-image of `feedback_scope_down_on_reveal` and complements `feedback_scope_up_on_live_api_reveal`.

- **BTS-115 dual-capture had a silent failure mode.** ODI-1 from prior stasis (`evidence-scan-session-needs-description-fetch`) was supposed to be auto-captured by /stasis's BTS-115 step. It wasn't, AND nothing went into the pending log either. Operator caught it by asking "does ODI 1 have a ticket?" Substrate gap to fix: dual-capture failures must either fail loud or queue to pending — silent drop is unacceptable.

- **The lifecycle-state envelope's `validate_result` field landed late.** Code-reviewer WARN-1 surfaced the double-`cmd_validate` call in cmd_recommend's blocked path. Fix: carry `validate_result` through the envelope so consumers can map without re-running validate. One-liner. Worth noting because it's a pattern: any envelope that swallows underlying state should preserve the underlying type-discriminator for consumers that need to fan out.

- **Code-review at PR #110 was uniquely valuable post-expansion.** Two passes total: one after Session-1 commit, one after expansion commit. Each surfaced 1-2 WARNs. Without the second pass, the double-validate inefficiency would have shipped. Substrate-tier ships warrant /review even when drift-guards are green — the reviewer catches semantic-correctness issues drift-guards can't.

## Determinism Review

- **operations_reviewed:** ~28 (BTS-20 spec/plan/TDD across 16 ACs × ~6 lifecycle ops; BTS-203 + BTS-204 captures; spec rewrite for BTS-204; PR review + fix cycles × 2; merge + land + auto-close; memory writes × 3; full-suite runs × 3).

- **candidates_found:** 1.

- **silent-failure-of-bts-115-dual-capture.** When /stasis's dual-capture step (Step in skill prose) fails to capture a determinism candidate as a Linear idea, the failure is currently silent on local-routed nodes (skipped) AND on Linear-routed nodes if the http call AND the pending-log fallback both fail. Today's session caught this: ODI-1 from prior stasis had no Linear ticket and no pending entry. Should be: dual-capture failure ALWAYS queues to pending log (which it should already do per the skill prose), and the absence of the captured ticket on the next /recall should surface as a "carry-forward determinism candidate" line in the briefing. Impact: medium — silent drops mean determinism candidates evaporate when capture transiently fails.

## Evidence Gaps

The substrate primitive `evidence-scan-session` reports 2 gaps (BTS-202 and BTS-198), but **both are false positives** caused by the same known substrate gap (BTS-203, captured this session): `idea.list` resolver doesn't include `description` in its output shape, so the scan can't see the four anchors that ARE present in both ticket bodies. This is the same false-positive pattern the prior stasis flagged. Will resolve when BTS-203 ships.

**No real evidence gaps this session.**

## Cross-Session Patterns

- **CONFIRMED RECURRING (4 sessions running): substrate-driven-pivot.** Yesterday: BTS-21 (gh-aw → launchd, refresh-twice). Two sessions ago: BTS-20 substrate-fit refresh (centralized engine → distributed substrate). Today: BTS-20 implementation absorbed mid-session expansion (Session-1 → full migration). Pattern is robust at 4x — formally promoted to durable practice. Memory already captures this.

- **CONFIRMED RECURRING: same-session dogfood.** BTS-20 ship was followed by SSOT-Linear capture in the same session — exercising BTS-20's lifecycle-state primitive on its own ship. Then the BTS-204 spec-mode-rewrite IS itself a same-session dogfood of the protocol that says "stay in spec mode at capture time." Three sessions running for this pattern.

- **CONFIRMED RECURRING: substrate gap surfaces ONLY at dogfood.** BTS-203 (evidence-scan-session description-fetch gap) was discovered via stasis-time dogfood prior session. Today: BTS-115 silent dual-capture-failure was discovered when operator manually asked about ODI-1. Both gaps would have stayed hidden indefinitely without active live-execution against real data. Reinforces `feedback_live_activation_hardening`.

- **NEW (positive): scope-up-mid-session works.** BTS-20 expansion absorbed previously-out-of-scope items into the same ship after operator pushback. Tests (1594 → 1605) caught no regressions across migrations. Drift-guards held. Tradeoff: PR #110 has two distinct commits/expansions — the squash-merge collapses them, but the PR body documents both. Worth doing again when substrate maturity supports it.

- **NEW (positive): capture-in-spec-mode discipline.** Operator's course-correction on BTS-204 ("purely in spec mode") IS a generalizable rule, now codified as `feedback_capture_in_spec_mode.md`. Pre-deciding architecture at capture-time anchors the spec session against substrate-state-of-the-moment. Mirror of the existing substrate-driven-pivot principle but at the capture-stage instead of the spec-stage.

- **No recurring legacy-refs.** legacy-refs-scan returned empty count.

## Security Review

- BTS-20 is substrate code (bash + JSON data); new function `cmd_lifecycle_state` reads validate output + filesystem markers + idea-count. No new auth surface.
- BTS-203 + BTS-204 captured via http substrate (linear-query.sh save-issue); same auth path as existing idea operations.
- No secrets, tokens, PII, credentials introduced. `.env` continues gitignored.
- Memory writes are local-filesystem only.
- **Verdict: PASS.**

## Memory Candidates

- **NEW MEMORY: `feedback_capture_in_spec_mode.md`** (already saved). Captured ticket bodies for major efforts stay in spec mode (problem + JTBD + ACs + open questions). Architectural shape, migration phases, friction mitigations belong to the dedicated spec session.

- **REINFORCE: `feedback_substrate_driven_pivot`** — now 4 consecutive sessions running. Promote to durable practice; refresh against current substrate before any spec or major scope-affecting decision.

- **REINFORCE: `feedback_live_activation_hardening`** — substrate gaps surface only at dogfood. Today's BTS-115 silent-failure was the latest example. Now ~4-5 sessions running.

- **REINFORCE: `project_ssot_history_tensions.md`** (already linked to BTS-204). The two history-loss concerns must be addressed at SSOT spec time; now anchored on a real ticket.

- **NEW REFERENCE: BTS-20 is the canonical substrate fan-in for state-parsing.** Single primitive (`cmd_lifecycle_state`) is the only function reading spec/plan/stasis files. SSOT-Linear becomes a single-function change because of this. Future state-parsing additions go to lifecycle-state, not new ad-hoc parses.

Memories to save: **none new** beyond what was already captured this session. Three reinforced.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
