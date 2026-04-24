# Feature: --respect-allowlist on legacy-refs-scan

> Feature: bts-132-legacy-refs-allowlist-flag
> Work: linear:BTS-132
> Created: 1777065516
> Status: Complete

## Summary

`legacy-refs-scan` returns every raw match, even those already covered by `hub/tests/legacy-refs-allowlist.txt`. `/stasis` produced 157 matches in a recent run, all allowlisted, drowning the signal. Add `--respect-allowlist [path]` so the scanner pre-filters matches against the allowlist — leaving only real drift for the Cross-Session Patterns section.

## Acceptance Criteria

- [ ] **AC-1:** Default behavior unchanged. `docs-check.sh legacy-refs-scan` without `--respect-allowlist` returns the full raw match list (regression guard).
- [ ] **AC-2:** `docs-check.sh legacy-refs-scan --respect-allowlist` with the repo's default allowlist path (`hub/tests/legacy-refs-allowlist.txt`) filters out all matches whose `file:line:content` string matches an allowlist ERE pattern.
- [ ] **AC-3:** `docs-check.sh legacy-refs-scan --respect-allowlist <custom-path>` reads a user-provided allowlist file. Missing path = ERROR + exit 2.
- [ ] **AC-4:** Comment lines in the allowlist (starting with `#`) are skipped, as are blank lines. Matches pattern already in use by the test.
- [ ] **AC-5:** Exit code preserved: `0` when zero post-filter matches, `1` when ≥ 1 remain (unchanged from pre-flag behavior).
- [ ] **AC-6:** Output format unchanged — JSON array of `{file, line, match, scope}` objects.
- [ ] **AC-7:** `/stasis` skill is updated (`.claude/skills/stasis/SKILL.md` step 6) to invoke `legacy-refs-scan --respect-allowlist hub/tests/legacy-refs-allowlist.txt` so the Cross-Session Patterns section surfaces real drift only.
- [ ] **AC-8:** 4+ new bats cases in `hub/tests/legacy-refs-scan.bats` covering default, flag-on-no-allowlist-arg, flag-on-with-arg, missing-file error, comment/blank skipping.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `--respect-allowlist` flag to `cmd_legacy_refs_scan` |
| `hub/tests/legacy-refs-scan.bats` | Modified — 4+ new cases |
| `.claude/skills/stasis/SKILL.md` | Modified — step 6 updated |
| `.ccanvil/guide/command-reference.md` | Modified — scan command row updated with flag |

## Out of Scope

- Changing the allowlist content itself.
- Inline filtering (making `--respect-allowlist` the default) — keep additive for backward compat.

## Implementation Notes

- Parse `--respect-allowlist [path]` with a positional-arg fallback to `hub/tests/legacy-refs-allowlist.txt` when no path is given and a `$PWD/hub/tests/...` exists.
- Filter `raw_matches` BEFORE the processing loop via `grep -vEf <allowlist-cleaned>` on a temp file containing only non-comment/non-blank lines.
- Temp file via `mktemp`; cleanup with trap.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
