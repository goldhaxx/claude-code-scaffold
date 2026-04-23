# Stasis

> Feature: session-2026-04-23-bts-121-triage-routing-ship
> Last updated: 1776971680
> Plan hash: fc7b17a0 (plan shipped in PR #45 — 9 TDD steps, cleaned at merge)
> Session objective: Ship BTS-121 (`idea.add` → Triage via stateId). Dogfood-validate the lifecycle end-to-end on a single-session ship. Capture new findings via the shipped path.

## Accomplished

- **Shipped PR #45 (`d8cb90e`)** — `idea-add-triage-routing`. 4 new bats tests (AC-1/2/3/5). Full suite: **808/808 green** (+4 from prior 804 baseline). Clean squash-merge, FF land, dogfooded archive closure via `pr-cleanup`. Live smoke test (BTS-126) confirmed capture → Triage on first try; smoke ticket canceled post-verification. BTS-121 transitioned to **Done** in Linear with PR-link attached.
- **`.ccanvil/scripts/operations.sh`** — `idea.add` Linear resolver now pulls `state_ids.triage` via `linear_state_id()` helper and conditionally merges `stateId` into the save_issue params using the jq `+` pattern, matching `idea.promote/defer/dismiss/merge` (lines 428-500). When `state_ids` absent or the triage UUID is an empty string, the resolver falls through to team default (backward-compat).
- **Skill + guide docs aligned** — `.claude/skills/idea/SKILL.md:48` and `.ccanvil/guide/command-reference.md:126` now document stateId dispatch and retract the falsified "Linear auto-routes API-created issues to Triage" claim. Resolver comment in `operations.sh:368-375` rewritten with the empirical finding.
- **Superseded test retained** — `hub/tests/ideas-to-linear.bats` AC-15 updated to assert `stateId` absent when fixture lacks `state_ids`, keeping the contract locked from both directions.
- **7 new Linear tickets captured, all in Triage** — BTS-122 (pre-activate guard audit), BTS-123 (pending-log fallback integrity), BTS-124 (ticket-ID in filenames + enforcement), BTS-125 (Linear markdown truncation), BTS-127 (bats test assertion leak), BTS-128 (`ticket.transition` wrapper), BTS-129 (`ticket.find-by-title` wrapper). BTS-127/128/129 captured **post-BTS-121-merge** via the live fixed code path — each landed in Triage on first try with zero manual state transitions. End-to-end production validation.
- **Drive-by**: `.mcp.json` → `.mcp.json.example` rename (fix schema `type: url` → `type: http`; preserve as fork template; explained in CLAUDE.md Fork Setup section). Removed redundant project-scoped `linear-server` from `~/.claude.json:docint`. User's `claude.ai Linear` remote integration is the single source of truth now.
- **Pending-log reconciled** — investigated the "24 pending" alarm; discovered only 1 real entry (pretty-printed over 24 lines → `wc -l` miscount). Drained via `idea-sync --ack`. The miscount + writer-format bug became BTS-123.
- **Session-boundary stasis hit the BTS-120 trap again** — mid-session `/pr` run halted on stasis-mismatch; manual `rm docs/stasis.md` workaround applied. Confirms BTS-120 is recurring and high-leverage.

## Current State

- **Branch:** `main` at `d8cb90e`, synced with origin.
- **Tests:** 808/808 bats green at PR HEAD; post-merge on main: not re-run (squash was FF-equivalent, no code mutation).
- **Uncommitted changes:** none (working tree clean post-`land`).
- **Build status:** clean.
- **Context budget:** 5188 / 8000 tokens = 64.8% (HEALTHY).
- **Permissions audit:** 18 DANGER + 165 UNREVIEWED (long-standing, not introduced this session).

## Blocked On

- Nothing.

## Next Steps

1. **Triage the Linear inbox** — Triage currently holds at least 8 items from this session's captures (BTS-122/123/124/125/127/128/129 + any prior unhandled). Run `/idea triage` to assign priorities + promote/defer/dismiss. BTS-124 and BTS-122 are the highest-leverage candidates for immediate `/spec` promotion.
2. **Ship BTS-120 fix** (`/pr` validate halt on session-boundary stasis) — hit twice now, two consecutive sessions. Lowest-friction fix is step re-order: run `pr-cleanup` before `validate`. Small; one afternoon. Unblocks clean session boundaries going forward.
3. **Ship BTS-122** (pre-activate branch/env-sync guard audit) — comprehensive review + hardening. High surface area but each gap is small and well-scoped. Would retire a class of manual pre-flight workarounds.
4. **Ship BTS-124** (ticket ID in filenames + enforcement hooks) — enables Linear's native GitHub integration to auto-transition tickets on PR merge/open. Also introduces the "no Linear ticket → no spec" hard prerequisite, which downstream affects every future `/spec` invocation. Big-leverage workflow change; specify carefully.
5. **Ship BTS-128** (`ticket.transition` wrapper) — the missing primitive that unblocks BTS-119 (auto-close on merge) and makes future Linear state-UUID work DRY.
6. **Pick from Backlog**: BTS-118 (bats chain anti-pattern — captured earlier, overlaps with BTS-127), BTS-119 (auto-close Linear on merge — now unblocked), BTS-113 (stale recommend after stasis+compact+recall).

## Context Notes

- **Single-session feature lifecycle validated** — spec → activate → plan → TDD → /review → /pr → merge → land all ran clean in one session. Total commit count on the feature branch: 3 (activate, feat, complete). This is the tightest spec-driven ship the repo has seen.
- **BTS-121 self-validated.** Post-merge captures (BTS-127/128/129) landed in Triage with zero manual transitions, empirically confirming the fix in production. Three consecutive first-try successes.
- **Dogfooding cluster**: BTS-122, BTS-123, BTS-124, BTS-125 all surfaced DURING the BTS-121 ship, mostly from pending-log reconciliation (BTS-123), BTS-121's own recurrence in new captures (resolved by the merge), and Linear MCP quirks (BTS-125). The session revealed its own follow-up roadmap.
- **Linear "Done" state UUID discovered** — `bc6aa160-258d-4eae-b3b5-a2575732a188` for Blocktech Solutions team. Not currently in `state_ids` config. Adding `done` to `.claude/ccanvil.local.json:state_ids` would enable `ticket.transition <id> done` and unblock auto-close automation (BTS-119 territory). Called out in BTS-128.
- **Linear's GitHub auto-linking empirically** — Linear returned `gitBranchName: zwright7/bts-124-...` in `save_issue` response; the format is `<user-handle>/<ticket-key-lowercase>-<title-slug>`. Matcher is lenient on prefix, strict on ticket key substring. Evidence captured in BTS-124.
- **Linear `save_issue` silent markdown truncation** — numbered top-level lists with inline-bold leaders + indented sub-bullets are dropped after the first item. Workaround: H3 headings per section. Captured as BTS-125 with full reproduction pattern.
- **`idea-count` is local-only** — on a Linear-routed node, `docs-check.sh idea-count` still queries `.ccanvil/ideas.log` (total=29, triage=5 local), NOT the live Linear workspace. Linear Triage has more. Not a ticket yet, but worth noting: radar-gather's `ideas.*` may under-report on Linear-provider nodes. Consider for a future consolidation.
- **CLAUDE.md `Fork Setup` section added** — project-specific block above `HUB-MANAGED-START`. Documents the `.mcp.json.example` convention so contributors who clone the repo know when to rename-to-activate.
- **`/idea` skill fallback still has BTS-123 bugs** — the skill's reference echo-heredoc writer produces malformed JSON on multi-line bodies, and the `N total pending` count uses `wc -l` against a JSONL file. Both unfixed; BTS-123 captures the full fix. Pending log is currently empty so no immediate impact.

## Determinism Review

- **operations_reviewed:** 28
- **candidates_found:** 2 (both captured this session)
- **Linear state transition by role name**: Claude manually issued `save_issue { id, state: <uuid> }` ~7 times, pasting UUIDs literally from config each time. Should be `operations.sh exec ticket.transition <id> <role>` wrapper. Impact: **medium** (recurring every session; already captured as **BTS-128**).
- **Linear ticket dedup search by title**: Claude ran `list_issues { query: <title> }` manually + scanned results for dup check before pending-log replay. Should be `operations.sh exec ticket.find-by-title <title>` wrapper. Impact: **low** (recurring but smaller N; already captured as **BTS-129**).

## Cross-Session Patterns

- **RECURRING: BTS-120 `/pr` validate stasis-mismatch halt** — prior stasis flagged this; hit again live this session. Third or fourth consecutive occurrence. Priority bump warranted.
- **RECURRING: idea.add → Backlog instead of Triage** — prior stasis captured as BTS-121. **RESOLVED THIS SESSION** (PR #45, d8cb90e).
- **RECURRING: test-cadence codification gap (BTS-118)** — prior stasis flagged bats-chain anti-pattern. Didn't trigger this session (disciplined use of `bats > /tmp/out.out`), but BTS-127 surfaces an adjacent same-family issue (multi-assert exit code leakage). Pattern family is alive; BTS-118 + BTS-127 could merge.
- **Legacy-refs-scan: `/catchup`** — 5 matches in `.ccanvil/guide/command-reference.md` + `foundations.md` + `session-management.md`. Mixed hub-owned + node-specific scope. Pre-existing drift from the stasis/recall rename (PR #39). `/ccanvil-pull` should partially resolve hub-owned matches on downstream nodes; the hub copies themselves still need direct cleanup.
- **Audit-session**: 1 hit — a `jq` snippet inside `docs/specs/idea-add-triage-routing.md`. False positive (the doc was literally documenting the jq pattern itself).

## Security Review

- `security-audit.sh --files-only` run during `/review`: **PASS** (no secrets, PII, emails, dangerous file types).
- No new secrets/tokens/keys introduced this session. Commit diffs scanned clean.
- `.mcp.json.example` contains only a public HTTP endpoint URL — no credentials.

## Memory Candidates

- **Linear GitHub-integration branch-name matcher** (reference): format is `<user-handle>/<ticket-key-lowercase>-<title-slug>`; lenient prefix, strict ticket-key substring requirement. Applies to every future PR workflow that wants auto-status-transitions.
- **Linear `save_issue` markdown quirk** (project/feedback): nested numbered lists with inline-bold leaders are silently truncated server-side; use H3 headings per section for structured content. Relevant every time agentic tooling persists markdown into Linear.
- **Blocktech Solutions "Done" state UUID** (reference): `bc6aa160-258d-4eae-b3b5-a2575732a188`. Not in `.claude/ccanvil.local.json:state_ids` yet but should be added (BTS-128 deliverable).
- **Fork-template convention** (project): `.mcp.json.example` is the in-repo mechanism for sharing MCP config with contributors who clone. Owner's personal `claude.ai` MCP integrations are the working source; the file exists as a signal for fresh clones, not an active config.
- **Single-session lifecycle is viable** (project): spec → activate → plan → TDD → /review → /pr → merge → land ran clean in one sitting for BTS-121. Previous features took longer, but tight scope + clear spec allowed end-to-end in-session ship. Pattern worth repeating for narrow fixes.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
