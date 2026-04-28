# Plan: stasis-carry-forward gsub regex-escape fix

> Feature: bts-238-stasis-carry-forward-gsub-regex-escape
> Created: 1777340646
> Spec hash: 1d8142e5

## Strategy

Diagnose the gsub replacement-string bug, fix it with a named-capture pattern + correct interp shape, add positive-match tests for slugs containing each regex metacharacter the gsub is supposed to escape, plus a specificity test confirming the fix doesn't broaden matching beyond literal substring containment. Live-API gate (AC-6) verifies the fix against the actual BTS-237 dual-capture this ticket was surfaced from.

## TDD steps

### Step 1 — RED: add failing tests in hub/tests/stasis-carry-forward.bats

Three new tests:
- AC-3: bolded slug `**spec dispatch + activate concurrent-edit race**` matches literal-titled `Determinism: spec dispatch + activate concurrent-edit race` idea.
- AC-4: walks each metacharacter (`+ ? ( ) [ ] { } | ^ $ .`) using plain bullet shape (avoids the bolded-shape regex which can't carry asterisks).
- AC-5: specificity — slug `foo + bar` does NOT match title `Determinism: foo - bar`.
- Drift-guard: `BTS-238` referenced inline in docs-check.sh.

Confirm 3 fail (12, 13, 16) and 1 passes (14 — original code happens to be specific enough by accident).

### Step 2 — GREEN: fix the gsub replacement

Located at `.ccanvil/scripts/docs-check.sh:4596-4609`. The bug:
- Original pattern: `[][\\\\.\\^\\$\\*\\+\\?\\(\\)\\{\\}\\|]` (no capture group).
- Original replacement: `\\\\\\(.\\)` — jq parses to `\\\(.\)`. gsub interprets the `\(.\)` as malformed interp (jq uses `\(.name)` for named-capture refs); produces literal noise.

Fix:
- New pattern: `(?<c>[][\\\\.\\^\\$\\*\\+\\?\\(\\)\\{\\}\\|])` — adds a named capture group `c` around the metacharacter class.
- New replacement: `\\\(.c)` — jq parses to `\\(.c)`, gsub interprets as literal backslash + interp of named capture `.c` → produces `\<char>`.

This is the canonical jq idiom for regex-escaping in gsub.

### Step 3 — full suite verify

Confirm 1837 passing (1833 baseline + 4 new).

### Step 4 — AC-6 live-API gate

Run `bash .ccanvil/scripts/docs-check.sh stasis-carry-forward --project-dir .` against the live node — confirm `count_carry_forward: 0` and `has_idea: true` for the BTS-237 candidate.

### Step 5 — commit, /pr-cleanup, /ship

## Affected files

- `.ccanvil/scripts/docs-check.sh` — single jq pattern + replacement change in `cmd_stasis_carry_forward` (lines 4596-4609).
- `hub/tests/stasis-carry-forward.bats` — 4 new tests + drift-guard.

## Risks

- **Other call sites:** none. Grep confirms `cmd_stasis_carry_forward` is the only consumer of this gsub pattern shape.
- **Regression on existing matches:** none — the named-capture pattern matches the same character set as the original; only the replacement string changes from "produces garbage" to "produces correct escape sequence". Existing matching slugs (no metacharacters) hit the no-match branch of the gsub and emerge unchanged.
