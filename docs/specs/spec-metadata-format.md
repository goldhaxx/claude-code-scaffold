# Feature: Spec Metadata Format Resilience

> Feature: spec-metadata-format
> Created: 1776276101
> Status: Ready

## Summary

`parse_metadata()` in `docs-check.sh` only reads blockquote-style metadata (`> Feature: ...`). If a spec file uses YAML frontmatter (`---` blocks), the spec is invisible to the entire lifecycle system — `list-specs`, `activate`, `complete`, `validate`, and `recommend` all silently ignore it. Additionally, `recommend` tells users to "mark a spec as Ready" before activating, but `activate` doesn't enforce status, making the guidance misleading.

## Job To Be Done

**When** a spec is written with any reasonable metadata format,
**I want** the lifecycle tooling to find and parse it correctly,
**So that** format drift (YAML vs blockquote) never silently breaks the workflow.

## Acceptance Criteria

- [ ] **AC-1:** `parse_metadata` parses blockquote format (`> Feature: x`) — existing behavior preserved
- [ ] **AC-2:** `parse_metadata` parses YAML frontmatter format (`---` delimited, `feature: x` keys) and returns the same JSON shape
- [ ] **AC-3:** `list-specs` finds specs regardless of metadata format
- [ ] **AC-4:** `activate` works on specs with YAML frontmatter metadata
- [ ] **AC-5:** `complete` works on specs with YAML frontmatter metadata
- [ ] **AC-6:** `recommend` finds Ready specs regardless of metadata format
- [ ] **AC-7:** `parse_metadata` returns empty JSON `{}` for files with no recognizable metadata (no regression)
- [ ] **AC-8:** `recommend` guidance aligns with `activate` behavior — either activate enforces Ready status, or recommend stops requiring it
- [ ] **AC-9:** Existing tests pass (no regressions in the 444-test suite)

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — extend `parse_metadata()`, possibly adjust `recommend` |
| `hub/tests/docs-check.bats` | Modified — new tests for YAML frontmatter parsing |

## Dependencies

- **Requires:** None
- **Blocked by:** Nothing

## Out of Scope

- Migrating existing specs from blockquote to YAML (both formats coexist)
- Changing the `/spec` skill's default output format
- Adding new metadata fields beyond what `parse_metadata` already extracts

## Implementation Notes

- `parse_metadata()` is at lines 81-150 of `docs-check.sh`. Extend the parser to detect `---` on line 1 and switch to YAML parsing mode. Use `sed`/`awk` or a simple loop — avoid adding a `yq` dependency.
- YAML keys map to existing fields: `feature` → `feature_id`, `created` → `created`, `status` → `status`, etc. Handle case-insensitive keys (`Feature:` vs `feature:`).
- For AC-8: simplest fix is to update `recommend` to say "activate a spec" instead of "mark as Ready first" — `activate` already works on any status.
