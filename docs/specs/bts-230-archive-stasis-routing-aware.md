# Feature: archive-stasis routing-aware (read from Linear Document on Linear-routed nodes)

> Feature: bts-230-archive-stasis-routing-aware
> Work: linear:BTS-230
> Created: 1777328545
> Status: Complete

## Summary

`cmd_archive_stasis` reads `docs/stasis.md` from disk to produce the cross-session archive at `docs/sessions/<epoch>-<feature_id>.md`. On Linear-routed nodes (`integrations.routing.stasis=linear`), the stasis lives in a Linear Document, not on disk, and `archive-stasis` errors with `docs/stasis.md not found`. Discovered during BTS-217's session-stasis flow on 2026-04-27 — the operator manually replayed the archive, but `/recall`'s cross-session history (via BTS-22's `sessions-list`) silently degrades when archives are missing.

This ship makes `cmd_archive_stasis` routing-aware. When `route-of stasis = linear`, content is read via the existing `cmd_artifact_read` primitive (BTS-204/213 substrate) — session-kind first (most common), feature-kind fallback (when `docs/spec.md` is present and carries a `> Feature:` line). Output destination unchanged. Pattern matches `cmd_complete`'s existing routing-aware read path.

## Job To Be Done

**When** I run `archive-stasis` on a Linear-routed node after a `/stasis` write,
**I want to** have the archive populate `docs/sessions/<epoch>-<id>.md` correctly,
**So that** `/recall`'s cross-session history doesn't degrade and I don't have to manually replay the archive.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Linear-routed + session-kind: when `routing.stasis=linear` and a session-kind stasis Document exists, `archive-stasis` reads it via `cmd_artifact_read --kind stasis --stasis-kind session` and writes `docs/sessions/<epoch>-<feature_id>.md` correctly. Output JSON: `{archived: true, path: "docs/sessions/..."}`.

- [ ] **AC-2:** Linear-routed + feature-kind: when `routing.stasis=linear` and session-kind read returns empty, archive-stasis falls back to feature-kind by reading `> Feature:` from `docs/spec.md` and calling `cmd_artifact_read --kind stasis --feature <id>`. Same output shape.

- [ ] **AC-3:** Local-routed regression: when `routing.stasis=local` (or unset) and `docs/stasis.md` exists, archive-stasis still reads from disk (existing behavior). No regression.

- [ ] **AC-4:** Linear-routed + no content: when `routing.stasis=linear` and BOTH session-kind read AND feature-kind fallback fail, archive-stasis exits 1 with `ERROR: archive-stasis: routing.stasis=linear but no stasis content found (tried session-kind, feature-kind)`. Clear diagnostic, no silent failure.

- [ ] **AC-5:** Idempotency preserved: byte-identical content produces `{archived: false, reason: "already-archived"}` (existing behavior, both routes).

- [ ] **AC-6:** Collision preserved: non-identical content at the destination still errors `{error: "collision", existing: ...}` and exits 1 (existing behavior, both routes).

- [ ] **AC-7:** New bats `hub/tests/archive-stasis-routing.bats` covers AC-1 through AC-4 with stubbed `cmd_artifact_read` (no live API). AC-5/6 covered by existing bats.

- [ ] **AC-8:** Full bats suite remains green at ≥ 1771 (post-BTS-202 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | `cmd_archive_stasis`: routing-aware source selection at the top of the function. Restructure parse-and-write to operate on `$stasis_content` variable instead of `$stasis_file`. |
| `hub/tests/archive-stasis-routing.bats` | New bats covering AC-1 through AC-4 via `cmd_artifact_read` stub. |

## Dependencies

- **Requires:** BTS-204 (`cmd_artifact_read` primitive), BTS-213 (route-aware dispatch), BTS-22 (`docs/sessions/` archive substrate). All shipped.
- **Blocked by:** Nothing.

## Out of Scope

- Auto-deriving stasis kind without trying both — would require a definitive lifecycle-state read at archive time. Try-session-then-feature is simple and covers all cases.
- Caching the stasis content between `cmd_archive_stasis` invocations — single call per session boundary; caching not warranted.

## Implementation Notes

- **Routing-aware read pattern:** matches `cmd_complete`'s `_has_any_linear_route` fast-path. Keep the same structure: detect route, read into a variable, then run the existing parse+write logic on the variable.
- **Destination unchanged:** `docs/sessions/<epoch>-<feature_id>.md` is local on every node regardless of routing. Only the SOURCE switches.
- **Bats stubbing:** override `cmd_artifact_read` in the test fixture to return canned stasis content. Verify the routing branch is exercised by checking for the BTS-230 reference in the source.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
