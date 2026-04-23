# Stasis

> Feature: session-2026-04-23-idea-triage-native-ship
> Last updated: 1776921842
> Plan hash: 91c57d7d (plan lived in PR #44 — 13 TDD steps, cleaned up at merge)
> Session objective: Ship `idea-triage-native` — align `/idea` with Linear-native Triage, codify the five-state idea lifecycle, make every triage outcome agentic via state-ID mutations, add Icebox 60d re-evaluation cadence. Dogfood-validate the flow by migrating 6 legacy items and capturing post-merge findings through the shipped path.

## Accomplished

- **Shipped PR #44 (`ed37701`)** — `idea-triage-native`: 9 AC across 13 TDD-style commits + 1 review-fix commit. 804/804 bats green (+32 new tests in `hub/tests/idea-triage-native.bats`). Clean squash-merge, fast-forward land, dogfooded archive closure (spec auto-transitioned In Progress → Complete via the previously-shipped `pr-cleanup`).
- **`operations.sh` gained five new resolvers** — `idea.promote`, `idea.defer`, `idea.dismiss`, `idea.merge`, `idea.review-icebox`. All four mutation verbs emit `params.stateId` from `state_ids.<role>` via the new `linear_state_id()` helper, with the conditional-merge pattern so absent state_ids omits the key rather than emitting an empty string.
- **`docs-check.sh` gained three new subcommands** — `idea-review-icebox` (Icebox items ≥60d), `idea-migrate-state` (one-shot legacy-vocab rewrite with timestamped backup, idempotent). `cmd_idea_count` and `cmd_idea_list` extend to five-state vocab with transparent legacy-alias translation (backward-compat for pre-feature logs). `cmd_idea_update` validates status vocabulary. `radar-gather` emits `ideas.icebox_stale_count`.
- **`/idea` skill rewritten** for fully agentic triage — four programmatic outcomes via state ID, new `/idea review-icebox` section, pending-log schema covers all five op types (add/promote/defer/dismiss/merge). `/radar` skill surfaces Icebox-stale count ambiently.
- **6 legacy items migrated post-merge** (BTS-113/115/116/117/118/119) from custom "Idea" state to real `Backlog` state via `save_issue` with explicit state UUID. State-ID path finally unblocks what the name-based path silently no-op'd earlier this session.
- **2 new Linear ideas captured via the shipped path**:
  - **BTS-120** — `/pr` validate halts on session-boundary stasis mismatch every time. Hit twice in consecutive sessions. Three fix options outlined (validator tolerance / step re-order / separate stasis slot).
  - **BTS-121** — AC-1's "Linear auto-routes to Triage" assumption was empirically wrong. Captures via API land in the team's default new-issue state (Backlog for Blocktech Solutions), not Triage. `/idea triage` listing misses fresh captures entirely. 5-line fix: re-add stateId=triage in `idea.add` resolver (keeps agent-ownership, requires state_ids populated).
- **Drive-by fix** — `pr.md` step 7 restored explicit `docs/{spec,plan,stasis}.md` mention (stasis-recall bats invariant that PR #43's refactor inadvertently dropped).
- **Memory saved** — `feedback_agentic_agency_first`: every external-system workflow action must be ccanvil-reachable programmatically; UI-only paths destroy agentic agency. Born from the "use Linear's native Triage UI shortcuts" pushback; directional rule for every future integration.
- **`.claude/ccanvil.local.json` populated** with the five state UUIDs for Blocktech Solutions (Triage, Backlog, Icebox, Canceled, Duplicate) — operator bootstrap for the new state-ID path. Not committed (gitignored, per design).

## Current State

- **Branch:** `main` at `ed37701`, synced with origin.
- **Tests:** 804/804 bats green at PR HEAD; post-merge on main: not re-run (squash-merge is fast-forward-equivalent, no code mutation).
- **Uncommitted changes:** none.
- **Build status:** clean.

## Blocked On

- Nothing.

## Next Steps

1. **Ship BTS-121 fix** (AC-1 gap) — re-inject `stateId: <triage>` in `operations.sh` `idea.add` Linear resolver. 5-line code change + test. Without this, every `/idea` capture on Linear-configured nodes skips Triage review and lands straight in Backlog. This is the highest-leverage next feature: it's the actual unblocking fix for the five-state model to function as designed.
2. **Ship BTS-120 fix** (`/pr` validate halt) — lowest-friction path is step re-order: run `pr-cleanup` before `validate` so the stasis-mismatch self-resolves before the check. Small; could bundle with BTS-121.
3. **Triage the 5 Triage items** (idea-count: `triage: 5` — includes BTS-121 captured correctly, plus 4 others). Run `/idea triage` for priority assignment + promote/defer/dismiss/merge outcomes.
4. **Pick next feature from Backlog.** Top candidates by priority:
   - **BTS-118** (High) — stop chaining bats + codify file-scoped TDD. This session exemplified the anti-pattern (caught at Step 3, switched to single-run+grep). Codifying in `.claude/rules/tdd.md` would prevent the recurrence.
   - **BTS-119** (Medium) — auto-transition linked Linear issue to Done on PR merge. Now enabled by the `state_ids` infrastructure shipped this session. One level up from BTS-114.
   - **BTS-113** (Medium) — stale `recommend` output after `/stasis+/compact+/recall` cycle. One-line fix.

## Context Notes

- **Dogfooded closure — second consecutive.** PR #43 auto-complete-spec-on-merge validated its own archive transition during its own merge. PR #44 idea-triage-native did the same AND additionally enabled the 6-item Linear migration smoke test on the same feature's infrastructure. Both features self-validated within the same session they shipped.
- **State-ID path is the only reliable programmatic route.** Linear's `save_issue state` field accepts "type, name, or ID" — it resolves ambiguously. When "Backlog" is both a state type AND a state name in the same workspace, passing `state: "Backlog"` matches the type and becomes a no-op for items already in type=backlog (even if their state NAME is "Idea"). Discovered this mid-session when 6 promotions silently did nothing; state-ID dispatch resolved it after Linear's Triage enablement + workspace statuses query. This is now codified in `operations.sh` via the `linear_state_id` helper + `state_ids` config block.
- **Linear Triage auto-routing isn't automatic.** The Linear docs claim API-created issues auto-route to Triage when enabled, but that's only true if the team's default new-issue state is Triage OR workspace routing rules explicitly direct API-created issues there. For Blocktech Solutions, the default is Backlog. Captures via MCP therefore bypass Triage unless the resolver passes `stateId: <triage>` explicitly. BTS-121 captures the fix.
- **`/review` caught two CRITICAL bugs that TDD tests missed.** The code-reviewer agent identified: (a) `idea.promote/defer/dismiss` emitted `stateId: ""` when state_ids absent (silent no-op or API error path), (b) `idea.merge` had inconsistent OP_ARGS semantics between Linear (target) and local (source). Neither showed up in my 32 new bats tests because I tested only the happy path. Adding "no state_ids" tests for all four mutations (via `_linear_config_no_state_ids` fixture) took 5 tests. Lesson: `/review` after TDD is not redundant — it catches configuration-edge-case bugs that happy-path TDD misses.
- **Bats-chain anti-pattern self-caught.** At Step 3 I ran `bats ... | grep ok` then `bats ... | grep not ok` as separate commands. Noticed, stopped, switched to `bats > /tmp/out.out 2>&1; grep -cE ... /tmp/out.out`. This is exactly BTS-118. Codification in `.claude/rules/tdd.md` would prevent recurrence — single-run + derived-from-capture should be the baseline pattern.

## Determinism Review

- **operations_reviewed:** ~40 (validate + radar-gather + 2 idea triage (1 failed-names, 1 ok) + 3 Linear saves + 13 TDD commits + 1 review-fix + /pr + merge + land + 6 migration MCPs + 2 dogfood captures + stasis data-gather + legacy-refs pass)
- **candidates_found:** 2

- **Manually populating `.claude/ccanvil.local.json.state_ids`**: I ran `list_issue_statuses`, hand-built the state_ids JSON block, and Wrote the file. This is deterministic-by-algorithm: call list_issue_statuses, select the 5 roles by name match, write back to local config. Should be `docs-check.sh idea-state-ids --sync` (or `operations.sh resolve idea.state-ids --bootstrap`) that does the MCP call + config write in one step. Recurs every time a new Linear-configured node bootstraps. **Impact: medium-recurring** (once per node, but every node).
- **Pre-`/pr` one-shot `rm docs/stasis.md && validate` dance**: Running validate, hitting mismatch, manually removing the stale stasis, re-validating — this is exactly the BTS-120 pattern. It's not a new candidate since it's captured, but it IS a determinism-review candidate by definition (recurring, deterministic cleanup dressed as reasoning). **Impact: medium-recurring** (every /pr). Captured as BTS-120.

## Cross-Session Patterns

- **RESOLVED — `bats` 3×-chain anti-pattern caught in the act.** Previous stasis flagged this as a NEW PATTERN; this session self-caught at Step 3 and switched to single-run-derived output. Pattern downgraded from "unobserved" to "observed + corrected reflexively" — still needs the rule codification (BTS-118) to generalize.
- **RESOLVED — spec-In-Progress-after-merge (3rd session clean).** The auto-complete-spec-on-merge feature shipped in PR #43 has now closed 2/2 merges cleanly (this one via its own primary path). Pattern remains closed; dogfooded twice.
- **RECURRING — session-boundary stasis blocks `/pr` validate.** Hit in PR #43's /pr and hit again in this session's /pr. Captured as BTS-120. Will recur until BTS-120 ships (validator tolerance or step re-order).
- **RECURRING — Linear issue state diverges from git reality at merge.** Last session flagged this as "first observation." This session manually moved BTS-114 to Done post-merge AND moved the 6 legacy-Idea items to Backlog post-merge — all manual. Captured as BTS-119. Will recur until BTS-119 ships.
- **NEW PATTERN — TDD-only tests miss configuration-edge-case bugs.** `/review` found two CRITICAL issues (both resolver-edge-case) not covered by 32 passing bats tests. Pattern: when writing tests during TDD, the "happy path fixture" is the only one that gets the "no config" variant should be added as a standard rung. Prefer: after each resolver's happy-path test, immediately add the "config missing this field" variant. Predicted to recur on any feature that extends `operations.sh` adapter output. Capture candidate for a follow-up idea.
- **legacy-refs-scan: 162 total, 70 hub-owned, 92 node-specific** — identical counts to previous two stasis snapshots. Stable. All 70 hub-owned are allowlist-covered historical archives; next `/ccanvil-pull` will propagate nothing new.
- **RESOLVED 4/4 — ALLOW_MAIN=1 + unpushed main = divergence.** Fourth consecutive clean session. Push-guard correctly blocked activate at the start of the session (caught the unpushed post-session stasis from the previous session). Pattern remains closed.

## Security Review

**PASS.** Session diff reviewed via `security-audit.sh --files-only`:
- New functions in docs-check.sh (`cmd_idea_review_icebox`, `cmd_idea_migrate_state`) + extended validators: pure shell + jq + existing helpers. No network, no credentials.
- New resolvers in operations.sh (`idea.promote/defer/dismiss/merge/review-icebox`): JSON emission only; no runtime dispatch.
- Skill prose rewrites (`/idea`, `/radar`): documentation, no secrets.
- `.ccanvil/guide/command-reference.md`: doc rows only.
- `docs/specs/idea-triage-native.md`: public design doc.
- `.claude/ccanvil.local.json` update: populates Linear state UUIDs — these are IDs, not secrets. Gitignored file, not committed.
- Linear captures (BTS-120, BTS-121) + 6 save_issue transitions: metadata only; no secrets, no PII.
- `pr.md` drive-by fix: prose update, no secrets.
- No `.env`, token, private key, or credential file touched. Diff audit clean.

## Memory Candidates

- **Feedback (saved this session):** `feedback_agentic_agency_first` — every external-system workflow action must be ccanvil-reachable programmatically; UI-only paths destroy agentic agency. Born from rejecting the "just use Linear's Triage UI shortcuts" option. Lives at `~/.claude/projects/-Users-zacharywright-projects-ccanvil/memory/feedback_agentic_agency_first.md` and linked in MEMORY.md.
- **Project fact (worth saving):** Linear's `save_issue state` parameter resolves "type, name, or ID" ambiguously. When the workspace has both a state type AND a state name with the same string (e.g., "Backlog"), name-based dispatch silently becomes a no-op. **Always dispatch by state UUID** for state transitions. Codified in `operations.sh:linear_state_id()` + `state_ids` config block.
- **Project fact (worth saving):** Linear's "Triage auto-routes API-created issues" claim is conditional on team workflow defaults + workspace routing rules, not on the Triage feature being enabled. For Blocktech Solutions, API captures land in Backlog (team default), not Triage. `/idea` capture must pass `stateId: <triage>` explicitly. Tracked as BTS-121 for the fix.
- **Reference (worth saving):** Linear team `Blocktech Solutions` state UUIDs — Triage=`53b10a02-...`, Backlog=`0dc23450-...`, Icebox=`58121463-...`, Canceled=`11c6b96a-...`, Duplicate=`7523382f-...`. Live in `.claude/ccanvil.local.json.integrations.providers.linear.state_ids`. Treat as workspace reference data; regenerate via `list_issue_statuses` if Linear workflow changes.
- **Pattern worth codifying:** `/review` after TDD catches configuration-edge-case bugs that happy-path bats tests miss. This session: 2 CRITICALs found post-TDD, 0 caught by bats alone. Argues for `/review` as a non-optional gate, not an aspirational one.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
