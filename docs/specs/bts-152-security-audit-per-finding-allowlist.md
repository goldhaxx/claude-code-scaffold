# Feature: security-audit.sh per-finding allowlist (file::category::detail)

> Feature: bts-152-security-audit-per-finding-allowlist
> Work: linear:BTS-152
> Created: 1777162929
> Status: Complete

## Summary

`security-audit.sh` allowlist is currently file-level only — a substring match against the file path silences all findings in that file. This is too coarse: silencing `.claude/settings.json` to accept one known-acceptable `Read(//Users/...)` PII match also silences future genuine secrets or PII in the same file. Extend the `.security-audit-allowlist` format to support per-finding granularity via `<file-glob>::<category>::<detail-substring>` triples while preserving backward compatibility with file-only entries.

## Job To Be Done

**When** I run `security-audit.sh` and a known-acceptable finding surfaces (e.g., a documented absolute path with my username),
**I want to** silence exactly that finding without losing audit coverage of the rest of the file,
**So that** the audit's signal-to-noise stays high as the project grows and future genuine findings in the same file are not masked.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Legacy file-only allowlist entries continue to work. A line like `.claude/settings.json` silences all findings whose file path contains that substring (existing behavior unchanged).
- [ ] **AC-2:** Triple-format entries `<file-substring>::<category>::<detail-substring>` silence only findings matching ALL three: file-path substring AND category exact AND detail substring.
- [ ] **AC-3:** Recognized categories: `secret`, `pii`, `email`, `dangerous-file` (the four currently emitted by `add_finding`). An entry with an unrecognized category is allowed (it just won't match any finding, which is harmless) — no error.
- [ ] **AC-4:** Triple-format allowlists are scoped — silencing `.claude/settings.json::pii::Read(//Users/` continues to surface a genuinely new `secret` finding in the same file (e.g., a leaked API key).
- [ ] **AC-5:** Both forms can coexist in the same allowlist file. Lines starting with `#` and blank lines are still ignored (existing behavior).
- [ ] **AC-6 (error):** Triple-format entries with fewer than 3 `::`-separated parts (e.g., `.claude/settings.json::pii`) are rejected as malformed at load time with a clear stderr message and a non-zero exit during `--check` style usage. Truly malformed lines should not silently fall through to file-only matching (which would expand the allowlist surface unintentionally).
- [ ] **AC-7 (edge):** Triple-format entries with empty middle/last segments (e.g., `.claude/foo.json::pii::`) are valid and behave as a wildcard for that segment — empty `detail-substring` matches any detail; empty `category` matches any category. Empty `file-substring` is rejected (would silence everything globally).
- [ ] **AC-8 (docs):** `.security-audit-allowlist`'s header comment documents both formats with one example each. `.ccanvil/guide/command-reference.md`'s entry for `security-audit.sh` references the new format.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/security-audit.sh` | Modified — extend allowlist parser + `is_allowlisted()` to accept category/detail args |
| `.security-audit-allowlist` | Modified — header comment documents triple format; one real triple entry exercising the path may be added if a current finding warrants it (otherwise leave as-is) |
| `hub/tests/security-audit.bats` | Modified — add coverage for triple format, mixed file+triple entries, malformed lines, scoped/un-scoped behavior |
| `.ccanvil/guide/command-reference.md` | Modified — document the triple format in the security-audit.sh subsection |

## Dependencies

- **Requires:** Existing `security-audit.sh` substrate (find scanners, `add_finding`, `is_allowlisted`).
- **Blocked by:** none.

## Out of Scope

- Glob support beyond substring (e.g., `**/*.json`). Substring matching is preserved as-is for file-segment to keep backward compatibility; full glob is a separate concern if it surfaces.
- Severity-level filtering (CRITICAL/HIGH/MEDIUM/LOW). Category is the right scoping axis here; severity is correlated with category and would be redundant.
- Migration of existing allowlist entries. Operator decides if/when to tighten file-only entries to triples — they continue to work as-is.

## Implementation Notes

- **Parsing:** keep the current line-by-line read loop. Detect the `::` separator: if `trimmed` contains `::`, split into 3 parts with `IFS=:`. Validate part count = 3 (AC-6); reject empty file-substring (AC-7). Push as a structured array entry like `"triple|<file>|<category>|<detail>"`. Push file-only lines as `"file|<file>"`.
- **Storage shape:** since bash 3.2 (macOS) lacks associative arrays-of-arrays, store entries as pipe-delimited strings in a single array `ALLOWLIST_ENTRIES`. Each entry is either `file|<substr>` or `triple|<file>|<category>|<detail>`.
- **Matcher:** rewrite `is_allowlisted()` to accept `(file, category, detail)` and iterate `ALLOWLIST_ENTRIES`. For `file|...` entries, match file-substring only (legacy). For `triple|...` entries, match file substring AND (category empty or category equal) AND (detail empty or detail substring). Return 0 if any entry matches.
- **Call-site updates:** the four scanners (`scan_tracked_files_secrets`, `_pii`, `_emails`, `_dangerous_files`) currently pass only `file`. Update to also pass `category` and `detail` (the same values they pass to `add_finding`). The change is mechanical.
- **Test fixture pattern:** existing `security-audit.bats` uses `mktemp -d` + git init + tracked files + invoke script. Mirror for new tests; add a fixture allowlist file in each test scenario.
- **BTS-127 compliance:** any new `@test` with ≥2 `jq -e` assertions opens with `set -e`. The script's text output makes most assertions `[[ "$output" == *foo* ]]` style — that's not jq-e, so BTS-127 doesn't apply, but standard `set -e` discipline still helps.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
