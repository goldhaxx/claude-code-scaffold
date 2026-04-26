# Feature: assert-pr-title substrate primitive

> Feature: bts-178-assert-pr-title
> Work: linear:BTS-178
> Created: 1777217843
> Status: Complete

## Summary

Add `docs-check.sh assert-pr-title <pr-number>`: a deterministic subcommand that reads the live PR title via `gh pr view`, computes the expected `feat(<feature-id>): <first-summary-line>` title from `docs/spec.md` (or `docs/specs/<feature-id>.md` when the active spec is gone post-cleanup), and force-updates via `gh pr edit` when the existing title is missing the `feat(<feature-id>):` prefix or matches a known placeholder pattern. Wires into `/pr` skill prose so the squash-merge commit on main always carries the correct title.

Surfaced 2026-04-25: PR #99 (BTS-175) squash-merged with commit subject `feat(auth-system): Auth feature. (#99)` — a placeholder title from some earlier `gh` interaction. `/pr`'s title resolution didn't fire because the PR already existed by the time `/pr` ran.

## Job To Be Done

**When** `/pr` is finalizing a draft PR for merge,
**I want to** run a single substrate command that asserts the PR's live title matches the spec-derived expected form (and force-updates it if not),
**So that** the squash-merge commit on main always carries `feat(<feature-id>): <summary>` — never a placeholder like `feat(auth-system)` or `feat(default)`.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh assert-pr-title <pr-number>` exists. Accepts `[--project-dir <dir>]`. With matching title, exits 0 with JSON `{updated:false, expected:"<title>", actual:"<title>"}` and does NOT call `gh pr edit`.
- [ ] **AC-2 (force-update path):** When live title is "placeholder-shaped" — matches `^feat\(auth-system\)`, `^feat\(default\)`, or does NOT start with `feat(<feature-id>):` where feature-id matches the active spec — calls `gh pr edit <pr-number> --title "<expected>"` and exits 0 with JSON `{updated:true, expected:"<title>", actual:"<previous-title>"}`.
- [ ] **AC-3 (no-op happy path):** When live title already starts with `feat(<feature-id>):`, no `gh pr edit` is called, output JSON has `updated:false`. Even if the summary text after the colon differs from spec's first line — we trust user edits to the descriptive part as long as the prefix is correct.
- [ ] **AC-4 (post-cleanup spec source):** When `docs/spec.md` is absent but `docs/specs/<feature-id>.md` exists (post `/pr` lifecycle cleanup), reads the archived spec to derive the expected title. The feature-id is recovered from the current branch name (`claude/feat/<feature-id>` → `<feature-id>`).
- [ ] **AC-5 (error: missing spec):** When neither `docs/spec.md` nor a matching archived spec exists, exits non-zero with stderr `ERROR: no spec found for branch '<branch>' to derive expected title`. Does NOT call `gh pr edit`.
- [ ] **AC-6 (error: gh unavailable):** When `gh` CLI is not on PATH, exits non-zero with stderr `ERROR: gh CLI not available — assert-pr-title requires GitHub CLI`. Does NOT attempt to read or modify anything.
- [ ] **AC-7 (skill drift-guard):** A bats test asserts the `/pr` skill prose in `.claude/skills/pr/SKILL.md` contains a literal `assert-pr-title` invocation in the post-`gh pr ready` step.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_assert_pr_title` + dispatch case |
| `.claude/skills/pr/SKILL.md` | Add `assert-pr-title` step after `gh pr ready` (or the equivalent ready-marking step) |
| `hub/tests/assert-pr-title.bats` | New: AC-1 through AC-6 |
| `hub/tests/pr-skill-assert-title.bats` | New: AC-7 drift-guard |

## Dependencies

- **Requires:** `gh` CLI (already a hard requirement of `/pr`); existing spec-metadata-parser; existing first-summary-line extraction at activate (line 983 of docs-check.sh).
- **Blocked by:** Nothing.

## Out of Scope

- Auto-running on every PR open (would require a hook or PR-creation interception); defer.
- Updating the PR body (separate concern; `/pr` already handles body).
- Detecting drift between `gh pr create`'s real failures and the silent-create-with-default-title case (the `cmd_activate` "NOTE: gh pr create failed" message stays as-is — assert-pr-title fixes the symptom directly).
- Idempotent re-runs guaranteed by AC-3 — a no-op call costs one `gh pr view` round-trip.

## Implementation Notes

- Reuse the title-derivation logic from `cmd_activate` (line 983-984): `sed -n '/^## Summary$/,/^## /{...}'` extracts the first non-blank summary line; `feat(<feature-id>): <line>`.
- For placeholder detection, the explicit pattern list keeps the rule conservative — we don't want `assert-pr-title` to overwrite a thoughtful manual title that uses a non-`feat(...)` prefix (e.g. `chore(...)` or `fix(...)`). Placeholder set: `feat(auth-system)`, `feat(default)`. Plus the catch-all "doesn't start with feat(<feature-id>):" — which catches the case where someone edited the title to a different feat scope but still spec-mismatched.
- Use `gh pr view <n> --json title --jq .title` to read the title; `gh pr edit <n> --title "<new>"` to write.
- BTS-127: tests with ≥2 `jq -e` start with `set -e`.
- Drift-guard bats: `pr-skill-assert-title.bats` greps `.claude/skills/pr/SKILL.md` for the literal `assert-pr-title` call in the post-ready section.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
