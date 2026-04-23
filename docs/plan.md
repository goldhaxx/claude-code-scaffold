# Implementation Plan: idea-triage-native

> Feature: idea-triage-native
> Created: 1776918186
> Spec hash: 41e77fe3
> Based on: docs/spec.md

## Objective

Align `/idea` with Linear-native Triage, introduce a five-state idea lifecycle, make every triage outcome ccanvil-reachable via state-ID mutations, and migrate off the deprecated custom "Idea" state.

## Sequence

### Step 1: Local-log status vocabulary (triage/backlog/icebox/canceled/duplicate)
- **Test:** `cmd_idea_add` writes `"status":"triage"` to `ideas.log`. `cmd_idea_count` recognizes both legacy (`new/promoted/parked/dismissed/merged`) and new vocabulary and sums into new-named counters.
- **Implement:** Replace default `status` in `cmd_idea_add` with `"triage"`. Update `cmd_idea_count` jq aggregator to include new status values. `cmd_idea_list --status <x>` accepts both legacy and new values (translation table).
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** `docs-check.sh idea-add "x" .` then `idea-count` shows `triage: 1`. Legacy fixture with `status:"new"` still counts under `triage` bucket.

### Step 2: State-ID config shape + lookup helper
- **Test:** `operations.sh` resolve emits `params.stateId` when config contains `integrations.providers.linear.state_ids.<role>`; emits empty/omitted when absent.
- **Implement:** Extend ccanvil.json schema to accept optional `state_ids: {triage, backlog, icebox, canceled, duplicate}`. Add `linear_state_id()` helper in `operations.sh` that reads from merged config.
- **Files:** `.ccanvil/scripts/operations.sh`, `.ccanvil/templates/ccanvil.json`, `hub/tests/idea-triage-native.bats`
- **Verify:** Test fixture with state_ids populated returns them in resolve output; fixture without returns stateId=null.

### Step 3: Capture — Linear auto-route to Triage (AC-1)
- **Test:** `idea.add` Linear resolver's `invocation.params` does NOT contain a `state` field (lets Linear API auto-route). Local resolver is unchanged.
- **Implement:** Remove `state: $idea_status` from the `idea.add` branch of `linear_mcp_adapter`. Keep `labels` and project/team.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** `resolve idea.add` with Linear config returns JSON without `.invocation.params.state`.

### Step 4: Triage listing via state ID (AC-2)
- **Test:** `idea.triage` Linear resolver passes `stateId` for Triage (not state name). Local `idea.triage` filters to `status=triage` (or legacy `status=new` via translation).
- **Implement:** Extend `linear_mcp_adapter` `idea.triage` branch to include `stateId` from `state_ids.triage`. Local bash filter already keyed on status string.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** resolve returns `params.stateId` matching config.

### Step 5: Four mutation resolvers — idea.{promote,defer,dismiss,merge} (AC-3, AC-4)
- **Test:** Each of `operations.sh resolve idea.<verb>` returns a JSON invocation with the correct target `stateId` (for Linear) or mapped status string (for local): promote→backlog, defer→icebox, dismiss→canceled, merge→duplicate. `is_valid_operation` accepts all four.
- **Implement:** Add four case branches to `is_valid_operation`. Add four branches each to `local_adapter` and `linear_mcp_adapter`. For `merge`, params include `duplicateOf: <OP_ARGS>` in addition to stateId.
- **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** `resolve idea.promote` → `params.stateId` = backlog ID; `resolve idea.merge BTS-1` → includes `duplicateOf: "BTS-1"`.

### Step 6: cmd_idea_update accepts new status vocabulary
- **Test:** `idea-update <uid> backlog` / `icebox` / `canceled` / `duplicate` all succeed and mutate the log correctly.
- **Implement:** Extend `cmd_idea_update` validation to accept the five-state vocab (reject unknowns with helpful error).
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Each status value round-trips through the log.

### Step 7: Default idea.list excludes terminal + deferred (AC-9)
- **Test:** `idea-list` default output omits entries with status in {icebox, canceled, duplicate}. `idea-list --status icebox` surfaces them explicitly.
- **Implement:** Update default `cmd_idea_list` filter. Explicit `--status <x>` flag continues to match exactly.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Fixture log with 1 each of {triage, backlog, icebox, canceled, duplicate}. Default list returns 2 (triage + backlog); `--status icebox` returns 1.

