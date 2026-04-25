# Stasis

> Feature: session-2026-04-25-release-primitive-capture
> Kind: session
> Last updated: 1777136656
> Session objective: Recall after the BTS-149 dogfood walk, then take a strategic backlog-grouping question to a fully-matured Linear capture without starting implementation. Defer execution until existing Linear backlog drains.

## Accomplished

- **`/recall` produced clean cold-start orientation.** Lifecycle aligned, audit-session 0 findings, DANGER 0, no untriaged ideas, no carry-forward stochastic candidates beyond what was already ticketed (BTS-159/160/161/162). Recall-then-radar produced a 4-cluster groupings view across the carry-forward backlog.
- **Strategic-design conversation on the "release" primitive.** Zach surfaced a missing layer between single-ticket and Linear initiative: a tactical work grouping that ships as a coherent unit and may span sessions. Three implementation paths were proposed and traded off (A: Linear parent label only; B: project-local docs/releases artifact; C: hybrid provider-aware). Zach picked **C** with explicit emphasis: provider-aware integration with `ccanvil.json` routing, mandatory provider migration when a project changes providers (no cross-provider drift at any point in time).
- **BTS-163 captured** (Linear, Triage state, "Release primitive: provider-aware tactical work groupings"). Body carries: problem, why-now, full hybrid Path C design, 5 confirmed decisions including provider-migration mandate, 7-child spec breakdown (~3 working sessions), self-application context (Release-system v1 will itself be a release), `/radar` surface changes (Active + Proposed sections), sequencing constraint, out-of-scope guardrails, and references to BTS-158 plus governing memories.
- **Drainage check scheduled** (cron job `62ed334a`, fires Monday 2026-05-11 09:13 local). Self-rearming biweekly one-shot: queries Linear backlog (Triage + Backlog states in project ccanvil); if 0, surfaces BTS-163 readiness; if not, re-arms for two weeks later. Reference count at scheduling time: 21. **Caveat:** scheduler echoed "Session-only" despite `durable: true` flag. Verify `.claude/scheduled_tasks.json` on next `/recall`; if job missing, request re-arm.

## Current State

