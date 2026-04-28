# Feature: docs-check.sh usage string single-source-of-truth from dispatch table

> Feature: bts-215-usage-string-sync-with-dispatch-table
> Work: linear:BTS-215
> Created: 1777340297
> Status: In Progress

## Summary

`docs-check.sh` dispatches 51 subcommands via a top-level `case "$1" in ... esac`, but the unknown-command fall-through usage block (line 5540) hard-codes a stale enumeration of 25 commands. Operators who mistype a subcommand or are exploring the surface see a usage hint that omits ~half the available verbs (including `artifact-read`, `artifact-write`, `route-of`, `ssot-migrate`, `lifecycle-state`, `evidence-scan-session`, `stasis-carry-forward`, `ship-finalize`, `archive-stasis`, `sessions-list`, `assert-pr-title`, `derive-pr-title`, `detect-repo-type`, `pr-guard`, `radar-gather`, `auto-close-emit`, `auto-transition-emit`, `extract-work`, `land-recover-branch`, `sync-check`, `idea-count-local`, `idea-review-icebox`, `idea-migrate-state`, `idea-template-body`, `session-info`).

Replace the hard-coded enumeration with a runtime-generated list extracted from the dispatch case itself. Single source of truth: the dispatch table. The usage string can never drift from what's actually dispatchable, because it IS what's dispatchable.

## Job To Be Done

**When** I mistype a `docs-check.sh` subcommand or am exploring the surface for the first time,
**I want to** see the complete list of available subcommands in the usage hint,
**So that** I can self-discover the substrate without grep'ing the source or reading `command-reference.md`.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** New helper function `_print_usage` extracts subcommand verbs from the dispatch case at runtime by parsing `.ccanvil/scripts/docs-check.sh` itself. Returns a sorted, pipe-delimited list (matches existing format: `{cmd1|cmd2|...}`). Implementation: read the file, awk-extract lines matching `^[[:space:]]*[a-z][a-z0-9-]+\)` between `case "$1" in` and the matching `esac`, sort uniquely.

- [ ] **AC-2:** The unknown-command fall-through (current line 5540) calls `_print_usage` instead of emitting a hard-coded string. Existing exit code (1) and stderr destination preserved.

- [ ] **AC-3:** Running `bash .ccanvil/scripts/docs-check.sh nonexistent-command` emits a usage line containing every dispatch verb. Specifically, the usage string contains all of: `status`, `validate`, `activate`, `land`, `artifact-read`, `artifact-write`, `route-of`, `ssot-migrate`, `lifecycle-state`, `evidence-scan-session`, `stasis-carry-forward`, `ship-finalize`, `archive-stasis`, `sessions-list`, `assert-pr-title`, `derive-pr-title`, `idea-add`, `idea-list`, `idea-count`, `idea-template-body`.

- [ ] **AC-4:** Drift-guard bats test `hub/tests/usage-string-dispatch-sync.bats` asserts at test time that every subcommand in the dispatch case appears in the runtime-generated usage output. Test reads the script, extracts the dispatch verbs, runs the script with a bogus subcommand, captures stderr, and asserts each verb is a substring of the captured output. Adding a new subcommand to the dispatch case without updating logic still passes (because `_print_usage` is generative, not hard-coded).

- [ ] **AC-5:** The `_print_usage` helper itself is callable without invoking the dispatcher (so tests can exercise it directly). One approach: a hidden `__print-usage` subcommand routed before the unknown-command fall-through. Alternatively (preferred): export the helper function and source it in tests via `source .ccanvil/scripts/docs-check.sh`. Pick whichever pattern matches existing test infrastructure.

- [ ] **AC-6:** Performance: `_print_usage` runs in <100ms cold (no caching needed at this ticket scope; the dispatch case is small and parsed at most once per invocation).

- [ ] **AC-7:** Full bats suite remains green at ≥ 1826 (post-BTS-235 baseline) — only one new test file (`usage-string-dispatch-sync.bats`) is added; no existing tests should regress.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Add `_print_usage` helper above the dispatcher. Replace hard-coded usage string at the unknown-command fall-through. |
| `hub/tests/usage-string-dispatch-sync.bats` | New file. Drift-guard test asserting every dispatch verb appears in usage output. |

## Dependencies

- **Requires:** Nothing new. The dispatch case is in the same file; awk + sort are standard utilities.
- **Blocked by:** Nothing.

## Out of Scope

- **Per-subcommand flag-error messages** (e.g., the `--*) echo "Usage: docs-check.sh <subcmd> [--flag]"` patterns at lines 299, 346, 403, 634, 808). Those are about individual subcommand flag discoverability; they pair with BTS-212 (subcommand fall-through on unknown flags), which is its own ticket. This ship is narrowly the top-level dispatch usage block.
- **Help-text generation for each subcommand.** A full `--help` system per subcommand is a much larger ship; this is just enumeration.
- **Caching.** `_print_usage` reads the script file every time the unknown-command path fires. That's fine — the path is cold (operator typed wrong), not hot.

## Implementation Notes

- The dispatch case starts with `case "$1" in` and ends with the matching `esac`. Use awk's range pattern (`/case "\$1" in/,/^esac/`) to scope the extraction.
- Pattern for verb extraction: `^[[:space:]]*[a-z][a-z0-9-]+\)` (matches lines like `  ship-finalize)     cmd_ship_finalize "$@" ;;`). Strip trailing `)`.
- Sort + uniq the extracted verbs for stable output.
- Format: `Usage: docs-check.sh {<verb1>|<verb2>|...|<verbN>} [args...]` — same shape as the existing hard-coded string, just dynamic content.
- The drift-guard test is the cheap insurance: any future hard-coded usage drift is caught instantly. The generative implementation should make this near-impossible by construction, but the test prevents regression to the hard-coded shape.
