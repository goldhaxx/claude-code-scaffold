# Stasis

> Feature: session-2026-04-24-todo-batch-ship
> Kind: session
> Last updated: 1777069686
> Session objective: Execute the 5-ticket Todo batch (BTS-131, 132, 136, 137, 139) end-to-end. Plus surface BTS-138 (cmd_land post-merge gap) as a follow-on determinism candidate found mid-session.

## Accomplished

- **Shipped 5 features end-to-end this session** plus closed BTS-131 as duplicate. Sequenced: BTS-138 (resolve determinism candidate from prior stasis) → BTS-131 (close duplicate) → BTS-139 (Triage routing root cause + fix) → BTS-132 → BTS-137 → BTS-136. Independent branches, independent dogfood-closes, one Linear smoke-test sweep (BTS-140 → Canceled).
  - **PR #54 / BTS-138** — `cmd_land` on main recovers landed branch from last squash-merge's `(#<PR>)` suffix via `gh pr view`, delegates to existing `cmd_auto_close_emit`. Closes the 3rd-consecutive-stasis determinism gap. 12 bats cases. Validated live: own merge fired AUTO-CLOSE without manual intervention.
  - **PR #55 / BTS-139** — root cause for "captures land in Backlog despite stateId" found: Linear MCP's `save_issue` tool accepts `state` (not `stateId`). Renamed 19 emissions in operations.sh + 48 test assertions + 15+ skill/doc refs. New regression test (`stateid-rename-regression.bats`, 11 cases) guards re-introduction. Empirical proof: BTS-140 smoke test landed in Triage with the renamed param.
  - **PR #56 / BTS-132** — `--respect-allowlist <path>` flag on `legacy-refs-scan`. /stasis skill now invokes it so Cross-Session Patterns surfaces real drift only (zero matches this session vs 157 raw last). 7 bats cases.
  - **PR #57 / BTS-137** — `--timings` / `--slow-top N` on `bats-report.sh`. Parses bats-core's `-T` output; sorted slowest-first table; JSON mode adds `timings: [{test, ms}]`. 7 bats cases.
  - **PR #58 / BTS-136** — `cmd_activate` emits `AUTO-TRANSITION:` marker (mirror of BTS-119's `AUTO-CLOSE:`). Linear lifecycle fully wired: Triage → Backlog → Todo (via /spec) → In Progress (via activate) → Done (via merge/land). New roles `todo` + `in_progress` added to operations.sh validation + state_ids config. 8 bats cases.
- **BTS-131 → Duplicate-of-BTS-118.** Comment posted with explicit fix-idea-by-fix-idea cross-ref to BTS-118's shipped reporter.
- **BTS-140 captured + canceled** — deliberate smoke test for BTS-139's fix. Title prefix `SMOKE TEST (BTS-139):` makes intent obvious. Canceled within ~10s of capture.
- **12 consecutive dogfood-closes** as of session end: BTS-128 → 119 → 122 → 127 → 118 → 129 → 113 → 138 → 139 → 132 → 137 → 136. Cultural invariant maintained — every primitive-introducing ship closes its driving ticket via the primitive.
- **Test suite grew 902 → 975** (+73 across 7 ships this session: 12 land-recovery + 11 stateid-rename + 7 legacy-allowlist + 7 timings + 8 auto-transition + assorted fixture cascades). Full suite green at every phase.

## Current State

