# Feature: stasis-carry-forward gsub regex-escape fix

> Feature: bts-238-stasis-carry-forward-gsub-regex-escape
> Work: linear:BTS-238
> Created: 1777340646
> Status: Complete

## Summary

`cmd_stasis_carry_forward` (BTS-232, `.ccanvil/scripts/docs-check.sh:4596-4609`) builds a regex by gsub-escaping metacharacters in the candidate slug, then runs a case-insensitive substring match against existing Linear idea titles. The replacement string is malformed: instead of producing `\<char>` (backslash + matched char) it produces the literal string `\\\(.)` for every metacharacter match. Slugs containing regex metacharacters like `+`, `*`, `?`, `(`, `)`, `[`, `]`, `{`, `}`, `|`, `^`, `$`, `.` never match their own dual-capture, so the carry-forward substrate emits false-positive `has_idea: false` reports. The substrate built to surface dual-capture drops surfaces phantom drops instead.

Live evidence (PR #125 dogfood, /recall on session 9): the BTS-237 dual-capture (title `Determinism: spec dispatch + activate concurrent-edit race`, contains `+`) is in Backlog state in Linear, but `stasis-carry-forward` reports `has_idea: false` for the slug `spec dispatch + activate concurrent-edit race`. Empirical jq trace:

```
$ jq -n '"spec dispatch + activate concurrent-edit race" | gsub("[][\\\\.\\^\\$\\*\\+\\?\\(\\)\\{\\}\\|]"; "\\\\\\(.\\)")'
"spec dispatch \\\\\\(.\\) activate concurrent-edit race"
```

The downstream `test("(?i)Determinism:.*" + escaped_slug)` regex never matches the live title containing a literal `+`.

## Job To Be Done

**When** I run `/recall` after a session whose `## Determinism Review` listed a candidate whose slug contains regex metacharacters,
**I want to** see the carry-forward substrate correctly identify the dual-captured idea (when present),
**So that** I trust `count_carry_forward` as the dual-capture safety-net signal it was built to provide.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cmd_stasis_carry_forward`'s gsub replacement string is corrected from `"\\\\\\(.\\)"` to `"\\\\\\(.)"`. The corrected jq parses to `\\\(.)`, which gsub interprets as a literal backslash followed by the captured character — producing the intended `\<char>` regex-escape sequence.

- [ ] **AC-2:** Empirical trace verification — running `jq -n '"foo + bar" | gsub("[][\\\\.\\^\\$\\*\\+\\?\\(\\)\\{\\}\\|]"; "\\\\\\(.)")'` produces `"foo \\+ bar"` (one literal backslash + the matched `+` in the JSON-rendered output, which is `\+` in the actual string).

- [ ] **AC-3:** Bats test fixture: a stasis content carrying `## Determinism Review` with a candidate whose slug contains `+` (e.g., `spec dispatch + activate concurrent-edit race`), paired with an idea-listing fixture containing the matching `Determinism: spec dispatch + activate concurrent-edit race` title, produces `count_carry_forward: 0` and `has_idea: true` for that candidate.

- [ ] **AC-4:** Bats test fixture: same setup but with the slug containing each individual metacharacter (`*`, `?`, `(`, `)`, `[`, `]`, `{`, `}`, `|`, `^`, `$`, `.`) — each must match its own literal-titled idea. One test per metacharacter, or one parameterized test that walks the full set.

- [ ] **AC-5:** Bats test fixture: a slug containing `+` does NOT match an idea title that uses a different character at that position (e.g., slug `foo + bar` does NOT match title `Determinism: foo - bar`). Confirms the fix preserves the original specificity — `+` is treated as a literal `+`, not as a regex one-or-more quantifier.

- [ ] **AC-6:** Live dogfood verification — after the fix, running `bash .ccanvil/scripts/docs-check.sh stasis-carry-forward --project-dir .` against the current node (whose prior stasis listed `spec dispatch + activate concurrent-edit race` and whose Linear idea listing contains BTS-237) produces `count_carry_forward: 0`. This is the live-API gate (per `.claude/rules/tdd.md`) — stub tests pass any regex shape; only the live call verifies the contract end-to-end.

- [ ] **AC-7:** Full bats suite remains green at ≥ 1833 (post-BTS-215 baseline). The new tests (AC-3, AC-4, AC-5) are added to `hub/tests/stasis-carry-forward.bats`; no existing tests should regress.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | One-character fix to the gsub replacement string in `cmd_stasis_carry_forward` (line 4602). |
| `hub/tests/stasis-carry-forward.bats` | Add tests AC-3 through AC-5 — slug+metacharacter fixtures with matching/non-matching idea-listing fixtures. |

## Dependencies

- **Requires:** Nothing new. The fix is a one-character change in an existing jq replacement string.
- **Blocked by:** Nothing.

## Out of Scope

- **Re-architecture of the matching logic.** A more principled fix would use jq's `gsub` with a proper backref pattern, or skip regex entirely and use `index` for substring matching. This ship preserves the existing approach and only fixes the malformed replacement.
- **Generalization to other gsub call sites.** A grep of the codebase shows `cmd_stasis_carry_forward` is the only place using this pattern; no other consumers carry the same bug.
- **Behavior change on malformed slugs.** The matching remains case-insensitive substring containment; the only change is that metacharacters are now correctly escaped.

## Implementation Notes

- The fix is one character: remove the trailing `\\)` from the replacement string. Old: `"\\\\\\(.\\)"` (jq parses to `\\\(.\)`, gsub sees backslash + jq-interp `\(.\)` → undefined behavior, emits literal). New: `"\\\\\\(.)"` (jq parses to `\\\(.)`, gsub sees backslash + jq-interp `\(.)` → backslash + matched char).
- The drift-guard bats test in `hub/tests/stasis-carry-forward.bats` should be updated to ALSO include a positive-match fixture with `+` — otherwise this class of bug remains invisible to fixture-only tests.
- The live-API gate (AC-6) is critical: stubs accept any regex shape; only the live call verifies the contract.
