# Feature: audit-session emits real file:line from git diff hunks

> Feature: bts-133-audit-session-line-numbers
> Work: linear:BTS-133
> Created: 1777071360
> Status: Draft

## Summary

`cmd_audit_session` always reports `line: 0` for file-pattern matches because the `line_num` variable is declared `local` inside the loop body — it resets to empty on every iteration, throwing away the line number captured from the preceding `@@` hunk header. Fix: hoist `current_line` to function scope, set it from the hunk header, and increment it for each added (`+`) line so subsequent matches in the same hunk get correct line numbers.

## Job To Be Done

**When** I review `audit-session` findings during `/recall` or `/stasis`,
**I want to** see the real source line number for each match (not `0`),
**So that** I can jump directly to the offending code.

## Acceptance Criteria

- [ ] **AC-1:** Single `cp` addition at line 1 of a new file: `audit-session` emits `line: 1` (not `0`).
- [ ] **AC-2:** Hunk header `@@ -0,0 +50,3 @@` followed by 3 `+` lines (each with a pattern match): findings emit `line: 50`, `line: 51`, `line: 52` respectively.
- [ ] **AC-3:** Multiple hunks in same file (e.g., `+10,1` then `+30,1`): each finding gets the line from its own hunk; line counter resets at each `@@`.
- [ ] **AC-4:** Multiple files in a single diff: the first finding in file B uses file B's hunk header, not the line counter from file A.
- [ ] **AC-5:** Commit-message scan findings continue to emit `line: 0` (commit hashes have no source line — backward compat).
- [ ] **AC-6:** Empty diff produces zero findings (no false positives from line-number tracking changes).
- [ ] **AC-7 (regression):** Existing audit-session bats cases still pass — the `line` field continues to exist as a number on every finding.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — hoist `current_line` outside loop; increment per `+` line; reset on file/hunk header |
| `hub/tests/docs-check.bats` | New cases — assert exact line numbers via fixtures with known offsets |

## Dependencies

- **Requires:** Existing `cmd_audit_session` infrastructure (Step 3 of stasis pattern audit, ships since BTS-75).
- **Blocked by:** Nothing.

## Out of Scope

- Changing the pattern definitions (still cp/jq/shasum/git-C/curl/wget).
- Changing the JSON output shape beyond accurate line numbers.
- Multi-line / rename detection.

## Implementation Notes

- Bug location: `.ccanvil/scripts/docs-check.sh` lines 678–682. `local line_num=""` at the top of the loop body resets the variable every iteration; the `@@` capture is immediately discarded by the next `local` reset.
- Fix shape: move `local current_line=0` to function scope (above the `while`); set from `@@.*\+([0-9]+)`; increment on each processed `+` line; reset to 0 on `^diff --git` or `^+++ b/`.
- Tests use `create_audit_repo` helper. Construct fixtures with deterministic line offsets (e.g., 50 lines of comments before the pattern) to assert against known line numbers.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
