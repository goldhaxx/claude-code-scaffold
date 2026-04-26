# Feature: refresh-plan-hash substrate primitive

> Feature: bts-177-refresh-plan-hash
> Work: linear:BTS-177
> Created: 1777217281
> Status: Complete

## Summary

Add `docs-check.sh refresh-plan-hash`: a deterministic subcommand that recomputes `docs/spec.md`'s `content_hash` and rewrites `docs/plan.md`'s `> Spec hash: <hash>` metadata line to match. Eliminates the manual plan-hash edit Claude was performing during the BTS-175 ship on 2026-04-25, when mid-flow spec scope expansion (live-API contract discovery) invalidated the plan's stored `spec_hash` and `validate` started reporting `stale-plan` until the line was hand-edited.

## Job To Be Done

**When** mid-implementation spec edits change `docs/spec.md`'s content (typically: scope expansion after live-API validation surfaces a substrate dependency),
**I want to** run a single substrate command that updates `docs/plan.md`'s `> Spec hash:` line to match the new spec hash,
**So that** `validate` returns to `aligned` and `/pr` proceeds, without Claude reading and editing a deterministic metadata line by hand.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh refresh-plan-hash` exists and accepts `[--project-dir <dir>]`. With no args, defaults to `.`.
- [ ] **AC-2:** Reads `docs/spec.md`, computes `content_hash` via the existing `content_hash` function, and rewrites `docs/plan.md`'s `> Spec hash: <old>` line to `> Spec hash: <new>`. The rest of the plan file is unchanged byte-for-byte.
- [ ] **AC-3:** Idempotent — running twice in a row leaves `docs/plan.md` unchanged on the second run, and exits 0 with a no-op message (e.g. JSON: `{"updated": false, "spec_hash": "<hash>"}`).
- [ ] **AC-4 (regression):** Given a `stale-plan` state (spec content_hash diverges from plan.spec_hash), running `refresh-plan-hash` returns `validate` to `aligned`. Test fixture: minimal spec+plan pair, mutate spec body, run validate (asserts `stale-plan`), run refresh-plan-hash, run validate again (asserts `aligned`).
- [ ] **AC-5 (error: missing spec):** When `docs/spec.md` is absent, exits non-zero with stderr `ERROR: docs/spec.md not found` and does NOT mutate plan.md.
- [ ] **AC-6 (error: missing plan):** When `docs/plan.md` is absent, exits non-zero with stderr `ERROR: docs/plan.md not found`.
- [ ] **AC-7 (error: malformed metadata):** When `docs/plan.md` exists but contains no `> Spec hash:` line, exits non-zero with stderr `ERROR: docs/plan.md has no '> Spec hash:' metadata line`. Does NOT mutate plan.md.
- [ ] **AC-8 (output JSON):** On success emits `{"updated": <bool>, "spec_hash": "<hash>", "plan": "docs/plan.md"}`. Same shape on no-op (with `updated: false`).
- [ ] **AC-9 (atomic write):** Plan rewrite uses tmpfile + `mv` so a partial write can't leave plan.md in a malformed state. Test: kill rewrite mid-flight (impossible to test cleanly; instead assert that the implementation code path uses `mktemp` + `mv` rather than `>` redirection on the destination).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_refresh_plan_hash` + dispatch case |
| `hub/tests/refresh-plan-hash.bats` | New: AC-1 through AC-8 |

## Dependencies

- **Requires:** existing `content_hash()` function (line 24), existing plan-metadata-parser (`> Spec hash:` line — already grok'd by `cmd_status` line 153 and `cmd_validate` line 430).
- **Blocked by:** Nothing.

## Out of Scope

- Auto-running this command on every spec edit (would belong in a hook; defer until proven necessary).
- Computing a new plan content_hash (the plan's own hash is independently maintained by validate; this command only refreshes the cross-reference to spec).
- Detecting whether the plan needs other revisions beyond the hash line (semantic drift between plan steps and spec ACs is a judgment call, not deterministic).

## Implementation Notes

- The substrate is mechanical: `sed -i` can rewrite the `> Spec hash:` line in place, but use `mktemp` + `mv` for atomicity per AC-9.
- Keep the implementation under 30 lines. The hash function already exists; this primitive is essentially a one-line `sed` plus the surrounding error handling and JSON output.
- Drift-guard the regex: match `^> Spec hash: [a-f0-9]{6,}` (lowercase hex; truncated sha256 is 8 chars in this codebase but the spec doesn't bind the length — accept ≥6 for forward-compat).
- BTS-127 (strict-mode bats): every test block with ≥2 `jq -e` assertions starts with `set -e`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
