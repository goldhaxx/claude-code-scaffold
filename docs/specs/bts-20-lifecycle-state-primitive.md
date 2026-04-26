# Feature: Unified lifecycle-state primitive

> Feature: bts-20-lifecycle-state-primitive
> Work: linear:BTS-20
> Created: 1777243739
> Status: Complete

## Summary

The implicit lifecycle state machine — Draft → Activated → Plan → Implement → PR → Land → Session-wrap — lives today in skill prose and a partially-overlapping pair of `docs-check.sh` commands (`validate` + `recommend`). Each consumer (skills `/recall`, `/pr`, `/stasis`, `/spec`) re-parses validate output independently. This ship introduces a unified `lifecycle-state` substrate primitive that emits a structured envelope `{state, legal_next_actions[], blockers[], suggestions[]}` consumed via one resolver call. The transition graph lives as data in `.ccanvil/templates/lifecycle-graph.json` instead of scattered prose.

**Single ship covering full migration:** primitive + transition-graph data + ALL state-parse consumers migrated (`/recall`, `/pr`, `/stasis`, `/spec`) + `/plan` pre-flight gate added + `cmd_recommend` refactored to delegate to the primitive. (Earlier draft scoped this as multi-session; expanded per substrate-mature judgment — drift-guards catch regressions across all migrations in one ship.)

## Job To Be Done

**When** any skill (or future scheduled-agent) needs to know the current lifecycle state and what the legal next actions are,
**I want to** call one substrate primitive that returns a complete machine-readable envelope,
**So that** state-parse logic stops being duplicated across skill prose, transitions are codified as data not narrative, and future skills inherit the gates by construction.

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` exits 0 on a clean repo and emits valid JSON matching `{state: string, legal_next_actions: [{action, command, reason}], blockers: [string], suggestions: [string]}`. Drift-guard greps the cmd dispatcher and runs the command on a fixture repo.
- [ ] **AC-2:** `.ccanvil/templates/lifecycle-graph.json` exists, parses as JSON, and contains keys `states[]` and `edges[]`. Each state has `{id, description}`. Each edge has `{from, to, action, guard?, command?}`. Drift-guard validates schema with `jq -e`.
- [ ] **AC-3:** The graph covers (at minimum) the canonical lifecycle states: `no-active-spec`, `spec-drafted`, `spec-activated`, `plan-written`, `implementing`, `pr-open`, `pr-merged`, `session-wrap`. Drift-guard `jq -e '[.states[].id] | contains(["no-active-spec","spec-activated","plan-written"])'`.
- [ ] **AC-4:** Given the current repo (no spec, no plan, session-stasis present, post-compact marker fresh), `lifecycle-state` returns `state == "session-wrap"` with at least one `legal_next_actions` entry whose `action` references `/radar` or `activate`. Drift-guard runs against a constructed fixture.
- [ ] **AC-5:** Given an active spec on a feature branch with no plan, `lifecycle-state` returns `state == "spec-activated"` and `legal_next_actions[]` includes `/plan`. Drift-guard runs against a fixture.
- [ ] **AC-6:** When validate returns `stale-plan` or `mismatched`, `lifecycle-state` surfaces it under `blockers[]` with the validate detail strings. `legal_next_actions[]` is empty (or only contains the recovery action). Drift-guard fixture.
- [ ] **AC-7:** `.claude/skills/recall/SKILL.md` consumes `lifecycle-state` (single call) instead of separate `validate` + `recommend` calls. Drift-guard greps for `lifecycle-state` and asserts `validate` + `recommend` are NOT also invoked side-by-side at recall's top.
- [ ] **AC-8:** Recall's briefing surfaces the new envelope: shows current `state`, lists `legal_next_actions[]` (titles + commands), and includes blockers when present. Drift-guard greps recall prose for the literal phrase `legal next actions`.
- [ ] **AC-9:** Edge: when `lifecycle-state` is invoked outside a git repo or in a non-ccanvil project, exit code is 2 with a JSON error envelope `{error: "...", state: "uninitialized"}`. Drift-guard runs against `/tmp` fixture.
- [ ] **AC-10:** Tests land in `hub/tests/lifecycle-state.bats` with ≥9 cases (one per AC-1..AC-9) plus drift-guards for the recall migration in `hub/tests/recall-skill.bats` (or new `recall-lifecycle-migration.bats` if no recall test file exists).
- [ ] **AC-11:** `/pr` skill (`.claude/commands/pr.md`) consumes `lifecycle-state` instead of separate `validate` call. `pr-guard` continues to run separately for behind-base check (different concern). Drift-guard greps for `lifecycle-state` and asserts no separate `docs-check.sh validate` call.
- [ ] **AC-12:** `/stasis` skill consumes `lifecycle-state` for pre-flight halt-check (replaces the separate `validate` call at step 1). On `state == "blocked"`, halt and surface the envelope's `blockers[]`. Drift-guard.
- [ ] **AC-13:** `/spec` skill consumes `lifecycle-state` for the "active spec exists?" check (step 4). Refuses spec creation when state is `spec-activated`, `plan-written`, or `implementing` — operator must `/pr` and `/land` (or revert) first. Drift-guard.
- [ ] **AC-14:** `/plan` skill (`.claude/commands/plan.md`) gains an explicit pre-flight: refuses to plan when `lifecycle-state.state` is not `spec-activated` or `plan-written`. Today /plan reads `docs/spec.md` silently and fails late on missing content; the new gate fails fast. Drift-guard.
- [ ] **AC-15:** `cmd_recommend` refactored to delegate state derivation to `cmd_lifecycle_state`. New shape: cmd_recommend emits `{next_action, reason}` from the first entry of the envelope's `legal_next_actions[]`. Output schema unchanged for existing callers. Drift-guard validates the existing `recommend` output JSON shape against the new implementation.
- [ ] **AC-16:** All 1594 baseline tests still pass post-refactor; no regression in `recommend-freshness.bats`, `feature-lifecycle.bats`, `auto-transition-emit.bats`, or any other lifecycle-touching suite.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_lifecycle_state` function + dispatcher entry |
| `.ccanvil/templates/lifecycle-graph.json` | New transition-graph data file |
| `.claude/skills/recall/SKILL.md` | Replace separate validate + recommend with single `lifecycle-state` consumption |
| `hub/tests/lifecycle-state.bats` | New — primitive shape + transition-graph + AC fixtures |
| `hub/tests/recall-skill.bats` (or new file) | Drift-guards for recall migration |
| `.ccanvil/guide/command-reference.md` | Document `lifecycle-state` subcommand |
| `.ccanvil/guide/session-management.md` | Reference the unified primitive in skill orchestration prose |

