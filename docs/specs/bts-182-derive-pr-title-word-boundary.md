# Feature: derive-pr-title word-boundary truncation

> Feature: bts-182-derive-pr-title-word-boundary
> Work: linear:BTS-182
> Created: 1777222091
> Status: In Progress

## Summary

`cmd_derive_pr_title` (BTS-181) currently caps the suffix at exactly 80 chars with no word-boundary awareness, producing mid-word truncation on PRs whose Summary opens with a verbose multi-clause sentence (PRs #103 `...docs-c`, #104 `...feature_id>` are the empirical cases). After the 80-char cap, walk backward up to 8 chars to find the nearest space or hyphen and truncate there — preserving readability without changing the deterministic-correct contract. Falls back to the hard cut when no boundary exists in the lookback window.

## Job To Be Done

**When** the live `derive-pr-title` substrate fires on a long Summary opener,
**I want to** see PR titles cut at a word boundary instead of mid-word,
**So that** GitHub PR titles read cleanly without changing any other contract — `assert-pr-title`, `derive-pr-title` exit codes, the `feat(<id>): ` prefix, the period-strip behavior, or the hard 80-char ceiling.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Summary that lands ≤80 chars after period-strip is emitted verbatim — word-boundary logic is a no-op (regression guard for AC-2 of BTS-181).
- [ ] **AC-2:** Given a Summary >80 chars after period-strip with a space at position 73-79 (within the 8-char lookback), when `derive-pr-title` is invoked, then output is truncated at that space and trailing whitespace is trimmed.
- [ ] **AC-3:** Given a Summary >80 chars after period-strip with a hyphen at position 73-79, when `derive-pr-title` is invoked, then output is truncated immediately before that hyphen (the hyphen is dropped).
- [ ] **AC-4:** Given a Summary >80 chars after period-strip with no space or hyphen anywhere in positions 73-79, when `derive-pr-title` is invoked, then the output falls back to the hard 80-char cut (preserves BTS-181 AC-3 contract).
- [ ] **AC-5:** Given a Summary containing a period before character 80, period-strip happens BEFORE word-boundary logic, so the result is identical to BTS-181 AC-4 (e.g., `Add foo. Bar baz.` → `feat(<id>): Add foo`). Drift-guard against ordering regressions.
- [ ] **AC-6:** Drift-guard: the lookback window is parameterized as a single `local` constant (`local lookback=8`) inside `cmd_derive_pr_title`. Test asserts the constant declaration appears in the function body so future tweaks are obvious.
- [ ] **AC-7:** Edge: trailing whitespace after the boundary cut is trimmed (e.g., a space at position 75 produces a suffix that ends at position 74, not position 75).
- [ ] **AC-8:** Empty Summary fallback (`activate feature`) is unchanged — short string never enters the truncation path (regression guard for BTS-181 AC-5).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified (cmd_derive_pr_title — add word-boundary walk after the cap) |
| `hub/tests/derive-pr-title.bats` | Modified (add AC-2 / AC-3 / AC-4 / AC-5 / AC-6 / AC-7 word-boundary tests; existing AC-2 in BTS-181 spec re-asserts as AC-1 here) |

## Dependencies

- **Requires:** BTS-181 (`cmd_derive_pr_title` substrate) — ✅ shipped, PR #103.
- **Blocked by:** none.

## Out of Scope

- Configurable truncation policy (per-project lookback window, ceiling, etc.) — out of scope per BTS-181's own "Out of Scope" inheritance.
- Multi-line Summary handling — Summary's first non-blank line is still the only input.
- Parameterizing the 80-char hard cap — remains hard-coded.
- Re-flowing `assert-pr-title` semantics (still no-ops on user edits per BTS-178 contract).

## Implementation Notes

- Drop the new logic between lines 2413 (`if (( ${#suffix} > 80 ))`) and 2416 (trailing-whitespace trim) in `.ccanvil/scripts/docs-check.sh`. After the hard cap shrinks the suffix to 80 chars, walk index `i` from 79 down to `80 - lookback` (= 72), inclusive. Match space (`[[:space:]]`) or hyphen (`-`). On match: set `suffix="${suffix:0:i}"` (drops the boundary char itself, which is the desired behavior for both space and hyphen — neither belongs at the end of a PR title). Break on first match.
- Keep `lookback=8` declared as `local lookback=8` at the top of the function. AC-6 drift-guard greps for that exact pattern within the function range.
- Existing trailing-whitespace trim (line 2416) still runs unconditionally — handles the case where the boundary-walk landed on a non-space char but the original 80-char cap left whitespace at position 79 (rare, but cheap to keep).
- Period-strip (line 2410) is unchanged — still operates on the unmodified first line, before the cap. AC-5 verifies the ordering.
- No changes to call sites (`cmd_activate` line 983, `cmd_assert_pr_title` line 2592). The contract is internal to the function.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
