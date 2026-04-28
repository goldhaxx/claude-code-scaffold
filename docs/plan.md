# Plan: docs-check.sh usage string single-source-of-truth from dispatch table

> Feature: bts-215-usage-string-sync-with-dispatch-table
> Created: 1777340297
> Spec hash: 1d8142e5

## Strategy

Single mechanical change: replace the hard-coded usage string at the unknown-command fall-through with a runtime call to a new `_print_usage` helper that extracts subcommand verbs from the dispatch case in the script itself. Add one drift-guard bats file. No behavior change for legitimate subcommand calls.

## TDD steps

### Step 1 — write the failing drift-guard test (RED)

Create `hub/tests/usage-string-dispatch-sync.bats` with these tests:

- **Test A:** runs `bash docs-check.sh nonexistent-command` and asserts `status` and `activate` both appear in stderr (sanity baseline — these are in the current hard-coded string).
- **Test B:** runs `bash docs-check.sh nonexistent-command` and asserts `artifact-read`, `artifact-write`, `route-of`, `ssot-migrate`, `lifecycle-state`, `evidence-scan-session`, `stasis-carry-forward`, `ship-finalize`, `archive-stasis`, `sessions-list`, `assert-pr-title`, `derive-pr-title`, `idea-template-body`, `session-info` all appear in stderr (this fails today; the hard-coded string omits them).
- **Test C (drift-guard):** parses the dispatch case in the script, extracts every verb, and asserts each one is a substring of the captured usage stderr. This is the enforcement-by-construction test.
- **Test D (exit code):** asserts the unknown-command exit code remains `1` (not `2` — preserves existing semantics).

Run the suite. Test B + C fail, A + D pass. Confirm RED.

### Step 2 — implement `_print_usage` (GREEN)

Above the dispatcher (just before `case "$1" in` at line ~5487), add:

```bash
# Generate the usage string from the dispatch case. Single source of truth —
# adding a new verb to the case statement automatically appears in usage output.
_print_usage() {
  local script="${BASH_SOURCE[0]}"
  local verbs
  verbs=$(awk '
    /^case "\$1" in$/ { in_case=1; next }
    in_case && /^esac$/ { in_case=0 }
    in_case && /^[[:space:]]*[a-z][a-z0-9-]+\)/ {
      sub(/^[[:space:]]*/, "")
      sub(/\).*$/, "")
      print
    }
  ' "$script" | sort -u | paste -sd '|' -)
  echo "Usage: docs-check.sh {$verbs} [args...]" >&2
}
```

Replace the hard-coded line at the unknown-command fall-through:

```bash
*)
  _print_usage
  exit 1
  ;;
```

Run the suite. Tests A–D now pass. Confirm GREEN.

### Step 3 — full suite verify

Run `bash .ccanvil/scripts/bats-report.sh --parallel`. Confirm 1830+ passing (1826 baseline + 4 new from this ticket).

### Step 4 — commit, /pr, /ship

Conventional commit. /pr to mark the draft ready. /ship to finalize.

## Affected files

- `.ccanvil/scripts/docs-check.sh` — add `_print_usage` helper + replace fall-through usage line.
- `hub/tests/usage-string-dispatch-sync.bats` — new file with 4 tests.

## Risks

- **Awk pattern false-positives:** `^[[:space:]]*[a-z][a-z0-9-]+\)` could match nested case-statement verbs inside other functions. Mitigation: scope to the line range between `^case "\$1" in$` and the matching `^esac$`. The dispatcher's `case` is anchored to start-of-line; nested case statements inside functions are indented, so the anchor on `^case "\$1" in$` (no leading whitespace) discriminates correctly.
- **Sort order:** `sort -u` produces alphabetical output, which differs from the current hard-coded order. The drift-guard test is order-agnostic (substring containment), so this is fine. Operators reading the usage line get a sorted list, which is actually more navigable.
- **paste availability:** `paste` is POSIX. Verified present on macOS + Linux. No portability concern.

## Out of scope (per spec)

- Per-subcommand flag-error messages. They pair with BTS-212 (separate ticket, separate ship).
- Caching. The cold path doesn't justify it.