## Dependencies

- **Requires:** Existing `cmd_validate`, `cmd_recommend`, `cmd_status` (already shipped). `last-compact-ts` marker (BTS-113). `cmd_idea_count` (existing).
- **Blocked by:** None.

## Out of Scope

- **Migrating `/plan` to consume the envelope's state.** /plan reads `status` for `spec.content_hash` (a metadata fetch, not a state-parse). Lifecycle-state doesn't surface content hashes. /plan instead gains a pre-flight gate (AC-14) that uses lifecycle-state to refuse planning outside legal states; its hash read stays unchanged.
- **Activate dirty-tree pre-flight gate.** `cmd_activate` already enforces this (`docs-check.sh` lines 911-931 — exits with "ERROR: worktree has uncommitted changes" if non-spec files are dirty). Pre-flight gap closed before this ship.
- **`/idea triage` just-captured warning.** Separate ideas-substrate concern, not state-machine.
- **SSOT-Linear (specs/plans/stasis stored in Linear ticket bodies).** Future major effort — own session. Two history-loss tensions to resolve in its spec session: (a) git-tracked spec evolution; (b) lifecycle docs backup/access regime. See memory `project_ssot_history_tensions.md`.
- **Always-on orchestrator service.** Original BTS-20 scope; deferred (launchd `claude -p` pattern is sufficient).
- **Multi-agent / multi-terminal coordination.** Original BTS-20 scope; not at single-user scale.
- **Cross-node lifecycle coordination.** Lives in `ccanvil-sync.sh`.
- **`pr-open` / `pr-merged` state detection.** In the graph but not emitted (would require a `gh` subprocess). `/pr` and `/land` aren't gated on these states today; deferred.
- **Refactoring `cmd_validate` internals.** Validate stays as the alignment checker that lifecycle-state composes. Refactoring it would multiply blast radius beyond this ship.

## Implementation Notes

- The shape `{state, legal_next_actions[], blockers[], suggestions[]}` is richer than `recommend`'s `{next_action, reason}` — recommend is a single-action emitter; lifecycle-state is the full state envelope. Recommend stays callable; can later be reimplemented as a thin wrapper, but not in this ship.
- The transition-graph JSON shape follows the substrate-data convention (see `.ccanvil/templates/scaffold.json` for the canonical pattern: `{states: [...], edges: [...]}`).
- For AC-4/AC-5/AC-6 fixtures: use the `BATS_TMPDIR`-based fixture pattern from `hub/tests/evidence-scan-session.bats` (constructs a temporary docs/ tree, invokes the cmd, asserts the JSON shape).
- `/recall` migration shape: replace steps 0a + 0b (currently two separate cmd calls) with one `lifecycle-state` call. The briefing render then walks `legal_next_actions[]` and `blockers[]` from the envelope. Keep all other recall data-gathering steps unchanged — this ship is scoped to the state-parse delta, not a recall rewrite.
- Drift-guard pattern follows BTS-200 / BTS-201 — bats tests grep skill prose for required structural elements + execute the substrate primitive against fixtures.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
