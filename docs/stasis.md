# Stasis

> Feature: session-2026-04-27-bts-204-ssot-linear-ship
> Kind: session
> Last updated: 1777267442
> Session: 1
> Boundary: 2026-04-26T19:26:29-07:00
> Session objective: ship BTS-204 (SSOT-Linear via Documents) end-to-end across 8 phases — substrate, routing, skill migration, archive-at-complete, PR body embed, bidirectional migration tool, concurrent-edit safety. Address /review findings inline + capture overflow as triage.

## Accomplished

- **Shipped BTS-204 end-to-end** (PR #112 squash-merged, BTS-204 → Done in Linear). Single session: spec → activate → plan → 8 phases of TDD → /review → merge + /land. 17 commits squashed. The largest single ship in the recent backlog arc.
- **Architectural pivot mid-spec from operator pushback**: original plan stored specs/plans/stasis in `Issue.description`. Operator demanded full Linear API research before committing. Research surfaced **Linear Documents** as a structurally cleaner home (per-document version history via `documentContentHistory`, native comment-as-review threads, project-scoped parent for session-stasis, caller-supplied UUID via `DocumentCreateInput.id` for idempotency). Pivoted entire architecture to Documents before any code was written. Operator's intuition on session-stasis was validated: project-parented Document is the structurally correct home, not a synthetic "session-state" issue.
- **Provider modularity codified as constraint**: operator added "this should be configured as a provider enhancement... downstream projects start as local and may add Linear later." This shaped AC-1/AC-2 — `integrations.routing.{spec,plan,stasis}` keys, default "local", zero behavior change on local-routed nodes. The fast-path `_has_any_linear_route` skips ALL Linear querying when no key is set; regression-test asserts a fail-stub of curl is never invoked on local nodes.
- **Phase 1 substrate live-validated against api.linear.app/graphql** (per `feedback_validate_plan_flagged_live_api.md`). Caught + fixed schema bug `actor` → `actorIds` on `documentContentHistory`. Confirmed Linear's markdown normalizer auto-linkifies filename-shaped tokens (`linear-query.sh` → `[linear-query.sh](<http://linear-query.sh>)`) on top of the BTS-125 backtick-bold strip — a substrate-wide caveat documented in spec.
- **/review surfaced 7 findings; 6 fixed inline + 3 captured as follow-up tickets**: BTS-213 (FIX: /spec skill not migrated — silent inconsistency on Linear-routed nodes; full evidence anchors), BTS-214 (Determinism: 6 serial API calls in `_complete_archive_linear`), BTS-215 (docs-check.sh usage string out of sync with dispatch). Each carries "why this matters" articulation per `feedback_review_findings_need_why_it_matters.md`.
- **Discovered + captured 2 substrate-correctness bugs during pre-BTS-204 /radar**: BTS-211 (`operations.sh exec` doesn't execute http-mechanism commands — silent break since BTS-175), BTS-212 (`docs-check.sh` subcommands silently fall through on unknown flags). Both promoted to Backlog P3.

## Current State

- **Branch:** `main` (post-merge, fast-forwarded to origin)
- **Tests:** 1681 / 1681 passing (1622 baseline → +59 SSOT-Linear drift-guards)
- **Uncommitted changes:** none
- **Build status:** clean

## Blocked On

Nothing.

## Next Steps

1. **`/idea triage`** — clear the 3 Triage items (BTS-213, BTS-214, BTS-215). All three are BTS-204 follow-ups surfaced this session.
2. **Pick the next ship** — Up Next options:
   - **BTS-213** is the most coherent next ship — it completes the SSOT-Linear story by migrating `/spec` so Linear-routed nodes work end-to-end without the half-broken state.
   - Alternative warmups: BTS-202 / BTS-211 (single-file substrate fixes).
   - Strategic: Dark Code / Three-Layer Solution (still research-pending).
3. **Verify BTS-204 via real onboarding**: configure a downstream node with `routing.spec=linear` (after BTS-213) and walk the full lifecycle on Linear Documents.

## Context Notes

- **Session arc**: a sequence of 5 distinct surfaces — recall → /idea triage (4 items) → /radar findings + capture (BTS-211/212 from /radar's own bash failures) → research-driven architectural pivot on BTS-204 → 8-phase TDD ship → /review → ship. Each surface fed the next.
- **Operator demanded research before commit**. When I proposed Issue.description as the SSOT home for OQ4, operator said: *"Research Linear document functionality to its fullest extent. Read the Linear documentation on Documents and understand how they can be used in the GraphQL API. Take the full Linear GraphQL API spec into context."* The research agent's findings (Documents as first-class entity, per-doc history, project parent option, caller-supplied UUID idempotency) materially changed the architecture — pivoted ALL four artifact types to Documents, not just session-stasis. Validates: when the operator flags a question requiring research, hold the spec until research lands.
- **/review of 17-commit ship caught real defects**. WARN-2 (swallowed GraphQL errors), WARN-4 (stasis skill commit step still references `docs/stasis.md` after artifact-write — silent confusion on Linear-routed nodes), W-1 (/spec migration deferred → silent inconsistency). Operator-driven articulation discipline (memory) held: every WARN/INFO got a "why this matters" rationale; 6 fixed inline, 3 captured with full operational cost spelled out.
- **Scope-down-on-reveal worked**. Mid-Phase 4, realized /spec migration required deeper activate-flow refactoring (local archive → active spec asymmetry doesn't map to Linear's single-Document model). Captured BTS-213 with full bug-shape evidence anchors instead of forcing it into this ship. Honest narrowing > partial completion.
- **Live-validation gate reinforced**. Phase 1 stub tests passed; live test caught the `actor` → `actorIds` schema typo in document-history that NO stub could detect (stub accepts any GraphQL body shape). 5+ sessions of this pattern now durable.
- **Substrate-driven-pivot pattern**: BTS-204 was captured weeks ago; substrate had materially shifted (BTS-20 lifecycle-state primitive, BTS-22 archive pattern, BTS-164/166 http substrate, BTS-206 session-info). The substrate-audit step at the start of the spec session re-grounded the architecture against current reality — `operations.sh` already had spec.read/write/etc verbs (just bash-routed); routing config was structurally ready; archive pattern generalized cleanly. Spec was much smaller than if I'd worked from the original ticket framing.

## Determinism Review

- **operations_reviewed:** ~40 (BTS-204 ship: 8 phases × ~3 ops each + /radar walkthrough + 4 triage operations + /review captures + 2 substrate-bug captures + spec-write + plan-write + activate + pr-cleanup + push + merge + /land)
- **candidates_found:** 0
- No candidates this session. The session was disciplined — substrate gaps surfaced via /review and /radar bash failures were captured as discrete Linear tickets (BTS-211/212/213/214/215) with full evidence anchors, not swallowed silently. No recurring stochastic operations identified. Provider-aware artifact-write/read primitives consolidated what would otherwise have been duplicate orchestration logic across 4 skills.

## Evidence Gaps

The substrate primitive `evidence-scan-session` reports 3 gaps (BTS-205, BTS-209, BTS-210), but **all three are false positives** caused by the known substrate gap BTS-203: the `idea.list` resolver doesn't include `description` in its output shape, so the scan can't see the four anchors that ARE present in each ticket body. BTS-205/209/210 were captured WITH full evidence anchors per the BTS-201 protocol; the scan can't see them. Will resolve when BTS-203 ships.

**No real evidence gaps this session.**

## Cross-Session Patterns

- **CONFIRMED RECURRING (5+ sessions): substrate gap surfaces ONLY at dogfood / live execution.** This session's `actor` → `actorIds` schema bug was caught by Phase 1 live-validation; stub tests passed. Prior sessions: WARN-1 in BTS-206 (TZ derivation on Linux non-symlink), BTS-203 (evidence-scan description-fetch), BTS-115 (silent dual-capture). The pattern is now durably codified — `feedback_live_activation_hardening` should be cited as the canonical justification for the live-API gate in `tdd.md`.

- **CONFIRMED RECURRING (5+ sessions): operator-driven articulation discipline.** /review WARN/INFO findings ALL came with cost-articulated "why this matters" — not just for the captured triage tickets but for the inline fixes too. The memory written in BTS-206 ship is now habitual contract.

- **CONFIRMED RECURRING (3+ sessions): scope-up / scope-down on reveal.** WARN-1 fix in BTS-206 was scope-up (absorb mid-ship); BTS-213 capture this session was scope-down (defer cleanly with full evidence). Both decisions made fast and explicit, not silent.

- **NEW (positive): research-driven architectural pivot.** Operator demanding Linear API research before committing to Issue.description-as-SSOT changed the entire architecture. Generalizes to ANY major ship where the substrate or external-API contract is uncertain — research first, spec second, code third. Worth a memory: `feedback_research_before_architectural_commit`.

- **NEW (positive): single-session 8-phase ship.** This is the largest single ship in the arc (17 commits, +59 drift-guards, 1622 → 1681 tests). Not a pattern to seek; it worked here because the substrate had materially matured (BTS-164/166/167 http stack, BTS-22 archive, BTS-206 session-info all shipped), and the architecture was clear post-research. Don't blindly target "ship everything in one session" — target shipping when the substrate is ready.

- **No recurring legacy-refs.** legacy-refs-scan returned empty array.

## Security Review

- BTS-204 substrate: bash + GraphQL via existing http machinery (BTS-164). No new auth surfaces. Linear API key reused from existing config. Document mutations carry user-content via stdin-JSON (no shell-injection); cache files written under `.ccanvil/state/` (gitignored, regenerable).
- Live test created + trashed 2 test Documents in Linear's ccanvil project (`36eb3962-...` and `bcef1f0a-...`). Both confirmed trashed via `trash-document` returning `{"success": true}`.
- New env-var escape: `ALLOW_CONCURRENT_EDIT_OVERRIDE=1` for Phase 7 force-write. Documented in error message + Phase 7 commit body. Same pattern as `ALLOW_DESTRUCTIVE=1` / `ALLOW_OUTSIDE_WORKSPACE=1` — operator-typed bypass tokens.
- /pr body embeds spec content in PR description. Not a secret-leak surface: specs don't carry credentials; PR descriptions are visible to repo collaborators only.
- **Verdict: PASS.**

## Memory Candidates

- **NEW MEMORY: `feedback_research_before_architectural_commit`** — when the operator flags a major-architecture question that depends on external API or substrate behavior, hold spec writing until research lands. Anchored on BTS-204: operator explicitly demanded Linear API + Documents research before agreeing to OQ4 resolution. Research changed the answer for ALL FOUR artifact types, not just session-stasis. Worth saving.

- **REINFORCE: `feedback_live_activation_hardening`** — substrate gaps surface only at dogfood. BTS-204 Phase 1 `actor`/`actorIds` schema bug. Now 5+ sessions running. Already saved; this is the latest data point.

- **REINFORCE: `feedback_review_findings_need_why_it_matters`** — every WARN/INFO from this session's /review came with "why this matters" rationale; 3 promoted to triage tickets carried that articulation forward. Now 2+ sessions of explicit application; durable practice.

- **REINFORCE: `feedback_validate_plan_flagged_live_api`** — Phase 1 plan flagged live-API contract risk; live test caught what stubs missed. Pattern held.

- **NEW REFERENCE (in code, not memory)**: BTS-204's `cmd_artifact_read` / `cmd_artifact_write` are now the canonical provider-aware lifecycle artifact IO primitives. Future skills that need to read/write spec/plan/stasis content should dispatch through these rather than hardcoding file paths or Linear calls.

Memories to save: **one new** (`feedback_research_before_architectural_commit`). Three reinforced.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
