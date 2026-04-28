# Feature: derive-pr-title structural pivot to `> Subject:` metadata field

> Feature: bts-236-derive-pr-title-subject-metadata
> Work: linear:BTS-236
> Created: 1777342700
> Status: Complete

## Summary

`cmd_derive_pr_title` produces mid-sentence truncated PR subjects on multiple recent ships (PRs #128, #131, #132, #133 — every multi-paragraph spec). The current logic extracts the first line of the `## Summary` section, period-strips, then hard-caps at 80 chars with an 8-char word-boundary lookback. Verbose Summary openers and trailing punctuation that lacks a space/tab/hyphen in the lookback window defeat it.

Structural pivot: add a `> Subject:` metadata field to the spec preamble, populated automatically by `cmd_stamp_spec` from the spec's H1 (which is naturally short and operator-controlled). `cmd_derive_pr_title` reads `> Subject:` first; falls back to the existing prose-truncate path for legacy specs without the field.

The H1 derivation works because spec H1s ALL follow the form `# Feature: <imperative-name>` and are operator-controlled to be short — a structural property the PR-subject pipeline can rely on, unlike the verbose Summary paragraph.

## Job To Be Done

**When** I ship a feature whose spec opens with a multi-clause Summary paragraph,
**I want to** see a clean ≤72-char imperative PR title without manual `gh pr edit` repair,
**So that** the squash-merge commit on main carries a readable subject — supporting `git log --oneline` discoverability and matching the autonomous-machine goal.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_stamp_spec` inserts a `> Subject: <derived>` line into the spec preamble when no `> Subject:` line is present. The derivation strips `# Feature: ` from the H1 and uses the remainder as the subject. If the H1 doesn't match the form `# Feature: ...`, the Subject line is omitted (graceful — falls back to current logic).

- [ ] **AC-2:** `cmd_derive_pr_title` reads `> Subject:` from spec metadata. When present and non-empty, uses it directly as the subject (after the `feat(<feature-id>):` prefix). When absent, falls back to the existing first-line-of-Summary period-strip+truncate logic.

- [ ] **AC-3:** Subject ≤72 chars: when the H1 (post-strip) exceeds 72 chars, `cmd_stamp_spec` truncates with word-boundary walkback (same algorithm as cmd_derive_pr_title's 80-char path, but applied at /spec time on the H1 — which is shorter and cleaner than Summary prose).

- [ ] **AC-4:** Bats: spec with `> Subject: clean imperative line` produces PR title `feat(<id>): clean imperative line`. Spec without `> Subject:` falls back to existing Summary-extraction (regression — existing tests pass).

- [ ] **AC-5:** Bats: cmd_stamp_spec on a fresh spec inserts `> Subject:` derived from H1. Re-running cmd_stamp_spec on the same spec is idempotent (doesn't duplicate the Subject line).

- [ ] **AC-6:** Bats: cmd_stamp_spec on a spec without H1 (or with malformed H1) skips the Subject insertion gracefully (no error, no Subject line — falls back to existing derive-pr-title).

- [ ] **AC-7:** `.ccanvil/templates/spec.md` documents the `> Subject:` field as auto-populated, operator-overrideable, ≤72 char imperative one-liner.

- [ ] **AC-8:** Drift-guard: `BTS-236` referenced inline in `cmd_stamp_spec` AND `cmd_derive_pr_title`.

- [ ] **AC-9:** Live AC: this ship's own PR title — `feat(bts-236-derive-pr-title-subject-metadata): derive-pr-title structural pivot to ...` — comes out clean (≤72 chars in subject, no mid-word cut). Live-API gate per `.claude/rules/tdd.md` — proves the fix end-to-end.

- [ ] **AC-10:** Full bats suite ≥ 1851 (post-BTS-211 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | `cmd_stamp_spec`: insert `> Subject:` from H1. `cmd_derive_pr_title`: prefer `> Subject:` over Summary extraction. |
| `.ccanvil/templates/spec.md` | Document the `> Subject:` field. |
| `hub/tests/derive-pr-title.bats` (existing) or new `pr-title-subject-metadata.bats` | Tests for AC-2, AC-4, AC-5, AC-6. |

## Out of Scope

- **Operator-typed Subject at /spec time.** /spec auto-derivation is sufficient for the autonomous-machine goal; manual override remains available (operator edits the metadata block directly between /spec and /pr).
- **Migration of existing specs.** Legacy specs without `> Subject:` continue using the prose-truncate fallback. No backfill needed.
- **Alternate truncation algorithms.** The H1-based subject is naturally short; the 72-char cap with word-boundary walkback is sufficient.

## Implementation Notes

- H1 derivation logic: `head -1 "$spec_path" | sed -nE 's/^# Feature: (.+)$/\1/p'`. Empty result → skip Subject insertion.
- Insertion point: after the `> Created:` line. Use awk's range pattern.
- 72-char cap with word-boundary walkback (8-char lookback for space/tab/hyphen/comma/colon).
- cmd_derive_pr_title precedence: `> Subject:` > Summary first-line. When using Subject, the period-strip and 80-char truncation paths are skipped (subject is already correctly shaped at /spec time).
