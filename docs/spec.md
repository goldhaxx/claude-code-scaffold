# Feature: Sync Hardening

> Feature: sync-hardening
> Created: 1774213893
> Status: Draft

## Summary

Add defensive guards to every destructive operation in `scaffold-sync.sh` and a `--dry-run` mode for pull/push workflows. Today, destructive operations (file copy, delete, lockfile mutation) trust the caller's classification without re-verifying preconditions at execution time. Six bugs have already been found and fixed from this gap (865792b, e507083, 3982959, 9f2a9c0, 280bab5, 721f344). This feature prevents the next six by making every destructive operation self-validating.

## Job To Be Done

**When** I run `/scaffold-pull` or `/scaffold-push` and the plan includes destructive operations (overwrite, delete, lockfile mutation),
**I want** each operation to verify its own preconditions immediately before executing, and to preview changes without applying them,
**So that** state drift between plan and apply phases can't cause silent data loss, and I can inspect what will happen before committing to it.

## Acceptance Criteria

### Part 1: Defensive guards on destructive operations

- [ ] **AC-1:** Before every `cp` that overwrites an existing file, the script verifies: (a) source file exists, (b) destination file's current hash matches what was seen during `pull-plan`. If the hash changed, the operation aborts with a descriptive error.
- [ ] **AC-2:** Before every `rm` in `pull-apply delete`, the script verifies the file's lockfile status is still what the plan expected. If status changed, abort with error.
- [ ] **AC-3:** After every `jq` mutation of the lockfile, the script verifies the output is valid JSON (`jq empty` on the temp file). If invalid, abort before `mv`, preserving the original lockfile.
- [ ] **AC-4:** After `git add` + `git commit` in finalize commands, the script verifies the commit succeeded (exit code check + `git rev-parse HEAD` changed). If not, report the failure clearly.
- [ ] **AC-5:** All guard failures produce a consistent error format: `GUARD_FAIL: <operation> on <file>: <reason>`. Exit code 3 (distinct from existing 1=general error, 2=hook block).

### Part 2: `--dry-run` mode

- [ ] **AC-6:** `pull-auto --dry-run` outputs what files would be copied and what lockfile entries would be updated, without executing any `cp`, `jq`, or `mv` operations.
- [ ] **AC-7:** `pull-apply <file> <action> --dry-run` outputs the action that would be taken without executing it. For `section-merge` and `write-merged`, shows the content that would be written.
- [ ] **AC-8:** `pull-finalize --dry-run` outputs the commit message and file list that would be committed, without staging or committing.
- [ ] **AC-9:** `push-apply <file> --dry-run` and `push-finalize --dry-run` behave analogously to their pull counterparts.
- [ ] **AC-10:** `--dry-run` still runs `pre-check` (cleanness verification) — dry-run doesn't skip safety checks, only mutations.
- [ ] **AC-11:** Dry-run output uses a consistent prefix: `DRY-RUN: would <verb> <file>` (e.g., `DRY-RUN: would copy .claude/rules/tdd.md`, `DRY-RUN: would delete .claude/rules/old.md`).

### Part 3: Test coverage for edge cases

- [ ] **AC-12:** Test: file modified between `pull-plan` and `pull-apply` triggers guard failure (hash mismatch).
- [ ] **AC-13:** Test: `jq` producing invalid JSON is caught before lockfile is corrupted.
- [ ] **AC-14:** Test: `pull-auto --dry-run` produces expected output without modifying any files or lockfile.
- [ ] **AC-15:** Test: all guard failures exit with code 3 and produce the `GUARD_FAIL:` prefix.

## Affected Files

| File | Change |
|------|--------|
| `scripts/scaffold-sync.sh` | Modified — add guards to destructive ops, add `--dry-run` flag parsing, add dry-run output |
| `tests/scaffold-sync.bats` | Modified — new tests for guards, dry-run, edge cases |

## Dependencies

- **Requires:** Current scaffold-sync.sh (all existing commands stable, 144+ tests passing)
- **Blocked by:** Nothing

## Out of Scope

- Rollback/undo capability (git checkout is sufficient recovery)
- Concurrent sync detection (document as unsupported, don't build locking)
- Dry-run for `promote`/`demote` (these are simple single-file ops with existing guards)
- Interactive confirmation prompts in the script (that's Claude's job in slash commands)

## Implementation Notes

- **Hash capture in pull-plan:** `pull-plan` already computes file hashes for comparison. Extend the plan JSON to include `local_hash_at_plan` for each file. Guards in `pull-apply` re-hash and compare.
- **jq validation pattern:** After every `jq ... > "$tmp"`, add `jq empty "$tmp" 2>/dev/null || { rm -f "$tmp"; die "GUARD_FAIL: ..."; }` before `mv "$tmp" "$LOCKFILE"`.
- **Dry-run threading:** Add a `DRY_RUN=false` global. Parse `--dry-run` in each subcommand. Wrap mutations in `if ! $DRY_RUN; then ... else echo "DRY-RUN: would ..."; fi`.
- **Exit code 3:** Distinct from `die` (exit 1) and hook blocks (exit 2). Add a `guard_fail` function that formats the message and exits 3.
- **Backward compatibility:** `--dry-run` is opt-in. All existing behavior unchanged without the flag.
- **Test strategy:** Use the existing bats test infrastructure. Modify files between plan and apply steps to trigger guards. Capture stderr for guard messages.
