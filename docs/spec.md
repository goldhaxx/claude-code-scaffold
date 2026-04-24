# Feature: Auto-close linked Linear issue on PR merge

> Feature: bts-119-auto-close-linear-on-merge
> Work: linear:BTS-119
> Created: 1777004190
> Status: In Progress

## Summary

After a feature PR is merged and `docs-check.sh land` returns main to its clean state, the Linear issue referenced by the archived spec's `> Work: linear:<ID>` metadata auto-transitions to `Done` via the `ticket.transition` wrapper shipped in BTS-128. This closes the last manual, deterministic, recurring cleanup step in the ccanvil lifecycle — the mirror-image fix to BTS-114 (which auto-transitioned the spec archive). On MCP failure the transition is queued to `.ccanvil/ideas-pending.log` for `/idea sync` to replay, so a network blip never blocks the merge.

## Job To Be Done

**When** a feature PR is squash-merged and I run `docs-check.sh land`,
**I want to** have the linked Linear issue automatically transition to `Done`,
**So that** the Linear backlog stays in sync with shipped work without manual status flips.

## Acceptance Criteria

- [ ] **AC-1:** Given a feature branch whose archived spec carries `> Work: linear:<ID>`, when the user runs the post-merge land flow on main, the Linear issue `<ID>` transitions to `Done`.
- [ ] **AC-2:** The transition dispatches through `operations.sh resolve ticket.transition <ID> done` — the BTS-128 primitive — not a hand-assembled `save_issue` payload. Verifiable by unit test: the land flow invokes the `ticket.transition` resolver with the extracted id.
- [ ] **AC-3:** Given `> Work: linear:<ID>` and a successful MCP failure simulation (e.g. mocked tool error), the transition intent appends one JSONL line to `.ccanvil/ideas-pending.log` with shape `{"op":"ticket.transition","args":{"id":"<ID>","role":"done"},"ts":<epoch>}`. The land flow exits 0 — auto-close failure NEVER blocks the post-merge cleanup.
- [ ] **AC-4:** `/idea sync` replays `op:"ticket.transition"` entries by re-resolving `ticket.transition <args.id> <args.role>` and dispatching MCP. On success it acks the entry (same path as `add`/`promote`/`defer`/`dismiss`/`merge`).
- [ ] **AC-5:** Given an archived spec without `> Work:` (legacy/grandfathered), the land flow skips the auto-close step silently — no error, no pending-log entry, no surfaced warning. Matches the validator's existing grandfather rule.
- [ ] **AC-6:** Given `> Work: local:<uid>` (local-provider node), the land flow skips auto-close and logs one line: `auto-close: local provider — skipping (BTS-119 Linear-only)`. Local ideas are not auto-closed in this feature; scope is Linear-only.
- [ ] **AC-7:** Given `> Work: <other-provider>:<id>` (future provider without a `ticket.transition` adapter), the land flow logs: `auto-close: provider '<other>' — no adapter, skipping` and exits 0.
- [ ] **AC-8:** Idempotent: if the Linear issue is already `Done` (e.g. manually transitioned, or pending-log replay), `save_issue` succeeds without error and no duplicate pending-log entry is created.
- [ ] **AC-9:** Determining the just-merged feature-id is deterministic: parse the current feature branch name against `^claude/<type>/(.+)$` BEFORE `cmd_land` switches to main. This reuses the existing post-merge safety-net regex (same extraction point, same branch-name source of truth, no new parser). If the branch doesn't match the convention (e.g. `hotfix/urgent`), skip auto-close and log: `auto-close: no feature-id detected in last merge commit — skipping`. Note: commit-message parsing was considered during spec-writing but rejected — the branch name is already canonical by BTS-130's `activate` convention, and the safety net already parses it for the archive Complete transition.
- [ ] **AC-10:** Bats coverage exists for AC-2 (resolver invocation), AC-3 (pending-log fallback on MCP failure), AC-4 (sync replay of `ticket.transition` op), AC-5 (legacy no-Work skip), AC-6 (local-provider skip), AC-8 (idempotency — issue already Done), and AC-9 (no-match skip). AC-1 is smoke-tested live against the `bts-119-*` branch itself (dogfood close, same pattern as BTS-128).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_land` behavior OR a new helper `cmd_auto_close_work` invoked from `land`. Extracts `Work:` from just-merged spec archive; emits resolve intent OR dispatches via shell path. |
| `.claude/commands/pr.md` OR new `.claude/commands/land.md` | Skill wrapper: runs `cmd_land`, extracts intent, calls `operations.sh resolve ticket.transition`, dispatches MCP `save_issue`, falls back to pending log on failure. |
| `.ccanvil/scripts/operations.sh` | Likely no changes — `ticket.transition done` already works post-BTS-128. |
| `.claude/skills/idea/SKILL.md` | Extend `/idea sync` dispatch table to handle `op:"ticket.transition"` — resolve + dispatch + ack. |
| `hub/tests/auto-close-linear-on-merge.bats` | New — covers AC-2, AC-3, AC-4, AC-5, AC-6, AC-8, AC-9. |

## Dependencies

- **Requires:** BTS-128 shipped (`ticket.transition` wrapper with `done` role). **Done** — PR #47 merged.
- **Requires:** BTS-130 shipped (`> Work:` metadata in spec archives). **Done** — PR #46 merged.
- **Blocked by:** Nothing. Both prerequisites live on main.

## Out of Scope

- Auto-closing on non-merge events (PR close without merge, branch delete, etc).
- Reading `Closes #N` from PR bodies or GitHub's native closes-issue syntax — Linear's GitHub integration already parses this on its side; we rely on `Work:` metadata as the authoritative link, not PR text.
- Auto-canceling / duplicating Linear issues — only the `Done` role is in scope. Other roles remain manual via `/idea triage` or `ticket.transition` direct.
- Local-provider auto-transition — the local log's `idea-update <uid> done` path is a separate ship if the pattern recurs. For now, local specs skip (AC-6).
- Retroactive auto-close for pre-BTS-130 specs without `Work:` — grandfathered silently (AC-5).

## Implementation Notes

- **Hook point:** `cmd_land` is the natural surface — fires post-merge, already reads git state. Option A: extend `cmd_land` to emit a JSON intent after git mechanics succeed, which the `/pr` skill (or a new `/land` skill) dispatches. Option B: keep `cmd_land` shell-only and move the MCP dispatch to a new `/land` skill that sequences `docs-check.sh land → read intent → MCP dispatch → pending-log fallback`. Prefer Option B — keeps shell scripts MCP-free (per deterministic-first: shell for git, skills for provider dispatch).
- **Feature-id extraction on main:** `git log -1 --format=%s main` → regex `^feat\(([^)]+)\):`. Cross-check the captured id against `docs/specs/` to avoid false positives. This is deterministic enough to be a shell function.
- **Work: extraction:** Reuse `docs-check.sh status` which already parses `Work:` via the existing BTS-130 metadata handler (line 151, line 288 in docs-check.sh). New `cmd_extract_work <spec-file>` helper returns `{"provider":"linear","id":"BTS-119"}` or empty.
- **Pending-log op format:** Use `op:"ticket.transition"` with `args:{id, role}` — parallel to existing `op:"add"`, `op:"promote"`, etc. `/idea sync`'s dispatch table gains one row. Same idempotent ack path.
- **Dogfood close:** AC-1 is verified by the BTS-119 branch itself — when this PR merges and lands, BTS-119 should auto-close without touching Linear manually. Same pattern BTS-128 used.
- **Follow BTS-128's combined-`jq -e` test pattern** for the bats suite — keeps new tests out of the BTS-127 silent-leak family.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
