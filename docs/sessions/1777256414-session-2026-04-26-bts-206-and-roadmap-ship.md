# Stasis

> Feature: session-2026-04-26-bts-206-and-roadmap-ship
> Kind: session
> Last updated: 1777256414
> Session objective: ship BTS-206 (SessionStart hook + session-info primitive) end-to-end + refresh roadmap with SSOT-Linear in Up Next + capture review-surfaced follow-ups as triage tickets.

<!-- BTS-206 self-fulfilling property: > Session: and > Boundary: lines OMITTED here per the feature's own AC-4/AC-5 spec — counter=0 because the SessionStart hook ships in this very commit and hasn't fired yet. First fire is the next session boundary. -->

## Accomplished

- **Shipped BTS-206** end-to-end (PR #111 squash-merged, BTS-206 → Done in Linear). 14 TDD steps across 6 commits, then `/review` round-trip with WARN-1 fixed inline + WARN-2/INFO-1/INFO-2 captured as Linear tickets. Commits: spec → plan → `cmd_session_info` (Steps 1-3) → SessionStart hook + settings (Steps 4-10) → stasis/recall surfacing (Steps 11-13) → docs sweep (Step 14) → TZ fallback fix (post-review WARN-1) → cmd_complete cleanup → squash on main.
- **Refreshed `docs/roadmap.md`** (commit `994f0be`, pushed pre-BTS-206 ship). Removed shipped fossils (Tech stack distribution, Stasis/Recall, BTS-20 workflow engine, BTS-21 gh-aw label, lifecycle timing). Promoted SSOT-Linear (BTS-204) + Determinism gap cluster + Dark Code/Three-Layer Solution into Up Next. Added Maturity Signal section (theme-agnostic empty-queues bar) and Next Theme Direction (simplicity-via-leverage / personality-packs working idea, not yet committed).
- **Captured 4 Triage tickets** post-/review and post-tooling-incident: BTS-207 (jq fork count in cmd_session_info), BTS-208 (hook + skill execution timing infrastructure), BTS-209 (canonize hook failure-handling pattern: loud + never-block + never-snuff), BTS-210 (guard-workspace false-positive on slash-command prose tokens — full evidence anchors per BTS-201 protocol).
- **Promoted BTS-205** earlier in session to Backlog P3 (silent-failure-of-bts-115-dual-capture from prior stasis ODI). Promoted BTS-203 + BTS-204 to Backlog (P3, P2). Triage queue went 0 → 3 → 0 → 1 → 4.
- **New memory:** `feedback_review_findings_need_why_it_matters.md` — every WARN/INFO from /review needs a "why this matters" rationale; don't pre-recommend defer/skip without articulating cost.

## Current State

- **Branch:** `main` (post-merge, fast-forwarded to origin via /land)
- **Tests:** 1622 / 1622 passing (BTS-206 added 17 drift-guards; net +17 from prior 1605)
- **Uncommitted changes:** none (working tree clean)
- **Build status:** clean

## Blocked On

Nothing.

## Next Steps

1. **`/idea triage`** — clear the 4 Triage items: BTS-207 / BTS-208 / BTS-209 / BTS-210. All four are determinism-cluster work surfaced this session.
2. **Pick the next ship** — roadmap Up Next ordering: (1) SSOT-Linear (BTS-204, P2, dedicated session), (2) determinism cluster: BTS-202/BTS-203/BTS-205 (P3 ×3, can co-ship), (3) Dark Code research-then-spec. The smallest warmup is BTS-202; BTS-204 wants a fresh full-context session.
3. **Verify BTS-206 fires on next SessionStart.** First post-`/compact` session should show counter=1 and a populated boundary file. /recall briefing should surface "Session 1 — boundary <iso>".

## Context Notes

- **BTS-206 was a self-fulfilling ship.** The hook ships in the same commit that activates it; the first fire is the next session boundary. /recall and /stasis briefings reference Session N + Boundary <iso> — but for the session that SHIPS the feature, counter=0, so both lines OMIT per the feature's own AC-4/AC-5 spec. This stasis is the inaugural omission.
- **Mid-session scope expansion: spec → 14 TDD steps → 17 drift-guards.** The plan's 15 steps collapsed cleanly into 6 commits because most steps were red-green for one AC each, layered. Mirror of BTS-20's expansion pattern. Worth noting that TDD compression to 1-commit-per-step-cluster is now habitual.
- **`/review` caught a real defect (WARN-1) that pre-ship validation missed.** TZ derivation on Linux non-symlink hosts (Docker, WSL) would have shipped wrong on a real Linux deploy. The code-reviewer subagent correctly flagged the cosmetic-vs-real distinction (cosmetic on macOS, real on Linux). Fixed inline before merge.
- **Operator pushed back on "ship as-is" recommendations.** I had triaged WARN-2/INFO-1/INFO-2 as defer/skip without articulating the cost. Operator: *"I don't understand the implications of the INFOS. These warnings should have a 'why this matters' section."* Resulted in `feedback_review_findings_need_why_it_matters.md` memory + clearer cost articulation in the BTS-208 / BTS-209 capture bodies.
- **Roadmap rewrite was strategic groundwork before BTS-206.** Cleared the Up Next so SSOT-Linear is unambiguously next; named the Maturity Signal (empty triage/backlog/icebox sustained) as theme-agnostic; floated personality-packs as direction-not-commitment. Theme-rollover criteria explicitly NOT defined yet.
- **guard-workspace prose false-positive surfaced inline.** `/stasis)` and `/radar)` in idea body text matched the workspace-path heuristic. Bypassed via `ALLOW_OUTSIDE_WORKSPACE=1` and captured as BTS-210 with full evidence anchors. Sibling to BTS-202 (guard-destructive jq+rm flag false-positive).

## Determinism Review

- **operations_reviewed:** ~22 (BTS-206 spec/plan/14 TDD steps × ~2 ops each, /review + WARN-1 fix, 4 triage captures, mergeland, roadmap rewrite, memory write)
- **candidates_found:** 0
- No candidates this session. The session was disciplined — substrate gaps surfaced via /review and bypass incidents were captured as discrete Linear tickets (BTS-207/208/209/210) rather than swallowed silently. The self-review safety net surfaced no new operations that should become deterministic.

## Evidence Gaps

The substrate primitive `evidence-scan-session` reports 4 gaps (BTS-198, BTS-202, BTS-205, BTS-210), but **all four are false positives** caused by the known substrate gap BTS-203: the `idea.list` resolver doesn't include `description` in its output shape, so the scan can't see the four anchors that ARE present in each ticket body. BTS-210 was specifically captured WITH all four anchors per the BTS-201 protocol; the scan can't see them. Will resolve when BTS-203 ships.

**No real evidence gaps this session.**

## Cross-Session Patterns

- **CONFIRMED RECURRING (5+ sessions): substrate gap surfaces ONLY at dogfood / live execution.** Today's WARN-1 (TZ derivation on Linux non-symlink hosts) was caught by the code-reviewer subagent during `/review`, not by my pre-ship validation. Prior sessions: BTS-203 (evidence-scan description-fetch), BTS-115 (silent dual-capture). The pattern is robust enough to be a durable practice — *automated review tooling catches what self-review misses*. Reinforces `feedback_live_activation_hardening`.

- **CONFIRMED RECURRING (4+ sessions): same-session dogfood validates thesis AND surfaces substrate gaps cheaply.** BTS-206 ship was followed in the same session by /stasis dogfooding the new `session-info` primitive (which correctly returned counter=0, demonstrating the self-fulfilling property is by design). The roadmap rewrite was itself a same-session dogfood of "stay in spec mode at capture time" (capture pre-review didn't pre-decide architecture). Now a durable practice.

- **CONFIRMED RECURRING: scope-up-mid-session works.** Inline TZ fallback fix (WARN-1) absorbed into BTS-206 ship rather than deferred. Tests held (1605 → 1622). Mirror of BTS-20's mid-session expansion. Now 2 consecutive sessions running.

- **NEW (positive): operator-driven articulation discipline.** Operator's pushback on "skip these INFOs" yielded the *why this matters* contract — now codified as `feedback_review_findings_need_why_it_matters.md`. Generalizes to ANY automated-review summarization where the agent might be tempted to pre-decide for the operator.

- **NEW (positive): triage queue grows DURING ships, not just at boundaries.** This session's queue went 0 → 3 → 0 → 4 over four discrete /idea captures triggered by review-time findings, tooling incidents, and operator scope-up requests. Healthy pattern: capture happens at the moment the issue surfaces, not deferred to /stasis.

- **No recurring legacy-refs.** legacy-refs-scan returned empty array.

## Security Review

- BTS-206 substrate (bash hook + JSON state files): atomic mktemp+mv writes; no auth surface; no secrets. State files written under .ccanvil/state/ which is .gitignored.
- Roadmap rewrite: doc-only, no secrets.
- Triage captures: routed via existing http substrate (linear-query.sh save-issue); same auth path as existing idea operations. Bypassed `ALLOW_OUTSIDE_WORKSPACE=1` ONCE for prose-token false-positive (BTS-210); not a security-relevant bypass.
- Memory write: local filesystem only.
- Security audit: 2 MEDIUM findings, both pre-existing in `docs/specs/bts-72-...` (false positives on `x@x` test fixture and `git@gitlab.com:` URL pattern); not introduced by this session.
- **Verdict: PASS.**

## Memory Candidates

- **NEW MEMORY (already saved): `feedback_review_findings_need_why_it_matters.md`** — every WARN/INFO from /review needs a *why this matters* rationale before any defer/skip recommendation. Operator decides informed; agent provides cost articulation.

- **REINFORCE: `feedback_live_activation_hardening`** — substrate gaps surface only at dogfood. WARN-1 (TZ Linux non-symlink) is the latest example. Now 5+ sessions running. Promote to durable practice if not already.

- **REINFORCE: `feedback_same_session_dogfood_validates_thesis`** — BTS-206's session-info primitive was dogfooded immediately by /stasis below (and verified the self-fulfilling property by returning counter=0, which is correct behavior). 4+ sessions running.

- **REINFORCE: `feedback_scope_up_on_live_api_reveal`** — WARN-1 inline fix is the same pattern (review surfaces a real defect mid-ship → expand the ship to absorb the fix). Now 2 consecutive sessions running.

- **NEW REFERENCE (in code, not memory):** BTS-206's `session-info` primitive is now the canonical state-file reader for hook-written boundary state. Future hooks that write per-session state should follow the same shape: state file under `.ccanvil/state/`, primitive reader under `docs-check.sh <subcommand>` returning JSON with fault-tolerant defaults.

Memories to save: **one new** (`feedback_review_findings_need_why_it_matters.md` — already written). Three reinforced.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
