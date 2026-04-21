# Feature: Registry as local state + events log audit trail

> Feature: registry-local-state
> Created: 1776717600
> Status: Complete

## Summary

`ccanvil-sync.sh` mutates `.ccanvil/registry.json` on every `register` and `broadcast`, then commits the change to the hub repo via `commit_hub_file` — directly on whatever branch is checked out (typically `main`). That violates the canonical GitHub flow's "never commit to local main directly" principle and is the source of every "local has diverged from origin/main" divergence we've hit this session. The underlying problem is that `registry.json` contains per-machine operational state (paths, last-synced timestamps) that never belonged in version control in the first place. This spec reclassifies the registry as local state (gitignored), removes all hub-side commit sites, deletes the now-unused `commit_hub_file` helper, and replaces the lost git-history audit trail with an append-only `.ccanvil/events.log` (JSON-lines) that captures the same events in a more query-friendly form.

## Job To Be Done

**When** I run `register` or `broadcast` on the hub,
**I want** the registry update recorded locally without committing to main,
**So that** `git log` on main stays focused on real code changes and `git pull` after PR merges always fast-forwards cleanly.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.ccanvil/registry.json` is listed in the hub's `.gitignore`. Fresh `git status` on main with a registered downstream node shows a clean tree.
- [ ] **AC-2:** Running `cmd_register` from a downstream node creates/updates `.ccanvil/registry.json` and does NOT create a commit on the hub. `git log -1` is unchanged.
- [ ] **AC-3:** Running `cmd_broadcast` on the hub updates `last_synced` fields in `.ccanvil/registry.json` and does NOT create a commit on the hub. `git status` after broadcast shows no hub-side changes (the gitignored registry mutation is invisible to git).
- [ ] **AC-4:** The `commit_hub_file` helper (current `ccanvil-sync.sh:80-106`) is deleted; all three call sites (`cmd_register:1984`, `migrate_registry:2050`, `cmd_broadcast:2215`) are removed.
- [ ] **AC-5:** Events log exists at `.ccanvil/events.log` (gitignored). Each line is a JSON object with at minimum `ts` (epoch), `event` (enum), and event-specific fields.
- [ ] **AC-6:** `cmd_register` appends one line with `event: "register"`, `node_uuid`, `node_name`, `path` to `.ccanvil/events.log`.
- [ ] **AC-7:** `cmd_broadcast` appends one `event: "broadcast_sync"` line per synced node with `node_uuid`, `node_name`, `from_version`, `to_version`. Skipped or unreachable nodes get `event: "broadcast_skip"` or `event: "broadcast_unreachable"` with a `reason` field.
- [ ] **AC-8:** `migrate_registry` appends one line with `event: "migrate_legacy_keys"` and `count` when one or more legacy entries are rewritten.
- [ ] **AC-9:** `.ccanvil/events.log` is also listed in `.gitignore`.
- [ ] **AC-10:** The events log is append-only and never truncated by the script. If the file doesn't exist, it's created on first write. Malformed existing lines are tolerated (don't abort writes).
- [ ] **AC-11:** New subcommand `ccanvil-sync.sh events [--since <epoch>] [--event <type>] [--node <uuid-or-name>]` tails and filters the log, outputting newline-delimited JSON. With no filters, prints the full log.
- [ ] **AC-12:** Migration: on next hub pull, the existing tracked `.ccanvil/registry.json` is removed from the index via `git rm --cached .ccanvil/registry.json` (one-time, manual) — the spec itself doesn't need to perform this, but the PR includes an `## Upgrade notes` section in the merge commit body covering the command.
- [ ] **AC-13:** Regression: all existing bats tests pass after the rewrite. Tests that previously asserted `commit_hub_file` behavior are replaced by tests asserting "no commit created" + "events log entry written."
- [ ] **AC-14:** Error/edge: If the hub is on a feature branch (not main) when `register` or `broadcast` runs, the commands still succeed and mutate the gitignored file — they just don't try to commit.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — delete `commit_hub_file`; remove 3 call sites; add `append_event` helper; add `cmd_events` subcommand |
| `.gitignore` | Modified — add `.ccanvil/registry.json` and `.ccanvil/events.log` |
| `hub/tests/registry-local-state.bats` | New — tests for AC-1..AC-11, AC-14 |
| `hub/tests/tech-stack-distribution.bats` and `hub/tests/feature-lifecycle.bats` | Modified — update any tests that previously asserted `commit_hub_file` behavior (if any) |
| `.ccanvil/guide/command-reference.md` | Modified — add `events` subcommand entry; update `register`/`broadcast` rows to drop "auto-commits" mentions |

## Dependencies

- **Requires:** nothing. This is a pure refactor that removes coupling rather than adding dependencies.
- **Blocked by:** nothing. PR #36 (git-flow activate/land) is already merged and is the direct prior art.

## Out of Scope

- Rotating, compressing, or size-bounding `.ccanvil/events.log` — append-only indefinitely. Can be addressed later if the file grows unreasonably (realistic ceiling: a few MB per year).
- Shipping events to Linear, Slack, or other external systems — local log is sufficient for Zach's solo use.
- Cross-machine registry sync — each machine has its own registry. If you work on ccanvil from two machines, you re-register projects on each.
- Back-filling `events.log` from existing `chore(registry)` commits in main's git history — starts fresh on merge.
- A `cmd_events --tail` flag (live-follow mode) — out of scope; use `tail -f .ccanvil/events.log` directly.

## Implementation Notes

- **New helper `append_event`:** takes JSON via stdin or as arg, writes one line to `.ccanvil/events.log`. Ensures file exists, appends atomically via `>>` (which is atomic for small writes on POSIX). Add `ts` field if not present. Example call: `append_event "$(jq -nc --arg u "$node_uuid" --arg n "$node_name" '{event:"register",node_uuid:$u,node_name:$n}')"`.
- **Events subcommand:** ~20 lines. Read the file, filter with `jq` on the command-line flags. Usage: `ccanvil-sync.sh events --event broadcast_sync --node taxes --since 1776000000`.
- **Deletion order during implementation:** first add `append_event`; then at each `commit_hub_file` call site, replace with the `append_event` call; then delete `commit_hub_file`; then add the ignore rules and run `git rm --cached`. This keeps the suite green at every intermediate step.
- **Pattern to follow:** `append_event` shape parallels `commit_hub_file`'s failure tolerance — if the write fails (permissions, disk), print WARNING and return 0. Never abort the caller.
- **Test harness:** follow `hub/tests/tech-stack-distribution.bats` for the hub + node fixture pattern. Assert on file contents and commit count (`git rev-list --count HEAD` before/after the operation — should be equal).
- **The `migrate_registry` legacy-keys case:** it's still useful code (downstream nodes with old path-keyed registries can upgrade cleanly) but its commit side-effect goes away. The in-memory mutation and events.log entry remain.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
