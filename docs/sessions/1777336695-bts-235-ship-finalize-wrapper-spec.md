# Feature: ship-finalize substrate — collapse post-/pr ship cycle into one verb

> Feature: bts-235-ship-finalize-wrapper
> Work: linear:BTS-235
> Created: 1777336342
> Status: In Progress

## Summary

Every ship cycle ends with the same 4-step sequence: `assert-pr-title` (forces title to `feat(<id>): <subject>`) → `gh pr ready <N>` → `gh pr merge <N> --squash --delete-branch` → manual `ticket.transition <ID> done` (because `gh pr merge`'s `--delete-branch` switches to main, bypassing `/land`'s feature-branch AUTO-CLOSE emission path even though `cmd_land`'s on-main recovery path SHOULD work — but only if `/land` is actually called).

Session 8 paid this cost 4 times today (BTS-232, 233, 234, plus the BTS-235 ship in progress). At \~20 stochastic operations per release, this is the highest-leverage determinism candidate currently surfaced.

This ship adds `cmd_ship_finalize` substrate that takes a PR number and runs the full sequence: title-fix → ready → merge → land → auto-close → idempotent return. Plus a `/ship` skill for ergonomic operator dispatch.

## Job To Be Done

**When** I have a draft PR ready to merge after running `/pr` (PR is reviewed, branch tests pass, lifecycle docs are clean),
**I want to** run a single command that handles title-fix + ready + merge + branch-cleanup + ticket-close,
**So that** I don't re-derive the title, re-emit four `gh` commands, AND remember the manual `ticket.transition done` after every single ship.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** New substrate `docs-check.sh ship-finalize <PR-NUMBER> [--project-dir <path>]` exists. Invoked with no PR number → exits 2 with usage. Invoked with valid number → runs the sequence below.
- [ ] **AC-2:** **Pre-flight** — `gh pr view <N>` confirms the PR exists and `state != MERGED`. If already merged, exit 0 with `{pr_merged: true, ...}` (idempotent — re-running on a merged PR is a no-op, not an error). If PR doesn't exist, exit 1 with error.
- [ ] **AC-3:** **Title fix** — calls `cmd_assert_pr_title <N>` (BTS-178 substrate, idempotent). If `gh pr edit` fails (network/auth), exit 1 with `{step: "title", error: ...}`. On success, the result `{updated:bool, expected, actual}` is preserved into the final summary's `title_result` field.
- [ ] **AC-4:** **Mark ready** — `gh pr ready <N>`. Already-ready PR returns non-zero stderr message (`already "ready for review"`) — captured but treated as success (idempotent).
- [ ] **AC-5:** **Merge** — `gh pr merge <N> --squash --delete-branch`. On success the local branch is deleted and HEAD switches to main. On failure (mergeable conflict, etc.), exit 1 with `{step: "merge", error: ...}` and DO NOT proceed to land.
- [ ] **AC-6:** **Land + auto-close** — invokes `cmd_land` from main (post-merge); captures its stdout; greps for the `AUTO-CLOSE: {...}` marker (BTS-138). When the marker is present, parses the JSON and dispatches `ticket.transition <id> done`. On dispatch failure, appends to `.ccanvil/ideas-pending.log` via `cmd_idea_pending_append --op ticket.transition` (BTS-119 pattern). Auto-close failure NEVER fails the ship-finalize call — same idempotency contract as `/land`.
- [ ] **AC-7:** **Output** — emits JSON `{pr_merged: bool, branch_deleted: bool, title_result: {...}|null, ticket_closed: bool|null, errors: [], pr: <N>}` to stdout. Exit 0 on full success; exit 1 on any pre-merge failure (title/ready/merge); exit 0 with `ticket_closed: false` if only the post-merge auto-close fails (logged in `errors` array).
- [ ] **AC-8:** New `/ship` skill at `.claude/skills/ship/SKILL.md` — invocation `/ship <PR-NUMBER>`. Calls `bash .ccanvil/scripts/docs-check.sh ship-finalize <N> --project-dir .`, surfaces the JSON summary as a one-line operator-readable status (`Shipped PR #N: title=<status> | merged=<bool> | ticket=<status>`), exits with the substrate's exit code.
- [ ] **AC-9:** New bats `hub/tests/ship-finalize.bats` covers AC-2 (already-merged idempotency), AC-3 (title force-update flow), AC-5 (merge-failure halt), AC-6 (auto-close success + auto-close failure → pending log), plus a drift-guard for `BTS-235` inline in `docs-check.sh`. Live `gh` calls stubbed via `GH_OVERRIDE` env (mirrors `LINEAR_QUERY_OVERRIDE` pattern from BTS-203).
- [ ] **AC-10:** Full bats suite remains green at ≥ 1819 (post-BTS-234 baseline). Existing `cmd_land`, `cmd_assert_pr_title`, `cmd_idea_pending_append` callers continue to pass — the new substrate only orchestrates them.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/docs-check.sh` | New `cmd_ship_finalize` function + dispatch entry. Add `ship-finalize` to `PROJECT_TREE_SUBCOMMANDS`. Recognize `GH_OVERRIDE` env var to redirect `gh` calls during tests. |
| `.claude/skills/ship/SKILL.md` | New skill file. Skeletal — accepts PR number arg, dispatches substrate, summarizes. |
| `hub/tests/ship-finalize.bats` | New bats covering AC-2 through AC-9. Stubbed `gh` and `linear-query.sh`. |

## Dependencies

* **Requires:** BTS-178 (`assert-pr-title` substrate); BTS-138 (`auto-close-emit` and `cmd_land_recover_branch`); BTS-119 (`/land` AUTO-CLOSE pattern); BTS-179 (`idea-pending-replay` for the queue path); BTS-128 (`ticket.transition` resolver); BTS-212 (PROJECT_TREE_SUBCOMMANDS contract). All shipped.
* **Blocked by:** Nothing.

## Out of Scope

* **Replacing** `/pr`'s pre-merge work. `/pr` still owns pr-cleanup + push + create-PR. `/ship` only handles the post-/pr cycle. Two-command flow: `/pr` (ready) then `/ship <N>` (merge + land + close).
* **Auto-detecting PR number from current branch.** Operator must pass it explicitly. Auto-detection is a follow-up if friction surfaces.
* **Recovering from a partial-state failure mid-sequence.** If merge succeeds but land fails (e.g., dirty working tree on main from concurrent work), the operator manually runs `bash docs-check.sh land`. The substrate reports the failure step in the JSON output.
* **Non-GitHub repo support.** Local-only repos have a different lifecycle (no `gh pr merge`); they continue using `bash docs-check.sh land --force`. The substrate exits 2 with a clear error message on non-github repos.
* **Concurrent ship-finalize calls on the same PR.** Single-operator workflow assumed (same trade-off as `cmd_idea_pending_replay`).

## Implementation Notes

* `gh` substitution for tests: introduce `GH_OVERRIDE` env var mirroring `LINEAR_QUERY_OVERRIDE` (BTS-203). When set, the substrate uses `bash $GH_OVERRIDE` instead of bare `gh`. Tests stub the override to canned responses.
* **Sequencing rationale:** title-fix BEFORE ready ensures the squash-merge subject is correct (gh inherits PR title). Ready BEFORE merge because `gh pr merge` requires non-draft state on most repo configs. Merge → land → auto-close as a strict pipeline.
* **Idempotency** at every step: assert-pr-title is idempotent (BTS-178 contract); gh pr ready returns success on already-ready PRs; gh pr merge on already-merged PRs is detected by AC-2's pre-flight; cmd_land on main is idempotent (BTS-138).
* **Output format:** JSON for machine consumption. `/ship` skill prose renders the operator-readable summary line.
* **No live-API gate:** the contracts here (`gh pr` calls, Linear `ticket.transition`) are all already proven by existing substrate. The new code is composition-only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
