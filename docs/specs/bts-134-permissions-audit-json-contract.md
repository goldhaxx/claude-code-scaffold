# Feature: permissions-audit.sh check JSON contract

> Feature: bts-134-permissions-audit-json-contract
> Work: linear:BTS-134
> Created: 1777071790
> Status: Draft

## Summary

`permissions-audit.sh check` defaults to JSON output but has two stdout-shape inconsistencies: (1) when `settings.json` is missing OR the log file is corrupt, the script exits 2 with NO stdout (only stderr ERROR), so `jq -c <(...)` callers crash on empty input; (2) there is no explicit `--json` flag — only `--text` to override the default — making intent ambiguous and force-overrides impossible. Fix: add explicit `--json` flag (no-op when default already JSON) AND emit a JSON error envelope on stdout in error paths so the JSON contract holds for every exit path.

## Job To Be Done

**When** `/stasis` (or any future automation) pipes `permissions-audit.sh check` into `jq`,
**I want to** rely on stdout being valid JSON regardless of exit code,
**So that** error handling stays uniform and the script is composable.

## Acceptance Criteria

- [ ] **AC-1:** `permissions-audit.sh check --json` is accepted and produces the same JSON output as the default no-flag invocation (regression guard for default).
- [ ] **AC-2:** Missing `settings.json` → stdout is a single-line JSON object containing an `error` field; stderr still gets the human-readable `ERROR: ... not found` line; exit code is 2.
- [ ] **AC-3:** Corrupt `permissions-log.json` → stdout is a single-line JSON object containing an `error` field; stderr gets the `ERROR: ... not valid JSON` line; exit code is 2.
- [ ] **AC-4:** `--text` mode preserves existing behavior (regression guard) — error paths emit only stderr ERROR + exit 2; no JSON envelope on stdout.
- [ ] **AC-5:** `--json --text` (or `--text --json`) — last flag wins (standard CLI convention). Already-true via the loop; assert with one regression case.
- [ ] **AC-6:** Default exit codes unchanged: `0` (all REVIEWED), `1` (UNREVIEWED present, no DANGER), `2` (DANGER or hard error).
- [ ] **AC-7:** Existing JSON envelope shape unchanged on the success path: `{entries, danger, unreviewed, reviewed}`. New error envelope: `{error: "<msg>", exit: <code>}` (distinguishable by presence of `error` key).
- [ ] **AC-8:** Existing bats cases in `hub/tests/permissions-audit.bats` continue to pass without modification.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Modified — add `--json` flag; wrap the two `exit 2` error paths to emit JSON envelope on stdout when not TEXT_MODE |
| `hub/tests/permissions-audit-json-contract.bats` | New — 7 cases asserting AC-1 through AC-7 |

## Dependencies

- **Requires:** Existing `cmd_check` infrastructure.
- **Blocked by:** Nothing.

## Out of Scope

- Changing the exit-code semantics (0/1/2 unchanged).
- Restructuring the success-path JSON envelope.
- Adding new error categories or DANGER patterns.

## Implementation Notes

- Bug location: `.ccanvil/scripts/permissions-audit.sh` lines 154–156, 178–180.
- Add `--json` to the arg-parse loop: `--json) TEXT_MODE=false; shift ;;`.
- Helper: `emit_error_envelope <msg> <exit_code>` — when `TEXT_MODE=false`, prints `jq -n --arg e "$msg" --argjson c "$code" '{error: $e, exit: $c}'` to stdout, then exits with `$code`. When `TEXT_MODE=true`, just exits.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
- Use `--separate-stderr` in tests to verify stdout is JSON and stderr is the human-readable line independently.
