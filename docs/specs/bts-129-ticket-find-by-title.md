# Feature: ticket.find-by-title wrapper — deterministic pre-capture dedup

> Feature: bts-129-ticket-find-by-title
> Work: linear:BTS-129
> Created: 1777054322
> Status: Draft

## Summary

Add `operations.sh exec ticket.find-by-title <title> [--exact]` wrapper. Under the hood: resolve provider params (project/team), dispatch `list_issues { query: <title> }`, filter matches by title, return JSON array of `{id, title, status, url}` (empty + exit 0 when no match). Sibling of `ticket.transition` (BTS-128). Unblocks BTS-123's idempotent `/idea sync` replay — prevents recreating issues already synced out-of-band.

## Job To Be Done

**When** I'm about to capture an idea or replay a pending-log entry,
**I want to** programmatically check whether a ticket with that title already exists,
**So that** I don't create duplicates and my idea-sync workflow is idempotent.

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/operations.sh resolve ticket.find-by-title "<title>"` returns JSON `{provider, mechanism, invocation}` with `invocation.tool = "mcp__claude_ai_Linear__list_issues"` and `invocation.params` populated with `{project, team, query}` where `query == "<title>"`.
- [ ] **AC-2:** `bash .ccanvil/scripts/operations.sh exec ticket.find-by-title "<title>"` returns a JSON array of matching tickets `[{id, title, status, url}, ...]` when matches exist.
- [ ] **AC-3:** When no ticket matches, `exec` returns `[]` and exits 0. No errors, no warnings.
- [ ] **AC-4:** Case-insensitive substring match by default: searching for `"assertion leak"` finds a ticket titled `"Bats: multiple jq -e assertions leak failures silently"`.
- [ ] **AC-5:** `--exact` flag narrows to case-sensitive string equality: `--exact "foo"` only matches tickets with title exactly equal to `"foo"`.
- [ ] **AC-6:** Special characters in title (`&`, `|`, `$`, `"`, `'`, backticks) are handled — no shell-injection surface, matches still work. Verified by a test that searches for a title containing each.
- [ ] **AC-7:** `.ccanvil/guide/command-reference.md` documents `ticket.find-by-title` with usage examples.
- [ ] **AC-8:** Error: when the Linear MCP dispatch fails (network/auth), `exec` emits `ERROR: ...` to stderr with the canonical `ERROR: <what>` + blank + bullet-remediation shape (from BTS-122 `_assert_error_format`) and exits non-zero. Offline/intermittent failures should not silently return empty (which would mask real duplicates).
- [ ] **AC-9:** Bats coverage: new `hub/tests/ticket-find-by-title.bats` file covering AC-1 through AC-8, using strict-mode (per BTS-127 convention) and `run --separate-stderr` for stderr assertions.
- [ ] **AC-10:** Local-provider nodes either (a) return an empty array gracefully (no Linear configured means no tickets to find), OR (b) resolve to a not-implemented error with clear remediation. Chosen behavior documented in command-reference.md.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified (add `ticket.find-by-title` resolver + exec branch) |
| `.ccanvil/guide/command-reference.md` | Modified (add row) |
| `hub/tests/ticket-find-by-title.bats` | New |
| `.ccanvil/templates/provider-config.json` (if applicable) | Modified (if new config key needed — TBD during planning) |

## Dependencies

- **Requires:** Linear MCP `list_issues` tool (already available in session).
- **Requires:** BTS-128's `ticket.transition` resolver/dispatch pattern as the template to mirror. Already shipped.
- **Blocked by:** Nothing.
- **Blocks:** BTS-123 (pending-log fallback integrity) — once shipped, BTS-123 can use this primitive for idempotent replay.

## Out of Scope

- Fuzzy-match tuning (Levenshtein distance, trigram similarity). Default substring match is sufficient for dedup; fuzzier matching is a future refinement if it becomes necessary.
- Multi-provider federation (search across Linear + GitHub Issues + Jira simultaneously). Single-provider-at-a-time per existing resolver shape.
- Writing to Linear (this is a read-only primitive). Mutations live in `ticket.transition` + `save_issue`.

## Implementation Notes

- **Template to mirror:** `ticket.transition` (BTS-128). Read how it parses args, resolves params, and structures its `invocation` JSON. Same shape for `find-by-title` — just a different MCP tool and a filter step.
- **Match filter:** after Linear returns results, filter locally by title. Linear's `query` param may return broad matches (full-text search across title+description); we tighten to title-substring for AC-4.
  ```bash
  jq --arg q "$title_lower" '
    [ .[] | select((.title | ascii_downcase) | contains($q))
          | {id, title, status: .state.name, url} ]
  '
  ```
- **`--exact` flag:** replace `contains` with `== ` in the jq expression, skip `ascii_downcase`.
- **Shell quoting:** test titles that contain `&`, `|`, `$`, `"` — always pass title via argv, never via eval/string interpolation. Use `"$1"` quoting throughout.
- **Error shape (AC-8):** match BTS-122's `_assert_error_format` — first stderr line starts with `ERROR: `, then blank line, then two-space-indented bullets. Example:
  ```
  ERROR: Linear MCP list_issues failed for "<title>"

    Fix:
    Check Linear auth via /mcp
    Retry the command
  ```
- **Local-provider behavior (AC-10):** lean toward (a) — empty array for local nodes. Matches the "silent compatibility" pattern of other `operations.sh` primitives that gracefully no-op when their provider isn't configured. Alternative (b) would force every caller to handle a "not implemented" branch.
- **Test file header:** `bats_require_minimum_version 1.5.0` to enable `run --separate-stderr`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
