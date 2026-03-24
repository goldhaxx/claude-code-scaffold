# Checkpoint

> Feature: guide-restructuring
> Last updated: 1774328597
> Plan hash: c7474253
> Session objective: BTS-26 (guide restructuring) + BTS-27/BTS-28 backlog + fucina sync + luxlook init

## Accomplished

### BTS-26 complete (all 13 ACs pass, merged PR #5)
- Split GUIDE.md (45.5k chars) into 12 files under `docs/scaffold-guide/`
- Removed duplicate Appendix section
- Moved SCAFFOLD_FRAMEWORK.md → `docs/scaffold-guide/scaffold-framework.md`
- Updated all references: CLAUDE.md, scaffold-sync.sh, hooks, rules, commands, templates, init, tests
- Code review: fixed protect-files.sh path matching (basename → full path), spec path correction, full manifest verification
- 345/345 tests pass
- PR #5 squash-merged, BTS-26 marked Done in Linear

### BTS-27 created (Low, needs-spec)
- scaffold-sync.sh bootstrap hash auto-update — determinism improvement from BTS-24 checkpoint

### BTS-28 created (Medium, needs-spec)
- docs-check.sh activate should commit spec on branch, not main
- Root cause: activate requires clean worktree → spec gets committed to main before branching → squash-merge creates divergent branches on return
- Traced through BTS-24 and BTS-26 occurrences

### Fucina synced with hub
- 9 auto-updates + 12 new scaffold-guide files + 2 deleted (GUIDE.md, SCAFFOLD_FRAMEWORK.md)
- scaffold-sync.sh conflict resolved (take-scaffold after bootstrap)
- Pull-plan now shows `[]` — fully clean

### luxlook initialized
- Explored project structure: iOS Swift/SwiftUI app with git worktree setup
- Committed pending changes (measurement history, export, app mode features)
- Ran `/init` from separate Claude session at `~/projects/luxlook/`
- All 12 scaffold-guide files, lockfile, CLAUDE.md verified in place
- First project initialized with the new `docs/scaffold-guide/` structure (not GUIDE.md)

## Current State

- **Branch:** `main`
- **Tests:** 345/345 passing
- **Uncommitted changes:** This checkpoint
- **Build status:** Clean
- **Fucina:** Synced
- **luxlook:** Initialized, scaffold verified

## Blocked On

- Nothing

## Next Steps

1. **BTS-28:** docs-check.sh activate commit sequencing (Medium, needs-spec) — recurring paper cut
2. **BTS-23:** CLAUDE.md content review — trim to 80-line budget (Medium, needs-spec)
3. **BTS-27:** scaffold-sync.sh bootstrap hash auto-update (Low, needs-spec)
4. **BTS-25:** operations.sh exec subcommand (Low, needs-spec)
5. **BTS-22:** Docs directory strategy (Medium, needs-research)

## Context Notes

- The `docs/scaffold-guide/` restructuring is now the canonical structure — GUIDE.md no longer exists anywhere
- `/init` correctly copies `docs/scaffold-guide/` to new projects (verified on luxlook)
- The git divergence issue (BTS-28) will recur on every feature branch until fixed — workaround is `git pull --rebase` then `git rebase --skip`

## Determinism Review

- **operations_reviewed:** 8
- **candidates_found:** 0
- All file splits used Write tool. All reference updates used Edit tool. scaffold-pull on fucina used script commands (pull-auto, pull-apply, pull-finalize). No manual cp, jq, shasum, or git -C improvised. Manifest verification used manifest-check.sh. No candidates this session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
