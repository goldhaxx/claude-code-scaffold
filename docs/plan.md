# Plan: derive-pr-title structural pivot to `> Subject:` metadata

> Feature: bts-236-derive-pr-title-subject-metadata
> Created: 1777342700
> Spec hash: 1d8142e5

## Strategy

Two coordinated changes:
1. cmd_stamp_spec auto-inserts `> Subject:` from H1 (form `# Feature: <name>`), capped ≤72 chars with word-boundary walkback. Idempotent (no insert if already present).
2. cmd_derive_pr_title reads `> Subject:` first; falls back to current Summary-extraction when absent (legacy specs grandfathered).

## TDD

- RED: 7 new tests in derive-pr-title.bats (AC-1, AC-2 prefer + fallback, AC-3, AC-5, AC-6, drift). 4 fail pre-fix.
- GREEN: cmd_stamp_spec H1 derivation + insert; cmd_derive_pr_title Subject preference.
- Suite: 1851 → 1858.
- AC-9 live gate: this ship's own PR title comes out as `feat(bts-236-derive-pr-title-subject-metadata): derive-pr-title structural pivot to ...` ≤72 chars subject.

## Files

- `.ccanvil/scripts/docs-check.sh` — cmd_stamp_spec + cmd_derive_pr_title.
- `.ccanvil/templates/spec.md` — document `> Subject:`.
- `hub/tests/derive-pr-title.bats` — 7 new tests.

## Risks

- grep-no-match under set -e: guarded with `|| true` on the `> Subject:` lookup.
- H1 with regex metacharacters: sed -nE handles parens/brackets safely (matches but doesn't interpret).