### Step 8: Icebox review command (AC-5)
- **Test:** `cmd_idea_review_icebox` returns only log entries with status=icebox and age ≥ 60d. `operations.sh resolve idea.review-icebox` works in both providers.
- **Implement:** Add `cmd_idea_review_icebox` (compares entry epoch to `$(date +%s) - 5184000`). Add `idea.review-icebox` to `is_valid_operation` + both adapters. Linear adapter uses `stateId` + `createdAt` filter in list_issues params.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `.ccanvil/scripts/operations.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Fixture with 3 icebox entries (1 fresh, 2 at ≥60d) returns 2.

### Step 9: radar-gather surfaces Icebox-stale count (AC-6, local)
- **Test:** `radar-gather` JSON contains `ideas.icebox_stale_count` equal to the count of local-log entries with status=icebox and age ≥60d.
- **Implement:** Extend the ideas block in `cmd_radar_gather` (or equivalent) to compute and emit the new field.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Fixture with 2 stale icebox entries produces `ideas.icebox_stale_count: 2`.

### Step 10: Legacy migration (AC-7)
- **Test:** `cmd_idea_migrate_state` (local) rewrites old vocab (`new→triage`, `promoted→backlog`, `parked→icebox`, `dismissed→canceled`, `merged→duplicate`) in `ideas.log`, keeping a timestamped backup. Running twice is idempotent (second run reports 0 migrations).
- **Implement:** Add `cmd_idea_migrate_state` to docs-check.sh. For Linear, emit a JSON resolution describing the needed MCP calls (list_issues in custom Idea state → save_issue with Backlog stateId) — executed by the skill, not the script.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Log with 1 entry per legacy status migrates to new vocab; second run reports 0.

### Step 11: Pending-log extension for triage-mutation failures (AC-8)
- **Test:** Append-pending for a failed promote: `.ccanvil/ideas-pending.log` gains an entry with `op: "promote"` and the target `id` + `priority`. `idea-sync` accepts and replays promote/defer/dismiss/merge intents (not just `add`).
- **Implement:** Extend `cmd_idea_sync` to dispatch per-entry based on `op` field. Document pending-log schema in script header. (Skill does the MCP call + append on failure; script handles replay.)
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/idea-triage-native.bats`
- **Verify:** Pending-log fixture with one `add` + one `promote` entry replays both without error (MCP mocked via env override).

### Step 12: Rewrite `/idea` and `/radar` skill prose
- **Test:** `bats` grep assertion: `/idea` skill contains `review-icebox`, all four outcomes (promote/defer/dismiss/merge) with state-ID references; does NOT mention state names like `"Backlog"` in the triage rubric (uses "stateId" from resolve output instead). `/radar` skill references Icebox-stale surface.
- **Implement:** Rewrite `/idea` skill's Triage section (four programmatic outcomes keyed on resolved stateId), add `/idea review-icebox` section, update `/idea list` to clarify default exclusions. Update `/radar` skill's Ideas section.
- **Files:** `.claude/skills/idea/SKILL.md`, `.claude/skills/radar/SKILL.md`, `hub/tests/idea-triage-native.bats`
- **Verify:** Grep assertions pass; manual read confirms prose is coherent + UI-free.

### Step 13: Update documentation (guide + command-reference)
- **Test:** `bats` assertion: `.ccanvil/guide/command-reference.md` contains rows for the new subcommands (`idea-migrate-state`, `idea-review-icebox`) and resolvers (`idea.{promote,defer,dismiss,merge,review-icebox}`). Linked guide sections reference the five-state model.
- **Implement:** Add rows to `.ccanvil/guide/command-reference.md`. Extend any guide section that describes idea lifecycle. CLAUDE.md updates not required (no tech-stack change; no new project-level "do not" rules).
- **Files:** `.ccanvil/guide/command-reference.md`, possibly `.ccanvil/guide/operations-architecture.md` or equivalent
- **Verify:** Grep assertions pass; bats suite green.

## Risks

- **State-ID lookup requires one-time manual population.** First-run user must invoke the lookup helper (or run `/idea` once to trigger caching). Mitigation: document explicitly in skill prose + provide `docs-check.sh idea-state-ids --sync` helper that populates `ccanvil.local.json`.
- **Local-log vocabulary migration is destructive.** Rewriting the log in place. Mitigation: timestamped backup (`ideas.log.YYYYMMDD-HHMMSS.bak`) before rewrite; refuse to run if backup write fails.
- **Linear mutation failures during triage batch could leave partial state.** If promotion of 3/5 items succeeds before MCP hiccups, 2 stay in Triage + pending-log has 2 entries. Mitigation: per-item reporting; pending-log replay idempotent; /idea triage second run picks up where it left off.
- **`/radar` Linear query adds MCP latency.** Every /radar invocation will hit Linear for Icebox-stale count. Mitigation: skill-level short-circuit — skip Linear call if a cached count from ≤10min ago exists (deferred optimization; flag if perf degrades).
- **AC-7 legacy migration is partially manual.** Deletion of the custom "Idea" state in the Linear workspace is operator-driven (Linear may block deletion of states with historical refs). Documented in migration output, not automated.
- **Hub-ship atomicity.** Skill prose + operations.sh + docs-check.sh must ship together. Mitigation: single PR; no intermediate commits to main.

## Definition of Done

- [ ] All 9 acceptance criteria from spec pass via bats tests (Linear mode with fixtures, local mode end-to-end).
- [ ] All existing tests still pass (765+ before, growing by this feature's new tests).
- [ ] Type / syntax checks clean (bash `set -euo pipefail`; jq queries validated).
- [ ] Code reviewed (run `/review`).
- [ ] The 6 legacy items (BTS-113/115/116/117/118/119) manually migrated to Backlog via the new `idea-migrate-state` flow as the first post-merge smoke test.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
