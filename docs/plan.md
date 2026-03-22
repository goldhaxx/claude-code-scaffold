# Implementation Plan: Sync Hardening

> Feature: sync-hardening
> Created: 1774213893
> Spec hash: cba56e09
> Based on: docs/spec.md

## Objective

Add self-validating guards to every destructive operation in scaffold-sync.sh and a --dry-run mode for pull/push workflows.

## Sequence

### Step 1: Guard infrastructure — `guard_fail` function and exit code 3 (AC-5)
- **Test:** Call a function that triggers `guard_fail`; verify exit code is 3 and stderr contains `GUARD_FAIL:` prefix.
- **Implement:** Add `guard_fail()` function to scaffold-sync.sh that formats `GUARD_FAIL: <op> on <file>: <reason>` and exits 3.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 2: jq validation guard (AC-3, AC-13)
- **Test:** Corrupt a lockfile mutation scenario (mock jq failure); verify guard catches it before `mv`, lockfile stays intact.
- **Implement:** After every `jq ... > "$tmp"`, add `jq empty "$tmp" || guard_fail`. Wrap existing lock mutation functions.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 3: Hash-at-plan capture in pull-plan (AC-1 prerequisite)
- **Test:** Run `pull-plan` on a modified file; verify plan JSON includes `local_hash` field.
- **Implement:** Extend `pull-plan` JSON output to include `local_hash` for each file entry.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 4: File overwrite guard — hash re-check before cp (AC-1, AC-12)
- **Test:** Run `pull-plan`, modify the local file, then run `pull-apply take-scaffold`; verify guard failure with hash mismatch.
- **Implement:** In `cmd_pull_apply` (take-scaffold, adopt-conflict paths), re-hash local file and compare against plan's `local_hash`. Also verify source exists.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 5: Delete guard — status re-check before rm (AC-2)
- **Test:** Run `pull-plan` with a delete action, change the file's lockfile status, then `pull-apply delete`; verify guard failure.
- **Implement:** In `cmd_pull_apply delete`, re-read lockfile status and compare against expected. Abort if changed.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 6: Git commit verification guard (AC-4)
- **Test:** Simulate a commit with nothing staged; verify guard reports failure clearly.
- **Implement:** In `cmd_pull_finalize` and `cmd_push_finalize`, capture HEAD before and after `git commit`. If unchanged, `guard_fail`.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 7: Guard failure exit code consistency (AC-15)
- **Test:** Trigger each guard type (jq, hash, status, git); verify all exit 3 with `GUARD_FAIL:` prefix.
- **Implement:** Review and ensure all guard paths use `guard_fail` consistently. This is a verification/refactor step.
- **Files:** `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 8: Dry-run infrastructure — flag parsing and DRY_RUN global (AC-6, AC-10, AC-11, AC-14)
- **Test:** Run `pull-auto --dry-run`; verify no files are copied and output contains `DRY-RUN: would` prefix. Verify pre-check still runs.
- **Implement:** Add `--dry-run` flag parsing to `pull-auto`. Set `DRY_RUN=true`. Wrap `cp`/`jq`/`mv` in `if ! $DRY_RUN` blocks. Pre-check still runs normally.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 9: Dry-run for pull-apply and pull-finalize (AC-7, AC-8)
- **Test:** Run `pull-apply <file> take-scaffold --dry-run`; verify output describes action without executing. Run `pull-finalize --dry-run`; verify commit message shown but no commit created.
- **Implement:** Add `--dry-run` parsing to `pull-apply` and `pull-finalize`. Same wrapping pattern.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 10: Dry-run for push-apply and push-finalize (AC-9)
- **Test:** Run `push-apply <file> --dry-run` and `push-finalize --dry-run`; verify output without mutations.
- **Implement:** Add `--dry-run` to push commands. Same pattern as pull.
- **Files:** `scripts/scaffold-sync.sh`, `tests/scaffold-sync.bats`
- **Verify:** `bats tests/scaffold-sync.bats`

## Risks

- **Existing tests may break** if guard checks fire on scenarios that previously succeeded silently. Mitigation: run full suite after each step, adjust test fixtures to satisfy new guards.
- **pull-plan JSON schema change** (Step 3) may affect `/scaffold-pull` command. Mitigation: `local_hash` is additive — existing fields unchanged.
- **Performance overhead** of re-hashing files before apply is negligible for scaffold file counts (<100 files).

## Definition of Done

- [ ] All 15 acceptance criteria from spec pass
- [ ] All existing tests still pass (no regressions)
- [ ] No guard fires on normal happy-path operations
- [ ] Code reviewed (run /review)
