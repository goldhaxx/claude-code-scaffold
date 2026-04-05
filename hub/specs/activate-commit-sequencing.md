# Feature: Activate Commit Sequencing

> Feature: activate-commit-sequencing
> Created: 1774588800
> Status: Complete

## Summary

Change `docs-check.sh activate` to commit the spec status update and `docs/spec.md` copy on the new feature branch instead of leaving them uncommitted. Currently, specs must be committed to `main` before activation (clean worktree requirement), and the status change is left uncommitted on the branch. After squash-merge, the spec commit on `main` and the squash commit both touch `docs/specs/*.md`, causing divergent histories that require `git pull --rebase` + `git rebase --skip` to resolve.

## Job To Be Done

**When** I activate a spec and later squash-merge the feature PR,
**I want to** return to `main` with a clean `git pull`,
**So that** I don't have to manually resolve divergent branches after every feature.

## Root Cause

The current `cmd_activate` flow:

1. **Requires** clean worktree → spec file must already be committed on `main`
2. Creates feature branch from `main`
3. Modifies `docs/specs/*.md` (status → In Progress) and copies to `docs/spec.md`
4. Leaves these changes **uncommitted**

The user/Claude then commits the status change on the branch. After squash-merge, `main` has: (a) the original spec commit and (b) a squash commit that also modifies `docs/specs/*.md`. This creates duplicate changes to the same file across different commit lineages.

## Proposed Fix

`cmd_activate` should:
1. Allow the spec file to be uncommitted (don't reject dirty worktree for spec-related files)
2. Create the branch
3. Update spec status + copy to `docs/spec.md`
4. Auto-commit all spec-related changes on the branch

This ensures `main` never has a spec commit — the spec addition and activation are both on the feature branch, and squash-merge cleanly collapses them.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `activate` succeeds when `docs/specs/<id>.md` is the only uncommitted file (previously rejected)
- [ ] **AC-2:** `activate` succeeds when both `docs/specs/<id>.md` and `docs/spec.md` are uncommitted
- [ ] **AC-3:** `activate` still fails if non-spec files are uncommitted (safety guard)
- [ ] **AC-4:** After `activate`, the branch has exactly one commit containing: spec status update in `docs/specs/<id>.md`, and `docs/spec.md` copy
- [ ] **AC-5:** The auto-commit message follows convention: `docs(lifecycle): activate <feature-id>`
- [ ] **AC-6:** After `activate`, the worktree is clean (no uncommitted changes)
- [ ] **AC-7:** `activate` still fails if another spec is In Progress
- [ ] **AC-8:** `activate` still fails if feature-id not found
- [ ] **AC-9:** Existing tests pass (updated for new behavior where needed)
- [ ] **AC-10:** After squash-merge simulation, `main` has no divergent history (no rebase/skip needed)

## Affected Files

| File | Change |
|------|--------|
| `scripts/docs-check.sh` | Modify `cmd_activate` — relax worktree check, add auto-commit |
| `tests/feature-lifecycle.bats` | Update activate tests for new commit behavior, add AC-1 through AC-10 tests |

## Dependencies

- **Requires:** None
- **Blocked by:** None

## Out of Scope

- Changing `cmd_complete` behavior (it runs on `main` after merge, which is correct)
- Changing the spec backlog directory structure
- Modifying squash-merge or PR creation workflows
- Adding spec creation to `activate` (spec authoring remains a separate step)

## Implementation Notes

- The dirty-worktree check should use a targeted approach: reject if `git status --porcelain` shows files outside `docs/specs/` and `docs/spec.md`
- The auto-commit should `git add docs/specs/<id>.md docs/spec.md` (only the specific files, not `-A`)
- Consider: if `docs/spec.md` already exists from a previous feature, it will be overwritten — this is correct and expected
- The squash-merge simulation test (AC-10) can create a branch, make commits, `git merge --squash`, then verify `git pull` works cleanly on a second clone/worktree

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
