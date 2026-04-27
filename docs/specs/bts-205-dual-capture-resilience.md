# Feature: dual-capture resilience — emergency dead-letter + local-routed capture

> Feature: bts-205-dual-capture-resilience
> Work: linear:BTS-205
> Created: 1777329561
> Status: Complete

## Summary

The `/stasis` BTS-115 dual-capture step has two silent-failure modes:

1. **Local-routed nodes** skip dual-capture entirely (`[[ "$provider" != "linear" ]] && continue`), so determinism candidates never enter the local `ideas.log`. They live only in `docs/stasis.md`'s narrative `## Determinism Review`.
2. **Linear-routed nodes** fall back to `idea-pending-append` when the http capture fails. If the pending log itself is unwritable (perms, exotic FS issue), the entry is silently lost — no dead-letter, no diagnostic.

Origin incident: a prior session's ODI-1 (Outstanding Determinism Improvement #1) appeared in `## Determinism Review` but had neither a Linear ticket NOR a `.ccanvil/ideas-pending.log` entry. Determinism candidate evaporated.

This ship closes both holes:

1. **Local-routed dual-capture** dispatches via the existing `idea-add` substrate (`.ccanvil/ideas.log` JSONL). No more silent skip.
2. **Emergency dead-letter** in `cmd_idea_pending_append`: when its own primary log write fails, it writes to `.ccanvil/dual-capture-emergency.log` with a WARN to stderr. Last-resort persistence; protects against double-failure.

## Job To Be Done

**When** I run `/stasis` and dual-capture surfaces a determinism candidate,
**I want to** know the candidate is durably persisted somewhere (Linear, local log, pending log, OR emergency dead-letter),
**So that** determinism work doesn't evaporate when capture transiently fails.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Local-routed dual-capture writes the determinism candidate via `idea-add` substrate to `.ccanvil/ideas.log`. The `## Determinism Review` candidate is recoverable via `idea-list` after `/stasis` completes.

- [ ] **AC-2:** Linear-routed dual-capture preserved — http path unchanged when the capture succeeds.

- [ ] **AC-3:** Pending-log fallback preserved — when the primary capture fails (http error, missing API key), `idea-pending-append --op add` queues the entry to `.ccanvil/ideas-pending.log` for `/idea sync` to replay.

- [ ] **AC-4:** Emergency dead-letter — when `cmd_idea_pending_append`'s primary log write fails (simulated by making the path unwritable), the entry is written to `.ccanvil/dual-capture-emergency.log` with a `WARN: idea-pending-append: primary log write failed; entry written to emergency log` line on stderr. Function returns 0 (no upstream cascade failure).

- [ ] **AC-5:** Total failure exit — when BOTH primary AND emergency log writes fail (simulated by making both paths unwritable), `cmd_idea_pending_append` exits 1 with `ERROR: idea-pending-append: both primary and emergency log writes failed`.

- [ ] **AC-6:** New bats `hub/tests/dual-capture-resilience.bats` covers AC-4 (emergency fallback), AC-5 (total failure), plus a static lock that the `/stasis` skill prose carries the BTS-205 reference and the `case "$mechanism" in bash) ... http) ...` dispatch shape.

- [ ] **AC-7:** Full bats suite remains green at ≥ 1781 (post-BTS-203 baseline). Existing `idea-pending-helpers.bats` continues to pass — emergency path is additive.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | `cmd_idea_pending_append`: add emergency dead-letter when primary append fails (BTS-205). |
| `.claude/skills/stasis/SKILL.md` | BTS-115 dual-capture section: replace `[[ "$provider" != "linear" ]] && continue` with mechanism-aware dispatch (`case "$mechanism" in bash) ... http) ...`). |
| `hub/tests/dual-capture-resilience.bats` | New bats covering AC-4 (emergency fallback), AC-5 (total failure), AC-6 (skill prose lock). |

## Dependencies

- **Requires:** BTS-115 (dual-capture substrate, original ship); BTS-123 (`idea-pending-append` helper); local `idea-add` substrate. All shipped.
- **Blocked by:** Nothing.

## Out of Scope

- `/recall` carry-forward determinism candidate surfacing — defer; the stasis emits candidates into structured logs, but the briefing-side surfacing is a separate concern.
- Local-routed dedup against `.ccanvil/ideas.log` — `idea-add` may produce duplicates if `/stasis` re-runs on the same candidate. Acceptable for v1; can ramp dedup if friction surfaces.
- Replaying the emergency log via `/idea sync` — emergency entries are operator-recoverable manually for now (cat the log, replay each via `/idea`). Auto-replay is a follow-up.

## Implementation Notes

- **Substrate change scoped to `cmd_idea_pending_append`:** the emergency fallback is added to the helper itself, so any caller of `idea-pending-append` benefits — not just the `/stasis` dual-capture path.
- **Skill prose change scoped to the BTS-115 block:** `mechanism`-aware dispatch replaces the local-skip. The dedup step remains Linear-only (local would require listing-by-title which is a separate enhancement).
- **Bats simulation pattern for AC-4/5:** create a project-dir whose `.ccanvil/` is a read-only file (forces append failure), then call `idea-pending-append` and assert the WARN line + emergency log creation. AC-5 makes both paths fail by making `.ccanvil/` itself unwritable.
- **No regressions:** all existing `idea-pending-append` callers continue to work because the new emergency path only fires on failure of the primary write.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
