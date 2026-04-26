# Feature: derive-pr-title substrate primitive with title truncation

> Feature: bts-181-derive-pr-title
> Work: linear:BTS-181
> Created: 1777219094
> Status: Complete

## Summary

Factor the spec-to-PR-title derivation duplicated between `cmd_activate` (docs-check.sh:983) and `cmd_assert_pr_title` (docs-check.sh:2446) into a single `docs-check.sh derive-pr-title <spec-file>` substrate primitive, and add deterministic truncation so verbose Summary opening lines do not produce overlong squash-merge subjects.

## Job To Be Done

**When** I activate a spec whose Summary opens with a long multi-clause sentence,
**I want to** have the derived PR title truncated deterministically at the first sentence boundary or ~80 chars,
**So that** the squash-merge commit subject is clean without manual `gh pr edit` shortening.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh derive-pr-title <spec-file>` emits the title `feat(<feature-id>): <truncated-first-summary-line>` to stdout. Reads `> Feature:` from the spec metadata and the first non-blank line of the `## Summary` section.
- [ ] **AC-2:** When the first Summary line is ≤80 chars and contains no period before char 80, the line is emitted verbatim (no truncation).
- [ ] **AC-3:** When the first Summary line contains a period (`.`), the title is truncated at the first period (period excluded). Example: `Add foo. Bar baz.` → `Add foo`.
- [ ] **AC-4:** When the first Summary line has no period within the first 80 chars, the title is truncated at char 80 with no trailing whitespace. The combined `feat(<id>): <line>` total may exceed 80 (this AC governs the suffix only).
- [ ] **AC-5:** Empty/missing Summary section → emits `feat(<feature-id>): activate feature` (parity with the existing `${first_line:-activate feature}` fallback).
- [ ] **AC-6:** Missing `<spec-file>` argument or non-existent file → non-zero exit with a clear error to stderr, no stdout output.
- [ ] **AC-7:** `cmd_activate` is refactored to call `cmd_derive_pr_title "$spec_file"` instead of inlining the `sed` extraction. Behavior is unchanged for short Summaries.
- [ ] **AC-8:** `cmd_assert_pr_title` is refactored to call `cmd_derive_pr_title "$spec_file"` for its `expected_title`. The placeholder/prefix decision logic is unchanged.
- [ ] **AC-9:** Drift-guard: a bats test asserts `cmd_activate` and `cmd_assert_pr_title` no longer contain inline `sed -n '/^## Summary$/...'` extractions — they must go through the primitive.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Add `cmd_derive_pr_title`; refactor `cmd_activate` (line 983) and `cmd_assert_pr_title` (line 2446) to call it |
| `hub/tests/derive-pr-title.bats` | New — covers AC-1..AC-6 and AC-9 |

## Dependencies

- **Requires:** none. Pure refactor + small behavior change (truncation).
- **Blocked by:** nothing.

## Out of Scope

- Re-shortening titles on existing open PRs that pre-date this change. `assert-pr-title` will only repair placeholder-shaped or missing-prefix titles per its existing decision logic; user-edited long titles stay untouched (trust user edits — BTS-178 contract).
- Configurable truncation policy. ~80 chars + first-period rule is hard-coded; future tickets can revisit if the cosmetics fail in practice.

## Implementation Notes

- The truncation is two-stage: first strip everything from the first `.` onward; then truncate the remainder at 80 chars. Order matters — period-first lets a "Long sentence. More." → "Long sentence" cleanly even if the full line exceeds 80.
- Pattern to follow: same shape as `cmd_assert_pr_title` — small focused function, takes one path argument, prints a single line to stdout, exits non-zero with a stderr message on bad input.
- Both call sites already compute the same `first_line` via identical `sed`. The refactor is mechanical: call `cmd_derive_pr_title "$spec_file"` and capture stdout into `pr_title` / `expected_title`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
