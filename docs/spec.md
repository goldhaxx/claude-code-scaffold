# Feature: linear-query.sh save-issue workspace-scoped label fallback

> Feature: bts-170-workspace-scoped-label-fallback
> Work: linear:BTS-170
> Created: 1777170035
> Status: In Progress

## Summary

`linear-query.sh save-issue --team NAME --labels NAME` currently resolves label NAMEs strictly through `cmd_list_labels --team-id <id>` (BTS-166's multi-team correctness fix), which filters by `team:{id:{eq:$team_id}}`. Workspace-scoped labels (where `team` is `null` in Linear) are excluded — `save-issue --team 'Blocktech Solutions' --labels 'idea'` exits 2 with `did not resolve to a label id` even when the `idea` label exists at the workspace level.

Fix: extend `cmd_list_labels` with a `--workspace-scoped` flag (filter `team:{null:{eq:true}}`); have `cmd_save_issue` fall through to a workspace-scoped lookup when the team-scoped lookup returns no match. Team-scoped wins when both exist (consistent with Linear's UI behavior). Closes the BTS-115 dual-capture bug surfaced during the 2026-04-26 stasis.

## Job To Be Done

**When** I call `save-issue --team NAME --labels NAME` for a label that's workspace-scoped (not attached to any team),
**I want** the wrapper to resolve the label correctly via a fallback unscoped lookup,
**So that** workspace-scoped labels work transparently — `/stasis` BTS-115 dual-capture and any other http-substrate caller using workspace labels stops failing on label resolution.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_list_labels --workspace-scoped` runs a GraphQL query with filter `{team:{null:{eq:true}}}`. Output contract identical to existing `cmd_list_labels`: `[{id, name}]` array.
- [ ] **AC-2:** `cmd_list_labels` rejects passing both `--team-id` and `--workspace-scoped` (or `--team` and `--workspace-scoped`) with exit 2 and a stderr error. Mutually exclusive — workspace-scoped means "no team filter," not "team filter AND null."
- [ ] **AC-3:** `save-issue --team NAME --labels NAME` succeeds when only a workspace-scoped label by that name exists. Two GraphQL queries fire: first team-scoped (returns empty), second workspace-scoped (returns the label).
- [ ] **AC-4:** `save-issue --team NAME --labels NAME` succeeds when only a team-scoped label exists. Single team-scoped query fires; no fallback round-trip when the first lookup matches by name.
- [ ] **AC-5:** Given both a team-scoped AND a workspace-scoped label by the same name exist (within the configured team), the resolved label_id is the **team-scoped** one. Team-scoped wins matches Linear's UI behavior.
- [ ] **AC-6:** When neither team-scoped nor workspace-scoped lookup finds the label, `save-issue` exits 2 with the existing error message: `save-issue: --labels '<name>' did not resolve to a label id`. No regression in the failure path.
- [ ] **AC-7:** When `save-issue` is called WITHOUT `--team` / `--team-id` (e.g., team is inferred from project, or the call only sets `--labels`), the label lookup uses the existing unscoped path (no team filter). Fallback semantics only activate when team-scoping is set AND yields no match. Drift-guard against accidentally regressing the unscoped path into "always two queries."
- [ ] **AC-8:** Edge: `save-issue --labels 'name with spaces'` (workspace-scoped) resolves correctly through both filters. Linear's IssueLabelFilter accepts arbitrary string names.
- [ ] **AC-9:** When the team-scoped lookup returns labels but none match the requested name, the fallback workspace-scoped query fires. (Empty-by-name vs empty-result-set distinction — both should fall through.)

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/linear-query.sh` | `cmd_list_labels` gains `--workspace-scoped`; `cmd_save_issue` label loop gains workspace-scoped fallback after team-scoped miss |
| `hub/tests/linear-query.bats` | New tests for AC-1 through AC-9 using the seq-aware curl stub pattern (BTS-166 fixture) |

## Dependencies

- **Requires:** BTS-166 (`cmd_list_labels --team-id`, name-based create flags) — already shipped.
- **Blocked by:** none.

## Out of Scope

- **Refactoring `cmd_list_labels` to UNION team + workspace in one query.** Linear's IssueLabelFilter doesn't support OR-of-team-filters in a single roundtrip without pagination considerations. Two sequential queries are simpler and the wall-time cost is negligible (sub-second at scale).
- **Promoting workspace-scoped labels to team-scoped.** That's a Linear-workspace governance question, not an `linear-query.sh` concern.
- **`--label-ids` flag callers.** They bypass name lookup entirely; no change needed.
- **`/stasis` BTS-115 dual-capture skill prose update.** Once this fix lands, the substrate path works as designed — no skill change required. The MCP fallback path in `/stasis` remains as defense-in-depth but won't be exercised on the happy path.

## Implementation Notes

- Follow same shape as BTS-166's `--team-id` addition to `cmd_list_labels`: small flag-parsing change, one filter-builder branch, one validation guard for mutual exclusion.
- `cmd_save_issue` label loop (line ~427-440 in `.ccanvil/scripts/linear-query.sh`): after `lid` is empty post-team-scoped lookup, retry once with `cmd_list_labels --workspace-scoped`. Reuse the same `head -1` pattern for picking the first match. Only attempt fallback when `team_id` or `team_name` was set (per AC-7 — unscoped callers don't get a second roundtrip).
- Test the seq-aware curl stub pattern from `hub/tests/linear-query.bats` line ~408 (`$BATS_TEST_TMPDIR/seq.count` counter) to script multi-roundtrip fixtures for AC-3, AC-5, AC-9.
- AC-2 mutually-exclusive guard: validate inside `cmd_list_labels` argument parsing — reject before any GraphQL roundtrip.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