- **Branch:** `main` at `76ae598` (post-BTS-136 merge, FF'd via `/land`).
- **Tests:** **975 / 975 green** via `bats-report.sh --parallel`.
- **Uncommitted changes:** none (working tree clean).
- **Build status:** clean.
- **Context budget:** WARNING at 74.9% (5989/8000 tokens). Up slightly from prior session's 73.0% — five spec/plan/stasis cycles + the BTS-139 cascade across operations.sh + skill docs explain the climb.
- **Permissions audit:** `permissions-log.json` not initialized → audit reports raw counts (27 DANGER, 171 UNREVIEWED, 0 REVIEWED). Last stasis showed it as classified clean. Either the log got truncated or the prior "clean" reading required prior init. Investigate next session — may be a new determinism candidate (auto-init the log on first run).
- **Specs archive:** **55 Complete** (was 50 entering session; +5: 138, 139, 132, 137, 136). Spec backlog still 14 Linear backlog items (minus 5 transitioned to Done minus BTS-131 to Duplicate plus BTS-138 + BTS-139 captured).
- **Linear state:** 0 Triage. ~7 Backlog. 5 fresh Done. 1 fresh Duplicate (BTS-131). 1 fresh Canceled (BTS-140 smoke test).

## Blocked On

- Nothing.

## Next Steps

1. **Investigate permissions-audit log re-init.** `permissions-log.json` is missing → audit reports unclassified counts. Likely needs `permissions-audit.sh init` to re-establish the classified state. If recurring, add to a hook to re-init when missing.
2. **Triage remaining Linear backlog** — ~7 items still in Backlog. /radar to see strategic priorities. BTS-123 (pending-log fallback integrity) was unblocked by BTS-129 last session.
3. **Validate BTS-136's auto-transition wiring next time you /spec a Linear feature.** This session, BTS-136 self-validated by manual dispatch (its activate ran before the fix existed). Next /spec from a clean state should see the dispatch fire automatically per the updated /spec skill prose.
4. **BTS-125** (Linear save_issue markdown truncation) — P4 nice-to-have finisher.
5. **BTS-133, BTS-134, BTS-135** (remaining tooling correctness items from the original cluster).
6. **Address context budget** — 74.9% trending up. Consider trimming `CLAUDE.md` hub section or one of the `guide/` files if next session opens at 76%+.

## Context Notes

- **Pre-existing config bug (BTS-139): the `stateId` vs `state` parameter mismatch.** Despite BTS-121 supposedly fixing "captures don't land in Triage", the operations.sh resolver was emitting `params.stateId` while Linear MCP's `save_issue` tool only accepts `state` ("State type, name, or ID"). Linear silently ignores unknown parameters and falls through to the team's default state. This bug has been live since BTS-121's fix — the only reason transitions appeared to work is that I (Claude) have been manually translating `stateId` → `state` at dispatch time across many recent sessions. The /idea capture path (BTS-138 + BTS-139) was the canary because skill prose said "pass `stateId`" verbatim and I followed it literally. Fixed via bulk rename in PR #55 + new regression test asserting `stateId` key never appears in resolver output.
- **The umbrella-decompose-sequenced-ship pattern continues to work.** This session shipped 5 + 1-close in a single run, mostly without /plan files (skipped for the 3 smaller ones to save context). All 5 ACs were tight enough that the spec alone was enough planning. Lesson: skip /plan for spec-driven work where ACs map 1:1 to TDD steps.
- **`cmd_auto_transition_emit` ≈ `cmd_auto_close_emit`.** Almost identical decision tree, only the role parameter and marker prefix differ. Inline duplication (~30 LOC) is still cheaper than abstracting; revisit if a third role-emitter shows up.
- **Linear's `state` parameter accepts UUID, name, OR type.** Documented in MCP schema as "State type, name, or ID". This means: ID dispatch works (UUID); type dispatch works ("triage", "started", etc.); name dispatch works but collides with type names ("Triage" vs `type:triage`) per BTS-121 historical note. Always prefer UUID dispatch — that's what the operations.sh resolver emits now.
- **/spec skill prose now drives 2 MCP dispatches per spec write.** When the work-ref is `linear:<ID>`: (1) `idea-update <num> promoted` if from idea; (2) `ticket.transition <id> todo`. The next-session /spec invocation will exercise this in production.
- **Validate accepted "no-active-spec" cleanly this session.** No legacy stasis from prior sessions (it was deleted at /pr-cleanup time of BTS-138 because the safety-net cleanup wiped lifecycle docs including the prior session-stasis). If the prior stasis is needed for cross-session comparison, it has to be retrieved via `git show <prev-stasis-commit>:docs/stasis.md` — which is what step 10 of /stasis already does.
- **BTS-140 was a deliberate smoke test, not real work.** Don't include in any "completed feature" counts. Title prefix `SMOKE TEST (BTS-XXX):` is the canonical marker for these.

## Determinism Review

- **operations_reviewed:** 80+ (across 5 ships + smoke test + cleanup)
- **candidates_found:** 2 new, 1 carryover (RESOLVED)
- **NEW: `permissions-audit.sh` reports unclassified state when `.claude/permissions-log.json` is missing.** Last session ended with "0 DANGER + 0 UNREVIEWED" implying the log was init'd. This session shows 27 + 171, and the script emits "NOTE: .claude/permissions-log.json not found — run permissions-audit.sh init". Either the log isn't being committed (gitignored?) or it got cleared. If the log is meant to be node-local and re-initializable, the script should auto-init on first run when missing. **Action:** investigate, probably add `--auto-init` flag or equivalent.
- **NEW: 4 redundant `git push origin main` invocations.** Each spec-on-main commit followed by sync-check failure forced a push, then activate. Could be folded into `cmd_activate --auto-push-main` or `cmd_spec --activate` shortcut. Impact: low (4 invocations × low cost), but recurs every time we ship a spec. **Action:** consider `cmd_activate` accepting a `--push-main-first` option that pushes main if behind.
- **CARRYOVER → RESOLVED: `gh pr merge --delete-branch` gap.** Was must-ship from prior stasis. Shipped this session as BTS-138. 5 land cycles after the fix all auto-closed without manual `auto-close-emit`. Resolved.

## Cross-Session Patterns

- **RESOLVED (live-validated this session): BTS-138 cmd_land gap.** Recurred 3+ consecutive stases entering this one; shipped the fix and validated 5× consecutively post-fix. Expected not to recur.
- **RESOLVED (live-validated this session): BTS-139 Triage routing.** /idea captures landed in Backlog instead of Triage every time despite correct config. Root cause was the `stateId` vs `state` parameter mismatch. Smoke-tested with BTS-140 capture immediately post-fix. Expected not to recur.
- **NEW: Permissions log missing at session end.** Last session ended clean (0 DANGER + 0 UNREVIEWED), this one is reporting unclassified. Watch next session.
- **Legacy-refs-scan: zero matches with `--respect-allowlist`** — the BTS-132 ship has its first immediate signal-cleaning win. Last stasis raw scan was 157 matches; this session's filtered scan is 0. (Determinism review's other findings: 3 jq false positives in test fixtures, all bats assertions over MCP shape — expected, not signal.)
- **Umbrella-decompose-sequenced-ship pattern: validated 2× in a row.** Last session: 4-ship bundle. This session: 5-ship batch. Both stable. Promote to default approach for any 3+ related-ticket cluster.
- **First stasis had no prior to compare** at one point — actually false. `git show c07b69d:docs/stasis.md` returned the prior stasis. Comparison succeeded.

