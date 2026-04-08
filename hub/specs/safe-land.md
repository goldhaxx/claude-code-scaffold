# Feature: Main branch guard and land command

> Feature: safe-land
> Created: 1775619120
> Status: Complete

## Summary

Two atomic units that prevent git divergence errors during the merge-back flow. A pre-commit hook guards main from direct commits (ensuring the invariant that makes fast-forward safe). A `land` command handles the full post-merge sequence deterministically: verify merged, checkout main, fetch, reset, delete branch.

## Job To Be Done

**When** a PR is merged on GitHub and I need to return to main,
**I want** a single deterministic command that handles the full flow,
**So that** Claude never wastes context on manual git sequences that can fail due to divergent histories.

## Acceptance Criteria

### Main branch guard

- [ ] **AC-1:** A PreToolUse Bash hook blocks `git commit` when the current branch is `main` or `master`. Exit code 2 with message: `"BLOCKED: Direct commits to main are not allowed. Create a feature branch first."`
- [ ] **AC-2:** The hook does NOT block commits on feature branches.
- [ ] **AC-3:** The hook does NOT block non-commit git commands on main (e.g., `git status`, `git pull`, `git merge`).
- [ ] **AC-4:** The hook can be bypassed with `--allow-main` in the commit message (escape hatch for init commits, hotfixes).

### Land command

- [ ] **AC-5:** `docs-check.sh land [--force]` performs the full post-merge flow: verify PR merged → checkout main → fetch → reset to origin/main → delete local branch → delete remote branch.
- [ ] **AC-6:** Land fails if the current branch IS main: `"ERROR: Already on main. Nothing to land."`
- [ ] **AC-7:** Land fails if no merged PR exists for the current branch (unless `--force`): `"ERROR: No merged PR found for branch '<branch>'. Merge the PR first, or use --force."`
- [ ] **AC-8:** Land reports each step as it executes: `"Switched to main" → "Fetched origin" → "Main updated to <sha>" → "Deleted local branch '<branch>'" → "Deleted remote branch '<branch>'" → "Land complete."`
- [ ] **AC-9:** Land handles the case where the remote branch was already deleted (GitHub auto-delete) gracefully — no error, just skips.
- [ ] **AC-10:** Land handles repos with no remote (local-only workflow) — skips fetch/remote-delete, just switches to main.

### Integration

- [ ] **AC-11:** The `/pr` skill (finalize) mentions `land` as the next step after merge: `"After merge, run: docs-check.sh land"`
- [ ] **AC-12:** The workflow rule documents `land` as the final step of the lifecycle.

### Tests

- [ ] **AC-13:** All existing tests pass (386+).
- [ ] **AC-14:** New tests: guard blocks commit on main, guard allows commit on feature branch, guard allows non-commit on main, guard bypass with --allow-main, land from feature branch after merge, land fails on main, land fails with unmerged PR, land handles missing remote branch, land handles no remote.

## Affected Files

| File | Change |
|------|--------|
| `preset/.claude/hooks/protect-main.sh` | New — PreToolUse Bash hook |
| `preset/.claude/settings.json` | Register the hook |
| `preset/.ccanvil/scripts/docs-check.sh` | Add `cmd_land` |
| `hub/tests/feature-lifecycle.bats` | New tests for land |
| `hub/tests/hooks.bats` or new test file | Tests for protect-main hook |
| `preset/.claude/rules/workflow.md` | Add land to lifecycle |
| `preset/.claude/commands/pr.md` | Mention land as next step |
| `preset/.ccanvil/guide/command-reference.md` | Document land command |

## Dependencies

- **Requires:** `gh` CLI for PR status check (graceful degradation with `--force`)

## Out of Scope

- Automatic landing after merge (would require polling or webhooks)
- Rebase-based merges (squash merge is the standard)
- Branch protection rules on GitHub (repo-level setting, not ccanvil's concern)

## Implementation Notes

- The protect-main hook checks `git branch --show-current` — if it returns `main` or `master`, scan the command for `git commit` or `git -c ... commit`. Must avoid false positives on `git commit --amend` on feature branches etc.
- `land` uses `git reset --hard origin/main` — this is safe ONLY because the guard ensures main never has local-only commits. These two units are coupled: land's safety depends on the guard's invariant.
- `--force` on land skips the PR-merged check. Useful when merging locally or when gh is unavailable.
- Hook registration in settings.json follows the existing pattern (protect-files.sh).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