- **Branch:** `main` at `b3e5950` (last session's stasis commit).
- **Tests:** **1101 / 1101 green** via `bats-report.sh --parallel` (unchanged — no source mutations this session).
- **Uncommitted changes:** none.
- **Build status:** clean.
- **Context budget:** still WARNING from prior session (~81% of 8000-token budget); no rule files touched this session.
- **Permissions audit:** danger=0, promote-review.total=0 (still in clean state from BTS-149 walk).
- **Specs archive:** 69 Complete (unchanged).
- **Linear:** 11 new ideas in Triage as of session end (BTS-153 through BTS-163).

## Blocked On

- BTS-163 implementation is **explicitly deferred** until Linear backlog (Triage + Backlog) reaches 0 tickets. Reference count: 21. Drainage check `62ed334a` will surface the unblock.

## Next Steps

Priority-ordered, smallest first:

1. **BTS-160** — Fix BSD mktemp template in `/permissions-review` skill prose (High, ~5 min). Carry-forward from last session; still the smallest opener.
2. **BTS-156** — Gate `rm -rf` in guard-destructive.sh (Urgent). Most acute risk surfaced in last session's walk.
3. **BTS-155 / BTS-157** — workspace-fence trio under BTS-158 umbrella (Urgent).
4. **BTS-159 / BTS-161** — `/permissions-review` substrate codification (Medium).
5. **BTS-162** — `/idea --parent` and capture-from-context (Medium).
6. **BTS-150 / BTS-151 / BTS-152** — carryover (classifier semantics, command-string false positive, per-finding allowlist).
7. **Tech stack distribution** — roadmap "Up Next #1".
8. **BTS-163** — DEFERRED until backlog drains; surfaces automatically via cron `62ed334a` on 2026-05-11 (or rearmed firings).

## Context Notes

- **Why C over A.** Path A (Linear parent + label only) is the smaller ship but treats the release primitive as Linear-shaped. Zach's provider_neutral_schemas memory plus agentic_agency_first memory both point at Path C as the long-term-correct answer: every workflow surface must work in both backends, and schemas must be provider-neutral. The cost (3 sessions vs. 1) is real but the design parity is the load-bearing decision.
- **Provider-migration mandate (decision 2 in BTS-163) is the most consequential design call.** It rules out a "lazy" implementation where releases drift between backends when a project switches providers. Cross-provider drift is forbidden at all times — `release.migrate` becomes a v1 deliverable rather than a follow-up. This makes the local backend a real first-class citizen, not a fallback.
- **Self-application is the design test.** Release-system v1 will be the first release the system manages, with its own ~7 children. If the model can express its own delivery cleanly, the model works. If not, the model is wrong. This is the dogfood-close pattern at the system level — same logic that has held across 29 consecutive feature ships.
- **Scheduling caveat surfaced for the first time.** CronCreate with `durable: true` echoed "Session-only" as if the flag was ignored. Could be cosmetic or genuine. Worth a deterministic check on next `/recall` (look for `.claude/scheduled_tasks.json`). If durable is silently a no-op for one-shots, that itself is a friction point worth capturing — but defer until evidence accumulates (one observation is not a pattern).
- **Carry-forward backlog clusters identified pre-emptively.** Even before BTS-163's `/radar` enhancement ships, this session's radar pass clustered the 14 backlog items into: workspace-fence hardening (BTS-153/155/156/157/158/151), `/permissions-review` codification (BTS-159/160/161), classifier bash-grammar awareness (BTS-150/154), orphans (BTS-162/152). These groupings will become the v1 backfill targets.

## Determinism Review

- **operations_reviewed:** ~25 (recall queries, radar synthesis, MCP idea capture, cron scheduling, validation passes).
- **candidates_found:** 1 NEW.

- **NEW: Cron-job durability verification.** Scheduling BTS-163's drainage check exposed an uncertainty about whether `durable: true` was honored on a one-shot CronCreate (response echoed "Session-only"). The deterministic check — does `.claude/scheduled_tasks.json` exist after scheduling, and is the job ID present — was not run. Future cron schedulings should include a post-schedule verification step in the skill that calls it. Impact: low (single cron job, easy to re-arm), but the friction will recur on every cron use.
  - **Capture:** Not yet ticketed. Add to next session if observed twice.
- **No other candidates** — this session was design dialogue + capture + schedule, not workflow-mechanic-heavy work.

## Cross-Session Patterns

- **VALIDATED: walk-then-codify pattern (extended to design-then-capture).** Last session's walk surfaced 10 follow-up tickets via friction; this session's strategic dialogue surfaced 1 follow-up (BTS-163) via design synthesis. Both are forms of the same loop: tactical activity surfaces strategic gaps; capture-during-flight prevents loss. The pattern generalizes beyond skill walks.
- **VALIDATED: dogfood-close cultural invariant.** Prior stasis: 29. This session ships nothing implementable, so cumulative count is unchanged. BTS-163's self-application clause means the count will jump on Release-system v1 ship.
- **NEW: backlog drainage as an explicit pre-condition for big-ticket work.** Zach explicitly named "0 tickets in Triage or Backlog" as the gate for BTS-163 pickup. This is the first time a strategic effort has been gated on backlog cleanliness rather than a tactical dependency. Pattern to watch for: are other future big-ticket efforts gated similarly? If yes, this becomes a workflow primitive (a "drain gate") that may itself want substrate support — e.g., `radar-gather` could expose drain-status as a first-class field that big tickets reference.
- **CONFIRMED: legacy-refs-scan stays clean** (0 matches). BTS-132 mechanism continues to hold.
- **CONFIRMED: classifier-semantics gap family still at 2 tickets** (BTS-150 + BTS-154). Below the 4-5 threshold for a structural cleanup ticket. Watching.

## Security Review

- This session added: nothing to local fs. One Linear issue created (BTS-163, idea-state) and one cron job scheduled (in-memory or `.claude/scheduled_tasks.json` if durable took).
- No secrets, tokens, PII, or credentials anywhere in the BTS-163 body or cron prompt.
- Verdict: **PASS**. No new attack surface.

## Memory Candidates

- **"Release" as a tactical work-grouping primitive (Linear parent + label, ccanvil-routed, provider-migration-mandatory).** Worth memorializing once Release-system v1 ships, not before. Premature memory while the design is still on paper. **Decision: NOT saved this session.**
- **Backlog drainage as an explicit gate for big-ticket pickup.** New workflow concept ("drain gate"). Same as above — capture once it's exercised more than once. **Decision: NOT saved this session.**
- **CronCreate `durable: true` ambiguity on one-shots.** Single observation. Not a pattern yet. **Decision: NOT saved.**
- No external references discovered this session that aren't already memorialized.

No new memories saved this session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
