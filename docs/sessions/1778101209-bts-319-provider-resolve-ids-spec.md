# Feature: provider-resolve-ids substrate primitive (Phase 1)

> Feature: bts-319-provider-resolve-ids
> Work: linear:BTS-319
> Created: 1778097957
> Subject: provider-resolve-ids substrate primitive (Phase 1)
> Status: In Progress

## Summary

Add `docs-check.sh provider-resolve-ids` — a single-verb substrate primitive that resolves a Linear provider's IDs (team_id, project_id, eight state_ids by canonical role names, label_ids\[idea\]) from live Linear queries and deep-merges them into `.claude/ccanvil.local.json`'s `integrations.providers.linear` block. Phase 1 of BTS-319 (the `provider-heal` umbrella surfaced by the unifi-toolbox dogfood 2026-05-06). Closes the highest-friction gap of the heal flow: the manual chain of 4 separate `linear-query.sh` calls + jq composition that took \~12 substrate operations on unifi-toolbox, collapsed to one verb. Out of scope for Phase 1: substrate-drift handling (`pull-auto-with-new`), `LINEAR_API_KEY` preflight, dispatch smoke-test verification — captured separately under BTS-316.

## Job To Be Done

**When** I have a node with `routing.idea = "linear"` but missing `team_id`/`project_id`/`state_ids`/`label_ids` (the unifi-toolbox-shaped partial init),
**I want to** run one substrate command that resolves all required IDs from Linear and writes them into the local config,
**So that** `operations.sh resolve idea.list` immediately dispatches successfully without manual jq composition or 4 separate `linear-query.sh` calls.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh provider-resolve-ids --provider linear --team <name> --project <name> --project-dir <path>` exits 0 on success and writes a complete `integrations.providers.linear` block containing `team_id`, `project_id`, `state_ids` (object with 8 canonical keys: `triage`, `backlog`, `icebox`, `todo`, `in_progress`, `done`, `duplicate`, `canceled`), and `label_ids` (object with `idea` key minimum) into `<path>/.claude/ccanvil.local.json`.
- [ ] **AC-2:** State-id resolution maps Linear state names to canonical role keys by name (case-insensitive): "Triage"→triage, "Backlog"→backlog, "Icebox"→icebox, "Todo"→todo, "In Progress"→in_progress, "Done"→done, "Duplicate"→duplicate, "Canceled"→canceled. Extra states in Linear (e.g., team-custom "Idea" state) are silently ignored.
- [ ] **AC-3:** Workspace-vs-team label fallback (BTS-170 anchor): label resolution first tries `linear-query.sh list-labels --team <name>`; if that returns `[]`, retries with `linear-query.sh list-labels --workspace-scoped`. The `idea` label is found via this fallback chain.
- [ ] **AC-4:** Deep-merge preserves existing keys: `node_uuid`, `integrations.routing.*`, and any other custom keys in `.claude/ccanvil.local.json` are preserved verbatim. Only the `integrations.providers.linear` slice is augmented; the existing `team` and `project` string keys are preserved alongside the new `_id` keys.
- [ ] **AC-5:** Idempotent: running `provider-resolve-ids` twice in succession with the same args produces byte-identical output on the second call (no spurious mutation, no duplicate keys).
- [ ] **AC-6:** Error: when team-name does not resolve via `list-teams`, exits non-zero with a clear stderr message naming the missing team and suggesting the operator verify spelling against Linear's team list. Same shape for missing project (exits non-zero, names project + filters by team in the error). No partial config write on failure.
- [ ] **AC-7:** Error: when no `idea` label is found in either team or workspace scope, the substrate emits a WARN to stderr (`WARN: idea label not resolved — capture-via-/idea will fail`) but writes the rest of the config and exits 0. Operator decides whether to create the workspace label and re-run.
- [ ] **AC-8:** Bats coverage: new `hub/tests/provider-resolve-ids.bats` uses `LINEAR_QUERY_OVERRIDE` stub pattern (mirror of `hub/tests/artifact-write-concurrent-edit.bats`) to test ACs 1-7 with deterministic stubbed responses.
- [ ] **AC-9:** Manifest declared per Layer 2 (BTS-239): the new `cmd_provider_resolve_ids` includes `# @manifest` block declaring purpose/input/output/depends-on/side-effect/failure-mode/contract. Drift-guard validates 100% on the new primitive.
- [ ] **AC-10:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel`) — 1993/1993 baseline maintained or improved.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_provider_resolve_ids` function + `provider-resolve-ids` subcommand dispatch in main case statement |
| `hub/tests/provider-resolve-ids.bats` | New: bats coverage for AC-1 through AC-7 using LINEAR_QUERY_OVERRIDE stubs |
| `.ccanvil/manifest-allowlist.txt` | Modified: register `cmd_provider_resolve_ids` for Layer 2 manifest enforcement |

## Dependencies

* **Requires:** existing `linear-query.sh list-teams|list-projects|list-states|list-labels` subcommands (already shipped, BTS-164/166/167 era).
* **Requires:** existing `LINEAR_QUERY_OVERRIDE` test pattern (already shipped, BTS-203 era).
* **Blocked by:** none.

## Out of Scope

* **Substrate-drift handling.** Heal-substrate must `/ccanvil-pull` before exercising new verbs, but that's a separate gap captured under BTS-316. This phase assumes substrate is current.
* `LINEAR_API_KEY` preflight + smoke-test verification. Heal-substrate must verify auth works before declaring success; separate sibling under BTS-316.
* **Compound** `provider-heal` verb that orchestrates all phases. This phase is just the ID-resolution primitive; the umbrella verb is a follow-up that composes this + the other heal phases.
* **Auto-discovery of team/project from existing partial config.** Operator must pass `--team` and `--project` explicitly. Auto-discovery is a future enhancement.
* **Microsoft365-toolbox-shape (zero config) heal.** This phase assumes `routing.idea = "linear"` is already set. Configuring routing from scratch is BTS-313 territory.

## Implementation Notes

* Mirror the existing `cmd_idea_setup` (`docs-check.sh:4364`) shape for arg parsing and config write — that's the closest precedent.
* Composition: 4 `linear-query.sh` calls (`list-teams`, `list-projects`, `list-states --team <name>`, label fallback chain), parsed via `jq` into the canonical block, deep-merged via `jq '. * $slice'` (same merge pattern proven on unifi-toolbox 2026-05-06).
* Test fixture pattern: stub `linear-query.sh` per the `artifact-write-concurrent-edit.bats:43-84` `write_lq_stub()` helper. Each subcommand returns a deterministic JSON shape parameterized by env vars. Use `LINEAR_QUERY_OVERRIDE` to inject the stub into `cmd_provider_resolve_ids`'s shell-out paths.
* `cmd_provider_resolve_ids` runs four subprocesses to `linear-query.sh`. That's deterministic substrate composition, NOT stochastic orchestration — operator-friction-mitigation per `feedback_deterministic_first` rule.
* Anchor file references for the test (per AC-7 BTS-265 file-ref validator): `.ccanvil/scripts/linear-query.sh`, `.claude/rules/provider-integration.md`.
