# Feature: context-budget.sh TTY-aware default mode

> Feature: bts-135-context-budget-tty-aware
> Work: linear:BTS-135
> Created: 1777072368
> Status: Draft

## Summary

`context-budget.sh check` lacks a `--json` flag and ignores TTY context — its output mode is purely flag-driven. `/stasis` historically called it with `--text` and then tried to consume the text as JSON, getting null fields. The standard CLI convention (`gh`, `jq`, `ls`, `git --color`) is: emit human-readable when stdout is a terminal, emit machine-parseable when piped. Add an explicit `--json` flag and switch the default-mode logic to TTY-aware: text when interactive, JSON when piped or redirected.

## Job To Be Done

**When** `/stasis` or any other automation invokes `context-budget.sh check` via Bash (no TTY),
**I want to** receive JSON by default with no flag negotiation,
**So that** scripts can `jq` the output without remembering to pass `--json`.

## Acceptance Criteria

- [ ] **AC-1:** `context-budget.sh check --json` is accepted and produces JSON regardless of TTY state.
- [ ] **AC-2:** When stdout is not a TTY (the case for `bats run` and any pipe/redirect), `context-budget.sh check` (no flags) emits JSON — regression guard for the current default behavior under automation.
- [ ] **AC-3:** `context-budget.sh check --text` is accepted and produces text-mode output regardless of TTY state — regression guard for /stasis's current explicit-flag invocation.
- [ ] **AC-4:** `--json --text` (last-wins → text) and `--text --json` (last-wins → json) both behave per the bash arg loop's standard convention.
- [ ] **AC-5:** Existing JSON shape preserved: top-level keys `files`, `totals`, `context`, `warnings`. `totals.estimated_tokens`, `totals.budget_percent`, `totals.status` paths intact.
- [ ] **AC-6:** Exit codes preserved: `0` HEALTHY, `1` WARNING, `2` CRITICAL or usage error.
- [ ] **AC-7:** Existing `hub/tests/context-budget.bats` cases continue to pass without modification.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/context-budget.sh` | Modified — add `--json` flag; replace hard-coded `TEXT_MODE=false` default with TTY-aware default (text when `[[ -t 1 ]]`, json otherwise) |
| `hub/tests/context-budget-tty-default.bats` | New — 7 cases asserting TTY-aware default + `--json`/`--text` resolution |

## Dependencies

- **Requires:** Existing `cmd_check` infrastructure.
- **Blocked by:** Nothing.

## Out of Scope

- Adding new fields to the JSON envelope.
- Restructuring text output formatting.
- Changing exit-code semantics.
- Adding `--text` / `--json` to `permissions-audit.sh` (already shipped separately in BTS-134).

## Implementation Notes

- The default-mode change: replace `TEXT_MODE=false` (line 24) with auto-detection. Idiomatic shell: leave `TEXT_MODE=""` initially; after arg parsing, if still empty, set based on `[[ -t 1 ]]`.
- The `--json` flag mirrors `--text`: `--json) TEXT_MODE=false; shift ;;`.
- `bats run` always captures stdout (no TTY) → default mode tests assert JSON. No need for `script -q` pty fakery.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
