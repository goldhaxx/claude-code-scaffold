# Feature: idea.add routes Linear captures to Triage via stateId

> Feature: idea-add-triage-routing
> Created: 1776968777
> Status: In Progress

## Summary

Fix BTS-121: the `idea.add` Linear resolver in `.ccanvil/scripts/operations.sh` does not pass a `stateId`, so Linear issues created via `/idea` on Linear-configured nodes land in the team's default state (Backlog) instead of Triage. The idea-triage-native feature (PR #44) built the five-state lifecycle assuming Linear would auto-route API-created issues into Triage; live smoke testing after the ship immediately falsified that assumption — BTS-121, BTS-122, and BTS-123 all landed in Backlog. The fix is to inject `params.stateId = <triage>` in the `idea.add` resolver using the exact pattern already established for `idea.promote/defer/dismiss/merge`, closing the loop on state-ID dispatch across every idea mutation.

## Job To Be Done

**When** I capture an idea with `/idea <text>` on a Linear-routed node,
**I want to** have the issue land in Linear's Triage intake surface for review,
**So that** the five-state lifecycle (Triage → Backlog/Icebox/Canceled/Duplicate) actually functions as designed instead of skipping review.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given `.claude/ccanvil.local.json` provides `integrations.providers.linear.state_ids.triage`, when `operations.sh resolve idea.add` runs, the JSON output's `.invocation.params.stateId` equals that UUID.
- [ ] **AC-2:** When the resolver in AC-1 runs, its `.invocation.params` still contains `project`, `team`, and `labels` (the existing contract); `stateId` is additive, not replacing.
- [ ] **AC-3:** Given a Linear-routed config with NO `state_ids` block, when `operations.sh resolve idea.add` runs, `.invocation.params` does NOT include a `stateId` key (backward-compatible with nodes that haven't migrated). This matches the conditional-merge pattern used by `idea.promote` at `.ccanvil/scripts/operations.sh:439`.
- [ ] **AC-4:** In all cases, `.invocation.params` does NOT include a `state` key (name-based dispatch is forbidden per the Linear state-name/type collision documented in the `/idea` skill Rules). Supersedes AC-15 in `hub/tests/ideas-to-linear.bats`.
- [ ] **AC-5:** Error: when `state_ids.triage` is present but empty string, resolver treats it as unconfigured and omits `stateId` (per conditional-merge guard `if $state_id != ""`). Passing `stateId: ""` to Linear would silently no-op or error.
- [ ] **AC-6:** Integration: the existing `/idea` skill flow (resolve → dispatch via MCP `save_issue`) is unchanged downstream of the resolver — no skill edits required, only the resolver emits the new param and Linear routes accordingly.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modified — `idea.add` Linear resolver at lines 365-376 gains triage stateId (conditional merge) |
| `hub/tests/ideas-to-linear.bats` | Modified — AC-15 test at line 113 updated to allow `stateId` key; add companion no-config test |
| `hub/tests/idea-triage-native.bats` | Modified — add `idea.add` stateId assertion (Step 2 shape); add no-state_ids test (Step 5 shape) |

## Dependencies

- **Requires:** `linear_state_id` helper (shipped PR #44 at `.ccanvil/scripts/operations.sh`); `_linear_config_with_state_ids` / `_linear_config_no_state_ids` fixtures (shipped PR #44 in `hub/tests/idea-triage-native.bats:19-65`).
- **Blocked by:** Nothing.

## Out of Scope

- No Linear workspace config changes. `state_ids.triage` is already set in `.claude/ccanvil.local.json:11`.
- No `/idea` skill doc changes — the skill already correctly follows the resolver; fix is invisible at the skill layer.
- Separately tracked: BTS-122 (pre-activate guard hardening), BTS-123 (pending-log fallback integrity). Both touch different code paths; do not bundle.

## Implementation Notes

- **Same shape as `idea.promote`** at `.ccanvil/scripts/operations.sh:428-443`. The pattern:
  ```bash
  local triage_state_id
  triage_state_id=$(linear_state_id "$provider_config" "triage")
  jq -n --arg tool "$tool" --arg state_id "$triage_state_id" \
    ... \
    '{ ..., "params":(<existing params> + (if $state_id != "" then {"stateId":$state_id} else {} end)) }'
  ```
- Existing `idea.add` resolver uses `jq -n` with multi-line merge; adapt using either `+` object-merge or an `if` branch inside the params literal.
- The stale comment at `.ccanvil/scripts/operations.sh:367-371` ("Linear routes API-created issues to the team's native Triage intake surface automatically") is the exact falsified assumption — update it to reference explicit stateId dispatch.
- TDD: write one failing bats test for AC-1 first; confirm red via `bats hub/tests/idea-triage-native.bats -f "idea.add.*stateId"` before implementing.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
