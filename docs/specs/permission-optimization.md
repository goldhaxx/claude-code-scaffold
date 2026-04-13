# Feature: Permission Optimization

> Feature: permission-optimization
> Created: 1776117407
> Status: Complete

## Summary

Expand the settings.json allow-list for commands already guarded by hooks and add new guard hooks for destructive operations, so that Claude operates autonomously on routine tasks while maintaining safety through the hook layer. Currently ~98% of approval prompts are for safe operations that hooks already protect — this feature eliminates that friction.

## Job To Be Done

**When** Claude runs routine operations (staging files, committing on a feature branch, running tests, creating PRs, manipulating JSON with jq),
**I want** those operations to be auto-approved by the permissions layer,
**So that** I only see approval prompts for genuinely consequential actions (force push, branch deletion, hard resets).

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `git add`, `git commit`, `git push`, `git push -u origin` commands are auto-approved without user prompt (protected by existing `protect-main.sh` hook which blocks commits on main)
- [ ] **AC-2:** `git checkout`, `git checkout -b`, `git switch`, `git switch -c`, `git branch --show-current`, `git fetch`, `git cat-file` commands are auto-approved
- [ ] **AC-3:** `bats` commands are auto-approved (test runner)
- [ ] **AC-4:** `mkdir` and `jq` commands are auto-approved
- [ ] **AC-5:** `rm -f` (single file removal, non-recursive) is auto-approved
- [ ] **AC-6:** `gh pr create` and `gh pr ready` commands are auto-approved
- [ ] **AC-7:** A new PreToolUse hook `guard-force-push.sh` blocks `git push --force` and `git push -f` (exit 2) unless `ALLOW_FORCE=1` is set
- [ ] **AC-8:** A new PreToolUse hook `guard-destructive.sh` blocks `git reset --hard`, `git branch -D`, `git push origin --delete`, and `git clean -f` (exit 2) unless `ALLOW_DESTRUCTIVE=1` is set
- [ ] **AC-9:** `git push --force` is NOT in the allow-list (the guard hook is the safety layer, but it should also not be auto-approved)
- [ ] **AC-10:** Existing hooks (`protect-main.sh`, `protect-files.sh`, `branch-name-lint.sh`, `commit-msg-lint.sh`) continue to function unchanged
- [ ] **AC-11:** All existing tests pass (`bats hub/tests/`)
- [ ] **AC-12:** New tests exist for `guard-force-push.sh` and `guard-destructive.sh` covering both block and bypass paths
- [ ] **AC-13:** Error: when `guard-force-push.sh` blocks, stderr includes actionable message with bypass syntax (`ALLOW_FORCE=1`)
- [ ] **AC-14:** Error: when `guard-destructive.sh` blocks, stderr includes actionable message with bypass syntax (`ALLOW_DESTRUCTIVE=1`) and names the specific blocked command

## Affected Files

| File | Change |
|------|--------|
| `.claude/settings.json` | Modified — expanded allow-list, new hook registrations |
| `.claude/hooks/guard-force-push.sh` | New — PreToolUse hook blocking force push |
| `.claude/hooks/guard-destructive.sh` | New — PreToolUse hook blocking hard reset, branch -D, remote delete, clean -f |
| `hub/tests/hooks.bats` | Modified — new tests for guard hooks |

## Dependencies

- **Requires:** Existing hook infrastructure (settings.json hook registration, PreToolUse pattern)
- **Blocked by:** Nothing

## Out of Scope

- Modifying existing hooks (protect-main.sh, protect-files.sh, etc.)
- Downstream sync of permission changes (separate feature)
- Per-project permission customization (future)
- `git reset --hard` allow-list entry (kept behind guard hook + approval)

## Implementation Notes

- Follow the same pattern as `protect-main.sh` for new guard hooks: read stdin JSON, extract command via `jq -r`, regex match, exit 2 to block / exit 0 to allow
- The two-layer safety model: settings.json is the coarse gate (pattern-matching, fast), hooks are the smart gate (context-aware, can inspect branch/state). This feature opens the coarse gate wider while adding smarter hooks.
- Guard hooks use `PreToolUse` matcher `Bash` — same as `protect-main.sh`
- The `guard-destructive.sh` hook covers multiple patterns in a single hook to avoid hook proliferation
- `rm -f` (non-recursive) is allowed but `rm -rf` stays in the deny list
