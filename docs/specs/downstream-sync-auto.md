# Feature: Downstream Sync Automation

> Feature: downstream-sync-auto
> Created: 1776135305
> Status: Draft

## Summary

Add a `broadcast` subcommand to `ccanvil-sync.sh` that iterates over all registered downstream nodes and runs the deterministic pull phases (pre-check, pull-plan, pull-auto, section-merge, finalize) in one pass. Conflicts requiring judgment are collected and reported, not resolved. The registry gains `last_synced` tracking so `/ccanvil-status` can show sync freshness across all nodes.

## Job To Be Done

**When** I make hub changes (new rules, updated commands, script fixes) and want them in all downstream projects,
**I want to** run one command from the hub that propagates auto-updates to every registered node,
**So that** I don't have to `cd` into each project, run `/ccanvil-pull`, and manually shepherd the deterministic steps.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `ccanvil-sync.sh broadcast` iterates over every node in `registry.json`, runs `pre-check`, `pull-plan`, `pull-auto`, section-merges, and `pull-finalize` for each.
- [ ] **AC-2:** Broadcast skips nodes where `pre-check` fails (dirty tree, missing lockfile) and reports them as skipped with the reason.
- [ ] **AC-3:** Broadcast collects conflicts (files needing judgment) per node and reports them at the end, without attempting resolution.
- [ ] **AC-4:** `--dry-run` flag runs the full broadcast without modifying any files in any node.
- [ ] **AC-5:** After a successful broadcast to a node, `registry.json` is updated with `last_synced` (epoch) and `last_synced_version` (hub commit hash) for that node.
- [ ] **AC-6:** `ccanvil-sync.sh registry` output includes `last_synced` and `last_synced_version` fields, showing "never" for nodes that haven't been synced via broadcast.
- [ ] **AC-7:** Broadcast operates from the hub directory — it `cd`s into each node path, runs sync commands, then returns. It does NOT require being inside the node.
- [ ] **AC-8:** If a registered node path does not exist on disk, broadcast reports it as unreachable and continues to the next node.
- [ ] **AC-9:** Broadcast summary at the end shows: nodes synced (count), nodes skipped (count + reasons), conflicts pending (count + file list per node).
- [ ] **AC-10:** Existing `pull-auto`, `pull-plan`, `pull-finalize`, and `section-merge` subcommands are NOT modified — broadcast orchestrates them.
- [ ] **AC-11:** All tests pass (`bats hub/tests/`), including new tests for the broadcast subcommand.
- [ ] **AC-12:** Error case: when `registry.json` has zero nodes, broadcast prints "No registered nodes" and exits 0.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `broadcast` subcommand, update `registry` output |
| `.ccanvil/registry.json` | Modified — schema gains `last_synced`, `last_synced_version` per node |
| `hub/tests/ccanvil-sync.bats` | Modified — new tests for broadcast |
| `.ccanvil/guide/sync.md` | Modified — document broadcast flow |
| `.ccanvil/guide/command-reference.md` | Modified — add broadcast to command table |

## Dependencies

- **Requires:** Existing `pull-auto`, `pull-plan`, `pull-finalize`, `section-merge` subcommands (all exist)
- **Requires:** `registry.json` with registered downstream nodes (3 exist: fucina, luxlook, fieldnation-toolbox)

## Out of Scope

- Automatic conflict resolution (stays manual — requires Claude judgment)
- Push broadcast (project → hub direction)
- `/ccanvil-pull` command changes (it still works per-project as before)
- Registry auto-discovery (nodes must be registered via `init`)

## Implementation Notes

- Broadcast must run from the hub directory. Use `hub_source` from each node's lockfile or the registry path to locate nodes.
- Each node operation should be wrapped in a subshell to avoid `cd` side-effects polluting state between nodes.
- Section-merge is deterministic (no judgment needed) — include it in the auto phase.
- The existing `pull-plan` output already classifies actions as `auto-update`, `section-merge`, or `conflict` — broadcast uses this classification to decide what to auto-apply vs. defer.
- Guard: broadcast must NOT run `pull-apply` for conflict-classified files. Only `auto-update` and `section-merge` actions.
