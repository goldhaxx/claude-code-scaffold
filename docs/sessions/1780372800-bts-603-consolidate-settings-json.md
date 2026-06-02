# Stasis: bts-603-consolidate-settings-json

> Feature: bts-603-consolidate-settings-json
> Work: linear:BTS-603
> Kind: feature
> Last updated: 1780372800
> Session: 80
> Boundary: 2026-06-01T17:14:27-07:00
> Plan hash: pending (no plan yet — implementer's first step on resume)
> Session objective: Wrap BTS-602 triage tail (drain Triage queue, capture follow-ups) and stage BTS-603 (consolidate `.claude/settings.json`) through spec + critic + activate. Stop short of plan/impl — operator going to sleep.

## Accomplished

- **`/idea triage` drained 24 → 0** (then +1 = 1 for BTS-612, drained again to 0):
  - **7 promoted** (4 Determinism dual-captures from BTS-602 + BTS-604 P3; 3 Onboarding-theme P2 — BTS-599/598/597).
  - **17 merged** into substrate parents or Backlog drift-watchdog siblings (BTS-601→602 substrate; BTS-600→321 substrate; 15 drift-watchdog Triage→Backlog merges, one per node).
  - **Discovered + captured BTS-612** — `cmd_save_issue --duplicate-of` ordering substrate bug. The IssueUpdate to Duplicate state runs BEFORE the relation-create dispatch (BTS-228 ordering), but Linear's Duplicate state rejects the update unless the relation already exists. Caused ALL 17 merges to fail dispatch + auto-queue to pending log. Workaround: two-step pattern (`create-relation` first with UUIDs, THEN `ticket.transition duplicate`). Triaged BTS-612 → Backlog P2.
  - **17 pending-log entries cleared** (filtered by jq id-match; 22 → 5; remaining 5 are stale pre-existing).
- **BTS-603 spec drafted** — `docs/specs/bts-603-consolidate-settings-json.md` + Linear Document `044b69f5`. 12 ACs, 1 GWT (AC-3 deny-superset), 1 error AC (AC-11), 3/3 file refs.
- **`/spec --review` × 6 rounds** — 5 real load-bearing findings caught and fixed, round 6 PASS:
  - R1 AC-6 (which canonical path form survives?)
  - R2 AC-7 ("at least one" → enumerated exact 8-entry move-set)
  - R3 AC-8 (Mermaid Chart unclassified → expanded to exhaustive project-shared list)
  - R4 AC-4 (per-event-group prose vs flat-union verifier → tightened to per-event subset check)
  - R5 AC-9 (stale hardcoded baseline 2469 → dropped count floor, "exit 0" carries the load)
  - R6 PASS
- **Activated BTS-603** — branch `claude/feat/bts-603-consolidate-settings-json` + draft PR #198. Auto-transitioned BTS-603 → In Progress.

## Current State

- **Branch:** `claude/feat/bts-603-consolidate-settings-json` (PR #198 draft).
- **Tests:** N/A this session — no implementation commits. Last full pass was 2469/2469 pre-BTS-602-ship.
- **Uncommitted changes:** none.
- **Build status:** clean. Manifest 204 / 204 drift 0 (cached — no allowlisted files touched this session).
- **Linear:** BTS-603 In Progress; BTS-612 Backlog P2; Triage 0; Backlog 88 (was 81 + 7 promotes = 88).
- **Pending log:** 5 stale pre-existing entries (none from this session's work).
- **Context budget:** CRITICAL — 9137 tokens vs 8000 ceiling (114.2%). settings.json still 1604 tokens / 20.1%. BTS-603 is the load-bearing trim about to begin.

## Blocked On

Nothing.

## Next Steps

1. **`/plan`** — first action on resume. BTS-603 lifecycle state is `spec-activated`; legal transition is plan-write. The implementer's plan structure should mirror BTS-602: TDD step 1 captures pre-state snapshots (deny array, hooks per-event-group, full allow array) into `/tmp/bts-603-pre.json`; then ACs land in order AC-5 (shell keywords) → AC-6 (path dedup) → AC-7 (operator-personal moves) → AC-1/AC-2 (measure budget delta) → AC-12 (drift-guard bats file).
2. **Stay in spec mode for the trim — don't rewrite settings.json by hand.** The spec's `Implementation Notes` section pins the verification rhythm: jq diff against `/tmp/bts-603-pre.json` snapshots, not git-history re-reads. AC-3 (deny superset) and AC-4 (per-event-group hooks) are the security-load-bearing invariants — verify them FIRST after every edit batch.
3. **AC-12 bats file** — `hub/tests/settings-consolidation.bats` is the drift-guard substrate ship for this PR. It must pin AC-3, AC-4, AC-5, AC-6, AC-7, AC-8 as re-runnable forever. Add to `hub/tests/legacy-refs-allowlist.txt` if needed; bats files are not on the manifest allowlist (only Bash primitives are).
4. **BTS-605 (Backlog Urgent) remains the higher-leverage follow-up** post-BTS-603 ship — substrate-wide broadcast unblock. BTS-603 makes future sessions cheaper; BTS-605 makes the BTS-603 trim REACH downstream nodes. Order them BTS-603 → BTS-605.
5. **BTS-612 (Backlog P2)** — the substrate ordering bug. Will need a spec + small ship. Smaller than BTS-603 or BTS-605; appropriate as a between-bigger-work palette-cleanser.

## Context Notes

- **Critic-mode caught 5 real findings on a `validate-spec`-clean spec.** Same pattern as BTS-602 (which caught 2). The cycle has stabilized at "round N+1 keeps finding load-bearing ambiguities until the spec is genuinely tight." Five rounds is a lot, but each finding was real and each fix was load-bearing. Memory note `feedback_critic_mode_finds_real_findings_on_validated_specs` says re-run after every substantive edit — that discipline is what surfaced rounds 3 and 5 (each triggered by my own round 2 / round 4 fix).
- **BTS-612 was a 5-week-old substrate bug surfaced ONLY by a 17-merge batch.** A single merge would have looked like a Linear flake. The batch made the 17/17 failure ratio undeniable. Lesson: substrate bugs at high-cardinality dispatch surfaces stay hidden until the surface is actually batched. The bulk dispatch IS the integration test the substrate never had.
- **Linear `Duplicate` state has a foreign-key constraint** that the substrate didn't model. The IssueRelation of type=duplicate must exist BEFORE the IssueUpdate to Duplicate state succeeds. BTS-612's spec needs to reorder cmd_save_issue's duplicate-of branch to call cmd_create_relation FIRST, then issueUpdate. Also needs UUID resolution at the substrate boundary (cmd_create_relation requires UUIDs; the `--duplicate-of` flag accepts identifiers today, dropping a `get-issue → .uuid` resolve in-between).
- **Pending-log cleanup-by-id-match is a determinism gap.** I used a hand-written jq filter to drop 17 completed entries from `.ccanvil/ideas-pending.log`. The substrate has `idea-sync --ack <ts>` but no `--ack-id <id>` (which would let bulk-replay drain by ID-list deterministically). Captured as a candidate below.
- **Concurrent-edit-guard fired 4× this session** (spec dispatch rounds 2/3/4, activate spec re-dispatch). Each time the pattern was identical: empty document-history → own-caller normalizer divergence → `ALLOW_CONCURRENT_EDIT_OVERRIDE=1`. 9 cumulative fires in the BTS-602/603 lifecycle (5 last session + 4 this session). BTS-563 is the load-bearing fix.

## Determinism Review

- **operations_reviewed:** ~25 (recall, idea triage round 1 with 24 transitions including discovery + workaround for BTS-612, idea triage round 2, spec drafting, 6 critic rounds with 5 substantive edits + re-dispatches, activate + retry + AUTO-TRANSITION dispatch).
- **candidates_found:** 2.

**idea-pending-bulk-ack-by-id-list**: Claude wrote a hand-crafted jq filter to drop 17 completed merge entries from `.ccanvil/ideas-pending.log`. The substrate's `idea-sync --ack <ts>` removes by timestamp, but timestamps are not unique across rapid-fire dispatch (3 entries shared 1780369770 in this batch) AND the ts of a manual-workaround completion doesn't match the pending-log ts. A substrate verb `idea-pending-ack-by-id --op merge --ids BTS-X,BTS-Y,...` would deterministically clear by op + id-list match. Impact: medium (every batch-recovery scenario benefits).

**cmd-save-issue-ordering-bug-already-captured**: BTS-612 captures the substrate ordering bug. Listed here for self-review completeness — the candidate IS the captured ticket. Impact: high (every `/idea triage` merge today hits this).

## Evidence Gaps

- BTS-505 — BTS-497 follow-up: capture test.error_excerpt on failed bats spans — missing-evidence-anchors

(Note: BTS-601's evidence gap from prior session is RESOLVED — closed as duplicate of BTS-602 this triage. evidence-scan surfaces it because it scanned the last 80 commits; the substrate doesn't dedup against closed Linear state.)

## Manifest Coverage

204 / 204 (allowlist), drift incidents: 0 (cached — no allowlisted files touched this session; only `docs/spec.md` lifecycle-shape commit).

## Cross-Session Patterns

- **concurrent-edit-guard friction RECURRED (6th consecutive session, 9× this lifecycle).** Last session (BTS-602): 8 fires. This session (BTS-603): 4 fires (rounds 2/3/4 spec re-dispatches + activate spec re-dispatch). Already-ticketed as **BTS-563**. Recurrence curve is now monotonic; the substrate fix is overdue.
- **legacy-refs-scan runtime-artifact false-positive RECURRED (9th consecutive session).** 180 matches, all in `.ccanvil/observability/raw-traces.jsonl` (OTel runtime artifact, gitignored). Already-ticketed as **BTS-562**. Hub-owned; one-line fix sitting in Backlog.
- **NEW pattern: substrate bugs at high-cardinality dispatch stay hidden until batched.** BTS-612 (cmd_save_issue ordering) had been in production since BTS-228 (2026-04-26) — over a month. Single merges looked like Linear flakes; 17/17 surfaced the deterministic bug. Pattern lesson worth a memory: dispatch-surface bugs require batch-mode usage to become visible. The 5+ findings from critic-mode on a validate-clean spec is a sibling pattern: high-cardinality scrutiny (5 independent passes) finds what single-shot validation cannot.
- **audit-session findings:** N/A (clean session, no implementation commits touched code).

## Security Review

**PASS.** No code changes this session — only spec authoring + lifecycle activation. The activate commit added `docs/spec.md` + bumped `docs/specs/bts-603-...md` Status to `In Progress`; no executable diff. No secrets, PII, or credential surface introduced.

## Memory Candidates

1. **Batch-dispatch surfaces hidden substrate bugs.** A 5-week-old substrate ordering bug (BTS-612) surfaced only when 17 merges fired in sequence. Single dispatches looked like Linear flakes. Candidate `feedback` memory: when introducing a new high-cardinality batch path through existing substrate, expect at least one substrate-API-shape bug to surface that single-call usage never tripped. Use the batch as the integration test the substrate never had.
2. **Critic-mode stabilizes at "real findings until genuinely tight."** BTS-602: 2 rounds, 2 findings. BTS-603: 6 rounds, 5 findings + PASS. The "stop after 2-3 rounds" heuristic in `feedback_critic_mode_finds_real_findings_on_validated_specs` may be too tight — both ships' critic loops naturally terminated when the spec was actually clean, not at an arbitrary round count. Candidate addition to the existing feedback memory: "let the critic decide when to PASS, don't pre-bound the rounds."
3. **Linear Duplicate state has a foreign-key precondition** — the IssueRelation must exist before the IssueUpdate succeeds. Useful `reference` memory for future Linear substrate work: states with relation preconditions need create-relation-first dispatch order. Anchor on BTS-612.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
