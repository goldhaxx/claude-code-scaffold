# Feature: docs-check recommend defaults to /compact

> Feature: recommend-compact-default
> Created: 1776711000
> Status: In Progress

## Summary

The completed `compact-over-clear` spec updated rules, guide docs, and public-facing references to prefer `/compact` over `/clear`, but missed `.ccanvil/scripts/docs-check.sh:479` — when docs are aligned with a checkpoint, the script still recommends `/clear and /catchup to resume`. This surfaces to every user every `/catchup` run: the script's JSON output contradicts the documented preference. Narrow fix: update the one recommendation string (and its comment + test name) to match the `/compact` default.

## Job To Be Done

**When** `docs-check.sh recommend` reports an aligned-with-checkpoint state,
**I want** the recommended next_action to say `/compact` instead of `/clear`,
**So that** the script's output is consistent with the documented `/compact`-default policy and users don't inadvertently blow away context they could have preserved.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given the aligned-with-checkpoint state, when `docs-check.sh recommend` runs, then the `next_action` field contains `/compact` and does NOT contain `/clear`.
- [ ] **AC-2:** Given the aligned-with-checkpoint state, when `docs-check.sh recommend` runs, then the `reason` field mentions context preservation (`/compact`'s semantic).
- [ ] **AC-3:** The comment block in `docs-check.sh` (currently line 417) documenting the aligned-with-checkpoint branch is updated to reference `/compact` instead of `/clear`.
- [ ] **AC-4:** The bats test `hub/tests/docs-check.bats:520` (test name currently references `/clear`) is renamed to reference `/compact`, and its assertion accepts `/compact` in the output.
- [ ] **AC-5:** Regression: all other `cmd_recommend` branches (no-active-spec, unlinked, mismatched, stale-plan, stale-checkpoint, missing-determinism-review, spec-only, aligned-no-cp, fallback) produce the same output as before the change.
- [ ] **AC-6:** Full bats suite passes (`bats hub/tests/`).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — 2 lines (comment at 417, next_action + reason at 479-480) |
| `hub/tests/docs-check.bats` | Modified — test name at line 520 |

## Dependencies

- **Requires:** `compact-over-clear` spec (already Complete) — this is its remaining task.
- **Blocked by:** nothing.

## Out of Scope

- Any other `/clear` references in the codebase — the completed `compact-over-clear` spec already audited them. Remaining mentions (e.g., `README.md:358`, `.ccanvil/guide/command-reference.md:21`) are intentional "rare fallback" references per AC-3/AC-4 of that spec.
- `.ccanvil/guide/foundations.md` — protected, descriptive references per AC-9 of the prior spec.
- The `/catchup` skill itself (it already handles both `/compact` and `/clear` resumption).

## Implementation Notes

- **Target string:** change `next_action` from `"/clear and /catchup to resume"` to `"/compact to wrap session"`. `/catchup` is unnecessary after `/compact` because context is retained; adding `/catchup` would re-process the checkpoint twice.
- **Matching reason string:** rewrite to mention context preservation, e.g. `"All docs aligned with checkpoint. Run /compact to preserve context and start the next feature."`
- **Test assertion compatibility:** the existing test at line 527 already permits `/compact` via the `/catchup` match — wait, it doesn't. Current assertion is `[[ "$action" == *"/clear"* ]] || [[ "$action" == *"/catchup"* ]] || [[ "$action" == *"Continue"* ]]`. Change to accept `/compact`: `[[ "$action" == *"/compact"* ]]`.
- **Pattern to follow:** same shape as other branches in `cmd_recommend`. Imperative short phrase for next_action; one-sentence explanation in reason.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
