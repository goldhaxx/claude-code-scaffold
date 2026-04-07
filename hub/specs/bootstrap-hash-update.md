# Feature: Bootstrap hash auto-update

> Feature: bootstrap-hash-update
> Created: 1775601007
> Status: Complete

## Summary

When `pre-check` bootstraps a newer `ccanvil-sync.sh` from the hub, it copies the file but doesn't update the lockfile hashes. This leaves the sync script permanently showing as "modified" in `status` output and appearing in every `pull-plan` (where it gets skipped with a special-case check). The fix: update lockfile hashes after the bootstrap copy.

## Job To Be Done

**When** the hub has a newer sync script and pre-check bootstraps it,
**I want** the lockfile to reflect the new hash automatically,
**So that** `status` shows "clean" and `pull-plan` doesn't include a skip entry.

## Acceptance Criteria

- [ ] **AC-1:** After bootstrap copy in `pre-check`, the lockfile's `hub_hash` and `local_hash` for `.ccanvil/scripts/ccanvil-sync.sh` are updated to the new file's hash.
- [ ] **AC-2:** After bootstrap, `ccanvil-sync.sh status` shows the sync script as CLEAN (not MODIFIED).
- [ ] **AC-3:** After bootstrap, `ccanvil-sync.sh pull-plan` does not include the sync script in its output.
- [ ] **AC-4:** The special-case skip in `pull-auto` (lines 772-778) can be removed since bootstrap now handles the lockfile update.
- [ ] **AC-5:** All hub bats tests pass (352+).
- [ ] **AC-6:** A new test verifies the bootstrap + lockfile update behavior.

## Affected Files

| File | Change |
|------|--------|
| `preset/.ccanvil/scripts/ccanvil-sync.sh` | Add lockfile update after bootstrap copy in `cmd_pre_check`, remove pull-auto skip |
| `hub/tests/ccanvil-sync.bats` | New test for bootstrap lockfile behavior |

## Implementation Notes

- Use `cmd_lock_update` or direct jq to update both `hub_hash` and `local_hash` after the copy.
- The `hub_version` should also be updated since the hub has new commits (the bootstrap implies the hub is ahead).
- The pull-auto skip (lines 772-778) becomes dead code after this fix — remove it to simplify.
