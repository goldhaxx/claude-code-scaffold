# Feature: spec dispatch + activate concurrent-edit race fix

> Feature: bts-237-spec-activate-concurrent-edit-race
> Work: linear:BTS-237
> Created: 1777341282
> Status: In Progress

## Summary

Every spec ship hits the Linear concurrent-edit guard immediately after `/spec` because:

1. `/spec` dispatches `artifact-write --kind spec` (CREATE path) → creates Linear Document with `updatedAt=T1`, caches `T1`.
2. ~500ms later, `cmd_activate` runs the same dispatch (UPDATE path) — its pre-flight check queries Linear's current `updatedAt`, gets `T2 > T1` (Linear eventual-consistency / async normalizer bumps the timestamp shortly after the create response returns), compares to cached `T1`, refuses.

Operator's only recourse: re-run with `ALLOW_CONCURRENT_EDIT_OVERRIDE=1`. Hit 4 times in session 7 + 4 times in session 8 = 8 manual retries; same workaround every time. Pure friction with no information value — there's no actual concurrent writer; the cache is "self-stale" because we're the same actor reading our own create's response.

Fix: **don't cache `updatedAt` after the CREATE path.** A fresh document has no prior writer to race against — caching the create-response timestamp produces a stale baseline that the very next UPDATE writer trips against. Skipping cache on create lets the immediate-next writer see an empty cache (treated as "first write — safe"), proceed, and seed the cache via its own UPDATE response. Subsequent writers (e.g., `/complete` after weeks of editing) then have a real baseline for genuine concurrent-edit detection.

## Job To Be Done

**When** I run `/spec` followed by `activate` on a Linear-routed node (the canonical lifecycle path),
**I want to** complete the activate step without `ALLOW_CONCURRENT_EDIT_OVERRIDE=1` retry friction,
**So that** every spec ship goes end-to-end without manual intervention, matching the autonomous-machine goal.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cmd_artifact_write` skips the `_doc_cache_set_updated_at` call on the CREATE path. The UPDATE path continues to cache the response `updatedAt` as before. Implementation: track which path was taken via a local variable (`local was_create=0`; set to `1` in the create branch; gate the post-write cache-set on `was_create == 0`).

- [ ] **AC-2:** Bats test simulating the race: with a stubbed `linear-query.sh` that returns `updatedAt=T2` from `document-updated-at` and `updatedAt=T1` from `save-document --create-with-id` (T2 > T1), the second `cmd_artifact_write` call (UPDATE) does NOT trip the concurrent-edit check. Pre-fix this test would fail; post-fix it passes.

- [ ] **AC-3:** Bats test verifying the UPDATE path STILL caches: after a successful UPDATE `cmd_artifact_write`, the cache contains the response's `updatedAt`. The cache is regenerated correctly so genuine concurrent-edit detection (different operator writing days later) still works.

- [ ] **AC-4:** Bats test verifying race-detection still works in the non-create scenario: with cache populated from a prior UPDATE response (T1), if `document-updated-at` returns T2 (advanced — simulates a real concurrent writer), `cmd_artifact_write`'s pre-flight check still refuses with exit code 4. The fix narrows cache-population scope; it does not weaken the safety check.

- [ ] **AC-5:** Live dogfood verification: run `/spec` → `activate` against a Linear-routed node without `ALLOW_CONCURRENT_EDIT_OVERRIDE=1`. The activate step's BTS-213 Linear dispatch completes cleanly (no `concurrent edit detected` error in stderr).

- [ ] **AC-6:** Drift-guard: `BTS-237` referenced inline in `docs-check.sh` near the change site, anchoring the why for future readers.

- [ ] **AC-7:** Full bats suite remains green at ≥ 1837 (post-BTS-238 baseline). The new tests (AC-2, AC-3, AC-4) are added to `hub/tests/artifact-write-concurrent-edit.bats` (or extend an existing test file if one already covers `_doc_concurrent_edit_check`).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | In `cmd_artifact_write`, skip the post-write `_doc_cache_set_updated_at` call when the just-completed write was a CREATE. |
| `hub/tests/artifact-write-concurrent-edit.bats` | New file (or extend existing). Tests AC-2, AC-3, AC-4 + drift-guard. |

## Dependencies

- **Requires:** Nothing new. The fix is a one-conditional change in `cmd_artifact_write`.
- **Blocked by:** Nothing.

## Out of Scope

- **Rewriting the cache mechanism.** A more principled fix would track per-actor sequence numbers or use Linear's optimistic-locking version field. This ship preserves the existing cache + pre-flight-check approach; only the cache-population scope changes.
- **Eliminating `ALLOW_CONCURRENT_EDIT_OVERRIDE` entirely.** The override remains as the explicit escape hatch for operator-acknowledged conflicts (e.g., recovering after a multi-actor desync).
- **Skip-on-content-match optimization.** Body-hash comparison to skip redundant writes (option (a) from BTS-237's body) is a separate concern. This ship fixes the race; the optimization can land later if friction surfaces around redundant writes.
- **Provider-neutral generalization.** The fix is specific to the Linear-Document concurrent-edit cache. Local-routed nodes don't have this surface.

## Implementation Notes

- The CREATE path is at `cmd_artifact_write` lines ~5286-5289 (uses `save-document --create-with-id`); the UPDATE path is at ~5282-5283 (uses `save-document` without `--create-with-id`).
- The post-write cache update is at lines 5292-5297. Wrap it in a conditional that fires only after UPDATE.
- Track path with `local was_create=0` set to `1` in the create branch.
- Live-API gate (AC-5) is critical: stub-only tests pass any sequencing; only a real `/spec` → activate cycle proves the race is gone.
