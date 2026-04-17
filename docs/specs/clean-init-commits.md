# Feature: Clean Init & Broadcast Commits

> Feature: clean-init-commits
> Created: 1776386558
> Status: Draft

## Summary

Three rollout gaps discovered during node-uuid-registry deployment: (1) `cmd_register` mutates the hub's `.ccanvil/registry.json` without committing it, so every `/init` leaves the hub dirty; (2) `migrate_registry` (called at the start of `cmd_broadcast`) dirties the hub mid-broadcast and breaks pre-check for every subsequent node; (3) nodes that gitignore `.ccanvil/ccanvil.lock` (e.g. taxes) fail the bootstrap commit because `git add` refuses ignored files. Together these make a fresh init require manual hub commits and partial broadcast runs require manual recovery. This feature auto-commits hub-owned registry mutations and makes bootstrap tolerant of gitignored lockfiles.

## Job To Be Done

**When** I run `/init` in a new project or `broadcast` from the hub,
**I want to** have the hub and nodes end the operation in clean, committed state,
**So that** I don't need to cd between projects to chase down dirty working trees after sync events.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_register`, after mutating `<hub>/.ccanvil/registry.json`, commits only that file in the hub repo with message `chore(registry): register <name> [<uuid>]`. Bypasses `protect-main.sh` via `ALLOW_MAIN=1`. Does not touch any other dirty file.
- [ ] **AC-2:** `cmd_register` skips the auto-commit if the hub path is not a git repo (`git -C <hub> rev-parse` fails) or if the registry was not actually modified (no-op idempotent register). No error, just skip.
- [ ] **AC-3:** `migrate_registry`, after converting legacy path-keyed entries, if it modified `registry.json`, auto-commits it with message `chore(registry): migrate to UUID keys`. Same ALLOW_MAIN bypass. No commit if migration was a no-op.
- [ ] **AC-4:** `cmd_broadcast`'s batch `last_synced` update at loop end auto-commits the registry with message `chore(registry): record broadcast sync` so the hub stays clean after every broadcast.
- [ ] **AC-5:** The bootstrap commit in `cmd_broadcast` (when a node's sync script was bootstrapped by pre-check) runs `git check-ignore` on `.ccanvil/ccanvil.lock` before `git add`. If the lockfile is gitignored, bootstrap commits only `.ccanvil/scripts/ccanvil-sync.sh`.
- [ ] **AC-6:** After `/init` in a fresh project, the hub's `.ccanvil/registry.json` is committed and the hub working tree is clean (verified by `git -C <hub> status --porcelain` returning empty for `.ccanvil/registry.json`).
- [ ] **AC-7:** After a `broadcast` run that includes a legacy path-keyed registry, the hub is fully committed (migrated registry + last_synced updates) and no manual commits are needed.
- [ ] **AC-8:** Error case: if the auto-commit fails (e.g., pre-commit hook fails, gpg signing error), the command prints a warning but continues (does not error-out the full init/broadcast). The registry is still correctly written; only the commit was skipped.
- [ ] **AC-9:** All existing tests pass — no regressions. New tests in `hub/tests/clean-init-commits.bats` cover each of the three fixes end-to-end.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — `cmd_register` (auto-commit), `migrate_registry` caller (auto-commit), `cmd_broadcast` batch update (auto-commit), bootstrap (tolerant of gitignored lockfile) |
| `hub/tests/clean-init-commits.bats` | New — tests for all three fixes |

## Dependencies

- **Requires:** node-uuid-registry (already shipped — UUID-keyed registry)
- **Blocked by:** Nothing

## Out of Scope

- Auto-committing files in the *node* after `/init` (e.g., the new `ccanvil.local.json` + lockfile). That remains the user's responsibility as part of their initial project commit.
- Rollback / undo of auto-commits. If a registry mutation was wrong, user reverts manually.
- Auto-pushing the committed registry to origin. Local commit only; user pushes when ready.
- Broadcast-time UUID generation for nodes that don't yet have one. Already handled by `migrate_registry` in a previous change.

## Implementation Notes

- **Auto-commit pattern** (follows existing bootstrap commit in `cmd_broadcast` at lines 2025+):
  ```bash
  (cd "$hub_root" && \
    ALLOW_MAIN=1 git add .ccanvil/registry.json && \
    ALLOW_MAIN=1 git -c commit.gpgsign=false commit -m "chore(registry): ..." --quiet 2>&1) || true
  ```
- **Dirty check before commit:** `git -C "$hub_root" diff --quiet -- .ccanvil/registry.json || { commit }`. If `diff --quiet` returns 0, nothing to commit — skip.
- **Gitignore check:** `git check-ignore -q .ccanvil/ccanvil.lock` returns 0 if ignored, 1 if tracked. Invert to decide whether to include in `git add`.
- **Failure tolerance (AC-8):** Wrap the commit subshell in `|| echo "WARNING: ..."` so a hook failure doesn't bubble up.
- **Test pattern:** Follow `hub/tests/node-uuid-registry.bats` setup (temp HUB + NODE, git init, lockfile bootstrap). Assert `git -C "$HUB" status --porcelain` is empty after the operation.
