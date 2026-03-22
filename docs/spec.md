# Feature: Scaffold-Wide Epoch Timestamps

> Feature: epoch-timestamps
> Created: 1742860800
> Status: In Progress

## Summary

Convert all internal timestamp fields in scaffold scripts from date strings to Unix epoch seconds. Timestamps are stored as integers (`date +%s`), displayed as human-readable via `date -r`. This aligns with the deterministic-first principle: integer comparison is deterministic, timezone-immune, and provides sub-day granularity.

## Job To Be Done

**When** I inspect lockfiles or script output containing timestamps,
**I want to** see epoch integers stored internally and human-readable dates on display,
**So that** timestamp comparison is deterministic (integer math, not string parsing) and ordering works within a single day.

## Acceptance Criteria

- [ ] **AC-1:** `scaffold-sync.sh` `timestamp()` helper returns Unix epoch seconds (integer, not ISO string).
- [ ] **AC-2:** `scaffold.lock` `synced_at` field stores epoch (integer) after init and pull-finalize.
- [ ] **AC-3:** `manifest-check.sh` `cmd_init` stores `verified` field as epoch (integer) in `manifest.lock`.
- [ ] **AC-4:** `manifest-check.sh` `cmd_verify` stores `verified` and `meta.last_verified` as epoch (integer) in `manifest.lock`.
- [ ] **AC-5:** `fetch-license.sh` retains `date +%Y` for the license year field (not converted — license text requires a year string).
- [ ] **AC-6:** Existing tests for scaffold-sync.sh continue to pass (timestamp format is not asserted on, only existence).
- [ ] **AC-7:** Existing tests for manifest-check.sh continue to pass after epoch conversion.

## Affected Files

| File | Change |
|------|--------|
| `scripts/scaffold-sync.sh` | Modified — `timestamp()` helper |
| `scripts/manifest-check.sh` | Modified — `cmd_init` and `cmd_verify` date fields |
| `.claude/manifest.lock` | Re-initialized — new epoch format |
| `tests/scaffold-sync.bats` | Possibly modified — if any test asserts date format |
| `tests/manifest-check.bats` | Possibly modified — if any test asserts date format |

## Dependencies

- **Requires:** Nothing — standalone change.
- **Blocked by:** Nothing.

## Out of Scope

- Converting `docs-check.sh` timestamps (already uses epoch via templates — implemented in docs-lifecycle-linking).
- Converting `fetch-license.sh` year field (license text requires `YYYY`).
- Adding human-readable display rendering (future enhancement — `date -r` can be added to status commands later).

## Implementation Notes

- **scaffold-sync.sh:** Single line change in `timestamp()`: `date -u +"%Y-%m-%dT%H:%M:%SZ"` → `date +%s`.
- **manifest-check.sh:** Two locations use `date +%Y-%m-%d` stored as `today` — change to `date +%s`. The variable name `today` should change to `now` for clarity.
- **Lockfile re-init:** After script changes, run `manifest-check.sh init README.md` to regenerate with epoch format.
- **Test impact:** Scaffold-sync tests check `synced_at` existence (`jq -e '.synced_at'`), not format. Manifest tests check `verified` existence via structure assertions. Both should pass without modification, but verify.
