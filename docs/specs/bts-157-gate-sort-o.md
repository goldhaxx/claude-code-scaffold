# Feature: Gate `sort -o FILE` via workspace fence

> Feature: bts-157-gate-sort-o
> Work: linear:BTS-157
> Created: 1777153313
> Status: Complete

## Summary

Close the structural gap where `sort` operates as a writer via the `-o FILE` flag and bypasses the workspace fence. The fence's verb-leading regex catches rm/cp/mv/chmod/chown/bash/find but not sort. Adding `sort` to that regex enables the existing path-token iteration to apply the workspace fence to ANY path argument (including `-o`'s target). Path A scope per spec — broad output-flag fence (Path B: sed -i, tee, shell redirect for non-fence-aware verbs) is deferred.

## Job To Be Done

**When** an agent or operator runs `sort -o FILE input` with FILE outside `~/projects/`,
**I want to** have the workspace-fence hook block the write,
**So that** the read-only-by-name `sort` utility cannot silently overwrite files outside the workspace through its `-o` writer flag.

## Acceptance Criteria

- [ ] **AC-1:** `sort -o ~/.zshrc input` exits 2 via guard-workspace; stderr identifies `~/.zshrc`.
- [ ] **AC-2:** `sort -o /etc/foo input` exits 2.
- [ ] **AC-3:** `sort -o ./local-output input` exits 0 (relative path, no fence violation).
- [ ] **AC-4:** `sort -o ~/projects/ccanvil/foo input` exits 0 (inside workspace).
- [ ] **AC-5:** `sort -o /tmp/foo input` exits 0 (whitelisted system temp).
- [ ] **AC-6 (bypass):** `ALLOW_OUTSIDE_WORKSPACE=1 sort -o ~/.zshrc input` exits 0.
- [ ] **AC-7:** `sort input` (no -o, stdout only) exits 0 — no path tokens to fence.
- [ ] **AC-8 (bonus):** `sort input > ~/.zshrc` exits 2 — the token scan catches the redirect target incidentally because `sort` is now a gated verb. (Path B-adjacent free win.)
- [ ] **AC-9 (word anchor):** `xsort -o ~/.zshrc x` exits 0 — `sort` regex requires word boundary.
- [ ] **AC-10 (existing gates intact):** All pre-BTS-157 guard-hooks tests pass.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | Add `sort` to gated-verb regex (line 31) |
| `hub/tests/guard-hooks.bats` | ~9 tests covering AC-1 through AC-9 |

## Dependencies

- **Requires:** Nothing. Builds on the existing path-fence machinery.
- **Blocked by:** Nothing.

## Out of Scope

- **Path B (broad output-flag fence).** Generalizing destination-flag detection across `sed -i`, `tee FILE`, shell redirection (`>`/`>>`) for non-fence-aware verbs (awk, grep, paste, comm, etc.). Deferred — separate ticket.
- **`uniq -o FILE`.** Some implementations of `uniq` accept `-o`. Not in current Bash(uniq:*) permission set; revisit if/when it becomes operationally relevant.
- **`sort -o $VARIABLE`.** Variable indirection limitation, same as the existing rm/cp/mv set.

## Implementation Notes

- **One-line change.** Add `sort` to `guard-workspace.sh:31`'s verb regex: `(rm|cp|mv|chmod|chown|bash|find|sort)`. Token iteration already scans every path argument; no special-casing for `-o` needed.
- **Header comment refresh.** Add `sort` to the verb list in the file header (line 3) for consistency.
- **Tests.** Mirror BTS-155's pattern. Use `set -e` per BTS-127 on any test with ≥2 assertions.
- **No hooks.md change required.** The guard-destructive row in the table doesn't enumerate the workspace-fence verbs; the workspace fence row was missing before BTS-156 and we didn't add it. Keeping the table tight.
