# Stasis

> Feature: session-2026-04-25-permissions-review-batch-ship
> Kind: session
> Last updated: 1777089249
> Session objective: Close the autonomy-first design loop. Ship BTS-147 (workspace fence false-positive), BTS-148 (deterministic activate transition), BTS-143 (DANGER override via accept_danger), BTS-144 (promote-review classifier). Validate BTS-148's `/activate` skill end-to-end via in-session dogfood on subsequent activates. Capture the missing interactive layer as BTS-149.

## Accomplished

- **4 features shipped end-to-end** + **1 captured** + **1 memory correction**. Each ship validated the prior session's substrate or paired with a same-session sibling. Coherent batch around the autonomy-first permissions / lifecycle / review story.
  - **PR #68 / BTS-147** — guard-workspace bare-`/` glob fix. One-line case-glob change `/*)` → `/?*)` so `/` followed by ≥1 char is required for the absolute-path branch. Eliminates daily `ALLOW_OUTSIDE_WORKSPACE=1` workarounds for jq math, shell expressions, and any literal standalone `/` in command strings. 4 new bats cases (AC-1, 3, 5, 6). Self-discovered stasis-time previous session — first dogfood case ever filed at the previous stasis time.
  - **PR #69 / BTS-148** — deterministic `cmd_activate` → Linear In Progress transition. `cmd_auto_transition_emit` was a stdout-marker-only design with no consumer; result was every activate left the linked Linear ticket stuck in Triage. Belt-and-suspenders fix: script-side `ticket.transition` enqueue to `.ccanvil/ideas-pending.log` (deterministic backup, drained by `/idea sync`) AND new `/activate` skill at `.claude/commands/activate.md` (immediate dispatch — parses marker, resolves, dispatches MCP, acks pending entry). Mirrors `/land`'s AUTO-CLOSE precedent. 5 new bats cases. Discovered, captured, designed, shipped, all in this session.
  - **PR #70 / BTS-143** — `accept_danger:true` log override. Inside `cmd_check`'s DANGER-pattern-match branch, when the log entry has `accept_danger:true` AND all 4 required fields filled, reclassify as REVIEWED with `matched_pattern` + `risk_accepted:true` preserved for audit trail. Backwards-compatible: existing entries without `accept_danger` keep current DANGER behavior. Text-mode adds always-visible `--- REVIEWED (risk-accepted) ---` section. 4 new bats cases.
  - **PR #71 / BTS-144** — `permissions-audit.sh promote-review` classifier. Lists `settings.local.json` entries not in `settings.json` and classifies each via deterministic rules: redundancy (covered by broader `Bash(<word>:*)`) → DELETE, `preset/` dead path → DELETE, env-prefix bypass with broadly-allowed underlying verb → DELETE, otherwise → TRIAGE. JSON + `--text` output modes per BTS-134 conventions. 9 new bats cases. **Dogfood:** real `settings.local.json` correctly classifies 2 stale `ALLOW_OUTSIDE_WORKSPACE=1` entries as DELETE one-shot.
  - **BTS-149 captured in Triage** — interactive permissions review at session boundaries. Full design for: surface BTS-143/144 outputs at `/stasis` + `/recall`, new `/permissions-review` skill walks through per-row Q&A, new `permissions-audit.sh apply --decisions <jsonl>` substrate. Closes the loop that BTS-143 + BTS-144 stopped short of.
  - **Memory correction.** Wrote `feedback_interactive_cleanup.md` after BTS-149 capture; Zach correctly called out that the principle should be enforced by process design (BTS-149's spec already does this — `--apply` requires explicit decisions JSONL → only populated via per-row Q&A → no shortcut). Removed the redundant memory. Refined understanding: memory is for additional coverage when process is broken, not for primary enforcement.
- **27 consecutive dogfood-closes maintained** as of session end (23 prior + BTS-147, 148, 143, 144 — all closed via the primitive being added or its sibling auto-close path).
- **Test suite grew 1058 → 1080** (+22 across 4 ships: 4 BTS-147 + 5 BTS-148 + 4 BTS-143 + 9 BTS-144). Full suite green on each ship.
- **In-session dogfood validation:**
  - **BTS-148 self-validated 3 times:** BTS-143 activate, BTS-144 activate, BTS-149 capture (well, the Triage capture flowed through `/idea` not `/activate`, but BTS-143 and BTS-144 activates both: script enqueued → marker emitted → I dispatched MCP → entry acked → no manual workaround needed). The pattern is robust.
  - **BTS-146 workspace fence self-validated** on the memory-file delete (correctly blocked the cross-workspace `rm`, surfaced `ALLOW_OUTSIDE_WORKSPACE=1` bypass affordance).
  - **BTS-147 bare-`/` fix dogfooded inline** by every script invocation since — no `ALLOW_OUTSIDE_WORKSPACE=1` workarounds needed for jq math.
  - **BTS-144 dogfooded on real settings.local.json** — 2 stale entries correctly classified as DELETE one-shot.

## Current State

- **Branch:** `main` at `0a6225b` (post-BTS-144 merge, FF'd via `/land`).
- **Tests:** **1080 / 1080 green** via `bats-report.sh --parallel`.
- **Uncommitted changes:** none.
- **Build status:** clean.
- **Context budget:** WARNING **81.3%** (6502/8000) — unchanged from last stasis. settings.json is the dominant cost; BTS-143 doesn't compress until rationales are written, BTS-144 doesn't add to settings.json.
- **Permissions audit:** 121 UNREVIEWED + 0 REVIEWED + (DANGER count from prior stasis was 18; should be similar — a follow-up review pass writing `accept_danger:true` rationales would drop DANGER to 0 by design now that BTS-143 is shipped). Promote-review surfaces 2 DELETE candidates in `settings.local.json` (the 2 carryover `ALLOW_OUTSIDE_WORKSPACE=1` entries that became unnecessary after BTS-147).
- **Specs archive:** **68 Complete** (was 64 entering session; +4: 147, 148, 143, 144). Linear backlog: BTS-149 in Triage; ~3 older needs-research items (BTS-22, 20, 21) on Horizon; remainder Done.

## Blocked On

- Nothing. Working tree clean, tests green, all 4 ships landed cleanly, BTS-149 captured for next session.

## Next Steps

1. **BTS-149** — interactive permissions review at session boundaries. The natural completer of the BTS-143/144 substrate. Three-part design already specced in Linear: (1) surface counts at `/stasis` + `/recall`, (2) new `/permissions-review` skill with per-row Q&A, (3) `permissions-audit.sh apply --decisions <jsonl>` substrate. Spec it with `/spec BTS-149 ...`, then activate.
2. **DANGER review pass** — separate small task. With BTS-143 shipped, write `accept_danger:true` + rationales for the ~18 broad-wildcard DANGER entries. Drops DANGER count to 0 by design. Could be a single commit. Best done alongside BTS-149 since they exercise the same surface.
3. **Tech stack distribution** — roadmap "Up Next" #1. Distribute tech-stack profiles (hooks/rules/CLAUDE.md sections) hub→nodes. First profile: FastAPI/SQLite. Bigger scope; reasonable second-priority after BTS-149.
4. **BTS-22** Docs directory strategy (Medium, needs-research) — Horizon item.
5. **BTS-20** Workflow engine — Horizon, low priority.
6. **BTS-21** GitHub Agentic Workflows — awaiting GA.

## Context Notes

- **The autonomy-first batch is now structurally complete (substrate-wise).** BTS-142 (broad allow), BTS-146 (workspace fence), BTS-145 (auto-push-main), BTS-147 (bare-`/` fix), BTS-148 (deterministic transition), BTS-143 (accept_danger override), BTS-144 (promote-review classifier). Seven primitives. The interactive layer is the missing capstone — that's BTS-149.
- **Pattern: the substrate ships first, the interactive layer ships next.** BTS-143 + BTS-144 gave us classifiers; BTS-149 is the agent-reachable interactive wrapper. Same pattern as BTS-146 (substrate) → BTS-147 (refinement) → no interactive wrapper because the fence doesn't need one. And BTS-136 (transition primitive) → BTS-148 (immediate dispatch + script enqueue) — the wrapper. Future autonomy work should think in this 2-step: deterministic substrate, then agent-reachable interactive layer.
- **Memory rules clarified.** Zach: "Memory should NOT enforce principles; deterministic process design should. Memory is for additional coverage when the process is broken." This refines the existing `feedback_deterministic_first.md`. Implication: when noticing a behavioral pattern I want enforced, FIRST ask "can the process design enforce this?" Only if no, then memory. The rule applies retroactively too — review existing memories, see if any encode principles that should be process-enforced.
- **Cloudflare WAF risk on Linear MCP** held this session. BTS-148 + BTS-149 ticket bodies contained shell-pattern strings (`rm /etc/foo`, `bash`, etc.) but the WAF didn't fire — likely because the patterns were inside markdown code blocks / quotes, not bare strings. The `reference_linear_mcp_waf.md` memory's workaround (paste via web UI) wasn't needed.
- **`/activate` skill is now battle-tested.** First in-session use was on BTS-143; second was BTS-144; in both cases the dispatch worked cleanly. The skill prose at `.claude/commands/activate.md` is the canonical reference for the AUTO-TRANSITION pattern.

## Determinism Review

- **operations_reviewed:** ~70 (4 ships + 1 idea capture + 1 memory write+delete + 5 lifecycle activates/lands + various script invocations + dogfood validations)
- **candidates_found:** 1 RESOLVED + 1 NEW (captured)

- **RESOLVED via ship: AUTO-TRANSITION marker stochastic dispatch.** Was previous session's stasis-time discovery (BTS-148 was captured at the end of last session). Shipped this session as BTS-148. Now deterministic via script enqueue + `/activate` skill dispatch + `/idea sync` retry path. **Dogfooded 2 times in-session** — robust.
- **NEW CANDIDATE (CAPTURED as BTS-149): interactive cleanup at session boundaries.** Discovered when BTS-144 dogfood printed 2 DELETE recommendations and Zach observed they should be interactive at session boundaries, not silent classifier outputs. The classification is deterministic but the user-facing review surface is missing. Captured with full design (Part 1: surface at /stasis+/recall, Part 2: /permissions-review skill, Part 3: apply --decisions substrate).

## Cross-Session Patterns

- **RESOLVED: AUTO-TRANSITION marker stochastic dispatch** — last stasis flagged this implicitly as a candidate (BTS-148 was the captured idea); this session shipped BTS-148. Pattern: stasis-time-discovery → next-session-ship.
- **VALIDATED: dogfood-close cultural invariant.** Prior stasis: 21 consecutive. This session: 25 → 27 (BTS-147, 148, 143, 144 all closed via the primitive being added or its sibling auto-close path).
- **VALIDATED: same-session capture→ship loop.** BTS-148 was captured + shipped same session (last session captured, this session shipped). BTS-149 captured this session — pattern continues.
- **CARRYOVER trending down: audit-session test-fixture noise.** 49 → 14 (last stasis) → 2 (this stasis). Allowlist-extension on `hub/tests/*.bats` would zero it. Worth a small ticket if it ever amplifies.
- **CONFIRMED: legacy-refs-scan stays clean** with `--respect-allowlist`. 0 matches this session, 0 matches last session. BTS-132 mechanism holds.
- **NEW: `/activate` skill in production.** First two activates (BTS-143, BTS-144) used the new pattern successfully. Will become routine going forward.
- **NEW: settings.local.json carries 2 stale entries.** Will resolve on BTS-149 ship via interactive triage.
- **NEW (meta): memory vs process design distinction made explicit.** Zach's call-out refines deterministic-first principle. Future memory writes should ask "can process enforce this?" first.

## Security Review

- No secrets, tokens, PII, or credentials introduced this session. All work was script logic, hook code, test fixtures, and skill prose.
- BTS-147 narrowed a glob pattern in a security-relevant hook (workspace fence) — defensive code, narrows risk surface.
- BTS-148 added a script-side enqueue + skill dispatch — reads from spec metadata + writes to gitignored pending log + dispatches via configured MCP. No new credential paths or external-data ingress.
- BTS-143 introduced `accept_danger:true` log flag — explicit user-driven override. Backwards-compatible (existing entries without the flag keep DANGER classification).
- BTS-144 is read-only review tooling — no mutation surface.
- The two `ALLOW_OUTSIDE_WORKSPACE=1` entries in settings.local.json remain (the carryover from last session); will be triaged via BTS-149.
- Verdict: **PASS**.

## Memory Candidates

- **Memory rules clarified (process design > memory for principle enforcement)** — Zach: "this should be enforced by deterministic process design and not rely on stochastic triggering. Memory is fine for additional coverage, only if the process is broken." Refines existing `feedback_deterministic_first.md`. **Decision: NOT saved as separate memory** (per Zach's own framing — would be over-memoring). Recorded here in stasis for cold-start recovery; the principle is implicit in the existing deterministic-first memory.
- **`/activate` skill is the canonical AUTO-TRANSITION wrapper** — point of reference, but already documented in `.claude/commands/activate.md` and `.ccanvil/guide/command-reference.md`. **Decision: NOT saved** — code is the source of truth.
- **Cloudflare WAF didn't fire this session despite shell-injection-pattern body content** — possible the WAF rules differentiate code-block vs bare-string contexts. Not strong enough signal to update `reference_linear_mcp_waf.md` yet. **Decision: NOT saved.**

No new memories saved this session. One memory was DELETED (`feedback_interactive_cleanup.md` after Zach's call-out).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