## Security Review

- `security-audit.sh --files-only` ran during BTS-138's /review cycle: PASS.
- All 5 ships introduced no secrets, tokens, or PII. New test files use safe fixture patterns (UUIDs as literal strings, no real secrets).
- The `state_ids` UUIDs in `.claude/ccanvil.local.json` were already committed (visible in git history) — they're workflow-state identifiers, not secrets, and Linear treats them as public per their API model.
- BTS-140 captured + canceled within seconds; description was self-explanatory test-only content.

## Memory Candidates

- **Linear MCP's `save_issue` parameter is `state`, NOT `stateId`** (project/feedback) — fundamental config-bug discovery. The /idea skill literally said to pass `stateId` and it silently no-op'd for years. Renamed everywhere; new regression test guards. Worth remembering whenever working with Linear MCP directly: always pass `state: <UUID>` (or `state: "<type>"`), never `stateId`.
- **Triage stateId UUID for Blocktech Solutions team** (reference) — `53b10a02-ce3c-4990-aebc-e105c7229a37`. Other key UUIDs in `.claude/ccanvil.local.json:state_ids`. Worth bookmarking because they're stable identifiers used everywhere.
- **`AUTO-TRANSITION:` marker convention** (project/feedback) — sibling of `AUTO-CLOSE:`. Pattern: scripts emit JSON-bodied markers on stdout; skills/Claude scan and dispatch. Reusable for future state-emit primitives.
- **Skip /plan when ACs map 1:1 to TDD steps** (feedback) — used this session for 3 of the 5 ships. Tight specs with focused ACs don't benefit from a separate plan file. Saved context. Pattern: if spec is <80 lines and each AC is one bats case, the plan would just be a numbered restatement.
- **PERMISSIONS audit: log file may need re-init each fresh start** (project) — `.claude/permissions-log.json` was missing this session-end. Investigate next session whether the file is gitignored (intentionally node-local) or got accidentally cleared.
- **bats-core has built-in `-T/--timing` flag** (reference) — emits `ok N <name> in Nms` per test. Used by BTS-137. Useful for any future bats-related observability.
- **Squash-merge commit subject format `(#<PR>)`** (reference) — GitHub's canonical squash format embeds the PR number. BTS-138 uses this to recover landed branches. Reusable for any PR-ID extraction.
- **/spec skill ALWAYS dispatches `ticket.transition <id> todo` for linear specs now** (project) — a new responsibility added this session. Don't forget when using /spec in future sessions.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
