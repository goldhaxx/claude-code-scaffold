# Feature: drift-watchdog per-create self-verification

> Feature: bts-200-watchdog-self-verification
> Work: linear:BTS-200
> Created: 1777237811
> Status: In Progress

## Summary

After each `linear-query.sh save-issue` returns an ID, the drift-watchdog skill MUST immediately call `get-issue` on that ID to confirm the create actually landed with the `drift-watchdog` label. On verification failure (get-issue exits non-zero or label is missing), treat as a failed create and queue to the pending log via `idea-pending-append`. Closes the agent-hallucination class of bug surfaced during BTS-21 first-kickstart: haiku produced a one-line "Drift-watchdog complete" claiming 7 creates with ZERO actual creates landed.

## Job To Be Done

**When** the watchdog dispatches a save-issue create,
**I want** the skill to programmatically verify the create landed (not trust the agent's narrative),
**So that** future runs cannot silently report success while having created nothing.

## Acceptance Criteria

- [ ] **AC-1:** Drift-watchdog SKILL.md includes a "Verify create landed" subsection between the `save-issue` dispatch (Step 4) and the next-iteration loop. Drift-guard greps for the literal phrase `Verify create landed`.
- [ ] **AC-2:** SKILL.md prose specifies the verification command shape: `linear-query.sh get-issue $CREATED_ID` invoked immediately after a successful save. Drift-guard greps for the literal `linear-query.sh get-issue`.
- [ ] **AC-3:** SKILL.md prose specifies the label assertion: verify the returned issue's `.labels` array contains `drift-watchdog`. Drift-guard greps for the jq filter pattern `.labels | index("drift-watchdog")`.
- [ ] **AC-4:** SKILL.md prose specifies the failure path: on verification failure (get-issue rc≠0 OR label missing), invoke `bash .ccanvil/scripts/docs-check.sh idea-pending-append --op add --title "$TITLE" --body "$BODY"` to queue the create for replay via `/idea sync`. Drift-guard greps for the `idea-pending-append --op add` invocation.
- [ ] **AC-5:** SKILL.md anchors the rule on BTS-200 (this ship) and BTS-21 (origin incident — haiku hallucination). Drift-guard greps for both ticket IDs in the new section.
- [ ] **AC-6:** SKILL.md has an explicit non-trust directive: "do NOT report success based on the save-issue stdout alone — verify externally via get-issue." Drift-guard greps for a phrase matching `do not (trust|report).*save-issue` or `verify externally`.
- [ ] **AC-7:** Edge: when get-issue itself errors (network, auth), the verification path treats the create as unverified (queue to pending) rather than crashing the skill. Drift-guard asserts the SKILL.md prose mentions the network-error fallback.
- [ ] **AC-8:** Drift-guards land in `hub/tests/drift-watchdog-skill.bats` as new BTS-200-prefixed tests. Test count increases by ≥6 (one per AC-1..AC-6 + the AC-7 fallback).

## Affected Files

| File | Change |
|------|--------|
| `.claude/skills/drift-watchdog/SKILL.md` | Add "Verify create landed" subsection after Step 4 dispatch |
| `hub/tests/drift-watchdog-skill.bats` | Add ≥6 BTS-200 drift-guards |

## Dependencies

- **Requires:** Existing `linear-query.sh get-issue` (substrate primitive — already in use elsewhere). Existing `docs-check.sh idea-pending-append` (BTS-123).
- **Blocked by:** None.

## Out of Scope

- Substrate-level (script) self-verification primitive. The fix lives in skill prose; the skill agent owns the verification call. A future-future ship could pull this into a `linear-query.sh save-and-verify` primitive, but for now the prose-level guarantee is sufficient.
- End-of-run reconciliation count check (re-query list-issues + assert created+skipped == drifted-nodes). The per-create verification covers the same hallucination class; the reconciliation check is belt-and-suspenders. Tracked as a future enhancement if per-create verification proves insufficient.
- Verification of skip-because-already-exists path. The idempotency check already runs against `list-issues` at the START of every fire, so existing-issue assertions are inherently verified.
- Pruning the pending log when a deferred create lands (handled by `/idea sync` replay).

## Implementation Notes

- The per-create cost: one extra `linear-query.sh get-issue` per drifted node. At 7 nodes that's 7 extra GraphQL calls per fire — negligible compared to opus orchestration cost.
- The pending-log fallback already exists for the save-issue failure path (BTS-21's pending-log handling). The verification path reuses the same `idea-pending-append --op add` invocation, so failures from either source converge into the same replay flow.
- Anchored on BTS-21 first-kickstart (2026-04-26): `--model haiku` produced `"Drift-watchdog complete"` log without firing any creates. Sonnet executed faithfully when re-run, but the skill should not depend on the parent model being faithful — verify externally regardless.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
