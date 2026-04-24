# Feature: Linear Dispatch stateId → state Rename

> Feature: bts-139-linear-state-param-fix
> Work: linear:BTS-139
> Created: 1777064736
> Status: Draft

## Summary

Linear's MCP `save_issue` tool accepts a parameter named `state` (documented as "State type, name, or ID"), NOT `stateId`. ccanvil's `operations.sh` resolver emits `params.stateId` everywhere, and the `/idea` skill documents the same. Linear silently ignores the unknown `stateId` parameter and falls through to the team's default state (Backlog) — this is why BTS-138 + BTS-139 landed in Backlog despite the correct Triage UUID being configured and wired end-to-end.

Empirical evidence from this session: manual transitions I dispatched with `state: <uuid>` succeeded (BTS-138 → Done, BTS-131 → Duplicate). Captures where the skill's literal `stateId: <uuid>` shape was followed failed silently. Fix: rename `stateId` → `state` in every resolver emission + skill doc + test assertion. No behavior change for the rename itself — it's a naming correction so dispatch actually matches the MCP tool's schema.

## Job To Be Done

**When** the `/idea` skill or any resolver-consumer dispatches `save_issue` with a state target,
**I want** the parameter name to match Linear's MCP tool schema (`state`, not `stateId`),
**So that** captures land in Triage and transitions actually transition — instead of silently no-opping to the team's default state.

## Acceptance Criteria

- [ ] **AC-1:** `operations.sh resolve idea.add --project-dir <linear-node>` emits `.invocation.params.state` (the configured Triage UUID) and does NOT emit `.invocation.params.stateId`.
- [ ] **AC-2:** `operations.sh resolve ticket.transition <id> <role>` emits `.invocation.params.state` and does NOT emit `.invocation.params.stateId`. Verified for roles: `triage`, `backlog`, `icebox`, `canceled`, `duplicate`, `done`.
- [ ] **AC-3:** All four `/idea triage` mutation verbs (`promote`, `defer`, `dismiss`, `merge`) resolve to `params.state` (not `stateId`).
- [ ] **AC-4:** `/idea review-icebox`'s `list_issues` resolution uses `params.state` (not `stateId`).
- [ ] **AC-5:** Empty-state guard unchanged: when no `state_ids.<role>` is configured, `params.state` is simply absent (NOT empty string) — preserves the "don't pass empty to Linear" semantic. Existing behavior for unconfigured nodes continues.
- [ ] **AC-6:** `.claude/skills/idea/SKILL.md` documents `state` (not `stateId`) in all 15+ references. Same for `.claude/commands/land.md` and `.ccanvil/guide/command-reference.md`.
- [ ] **AC-7:** All existing bats tests pass after the rename. Specifically: `hub/tests/idea-triage-native.bats` (38 refs), `hub/tests/ideas-to-linear.bats` (3 refs), `hub/tests/ticket-transition.bats` (7 refs) are updated to assert `state` instead of `stateId`.
- [ ] **AC-8:** NEW regression test: `hub/tests/stateid-rename-regression.bats` asserts that resolver outputs NEVER contain the key `stateId`. Runs across `idea.add`, `ticket.transition <id> <all-roles>`, `idea.triage`, `idea.review-icebox`. Guards against re-introduction.
- [ ] **AC-9:** No "dual-emit" compatibility shim. The resolver emits ONE key only (`state`). If downstream consumers were relying on `stateId`, they're part of this fix's scope and will be migrated in the same commit.
- [ ] **AC-10:** Dogfood-close: this ship's own `/idea` capture (if needed mid-ship for any reason) lands in Triage correctly. Its own `/land` auto-closes BTS-139 to Done via the renamed `state` param.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — 19 `stateId` → `state` renames in resolver emission paths |
| `.claude/skills/idea/SKILL.md` | Modified — 15+ doc references updated |
| `.claude/commands/land.md` | Modified — dispatch instruction updated |
| `.ccanvil/guide/command-reference.md` | Modified — 2 refs updated (ticket.transition row + 5-state lifecycle blurb) |
| `hub/tests/idea-triage-native.bats` | Modified — 38 assertion updates |
| `hub/tests/ideas-to-linear.bats` | Modified — 3 assertion updates |
| `hub/tests/ticket-transition.bats` | Modified — 7 assertion updates |
| `hub/tests/stateid-rename-regression.bats` | NEW — asserts `stateId` never appears in resolver output (AC-8) |

## Dependencies

- **Requires:** nothing. This is a standalone naming fix.
- **Blocked by:** nothing.

## Out of Scope

- Investigating *when* Linear's MCP renamed the parameter (the historical change is irrelevant — what matters is the current schema).
- Updating `.claude/ccanvil.local.json`'s `state_ids` key — that's a configuration key read by the resolver, not a parameter passed to the MCP. Stays as-is.
- Any other `/idea` functionality. This is strictly a parameter-name rename.

## Implementation Notes

- **Approach:** bulk rename in operations.sh (`"stateId":` → `"state":` in the jq emissions), cascade into test assertions, cascade into skill docs.
- **AC-8 is the guard rail.** Without it, a future well-meaning PR could re-introduce `stateId` (especially if someone drafts code against stale skill docs). The regression test makes this class of bug loud.
- **No semantic change.** The UUID passed is identical in both cases — only the key name changes. Linear's `state` parameter accepts "State type, name, or ID" (per the MCP schema); we pass UUID, matching the "ID" case.
- **One PR, one commit per logical step.** Step 1: add regression test (RED). Step 2: rename operations.sh (partial GREEN). Step 3: update test assertions (full GREEN). Step 4: update skill + command docs.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
