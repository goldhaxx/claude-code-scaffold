# Feature: Idea UIDs and Epoch Timestamps

> Feature: idea-uids
> Created: 1776109964
> Status: In Progress

## Summary

Replace sequential line-number IDs with stable 4-character UIDs and human-readable dates with epoch timestamps. Ideas become referenceable across sessions — reordering the file doesn't break references, and timestamps sort unambiguously.

## Job To Be Done

**When** capturing and triaging ideas across multiple sessions,
**I want to** reference ideas by a stable ID that doesn't change when the file is reordered,
**So that** triage decisions, promotion references, and cross-session updates are reliable.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `idea-add` generates a 4-char hex UID and epoch timestamp for each new idea
- [ ] **AC-2:** New idea format: `- [ ] <uid> <epoch>: <text> <!-- status:new -->`
- [ ] **AC-3:** `idea-list` returns `id` (uid) and `created` (epoch) instead of `num` and `date`
- [ ] **AC-4:** `idea-update` accepts a UID (not a number) and updates the matching line
- [ ] **AC-5:** `idea-update` still works with numeric index as fallback for backwards compatibility
- [ ] **AC-6:** `idea-count` works unchanged with new format
- [ ] **AC-7:** Existing ideas.md with old format still parse correctly (backwards compatible reading)
- [ ] **AC-8:** Edge: `idea-update` with nonexistent UID exits with clear error

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — all 4 idea functions |
| `hub/tests/docs-check.bats` | Modified — update idea tests |
| `.claude/skills/idea/SKILL.md` | Modified — update usage examples |
| `docs/ideas.md` | Migrated — existing ideas get UIDs on next update |

## Dependencies

- **Requires:** None
- **Blocked by:** None

## Out of Scope

- Migrating existing ideas.md entries automatically (old format reads fine, new entries use new format)
- Changing the status vocabulary (new, promoted, merged, dismissed, parked)
- Changing idea-count output format

## Implementation Notes

- UID: 4 hex chars from `head -c 2 /dev/urandom | xxd -p` (65536 possibilities — plenty for ideas)
- Format: `- [ ] a1b2 1776109964: idea text here <!-- status:new -->`
- `idea-list` regex must match BOTH old format (`YYYY-MM-DD:`) and new format (`<uid> <epoch>:`)
- `idea-update` first tries UID match, falls back to Nth-line if arg is numeric
- Keep `idea-count` logic unchanged — it only reads status comments
