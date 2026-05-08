# Feature: Modular provider connectivity — operator-config layer + activation switch

> Feature: bts-316-modular-provider-connectivity
> Work: linear:BTS-316
> Created: 1778272987
> Subject: Modular provider connectivity — operator-config layer + activation
> Status: In Progress

## Summary

Provider activation today is a manual sequence the operator pieces together: configure auth (BTS-331), run `provider-heal` to resolve IDs (BTS-326), then hand-edit `.claude/ccanvil.local.json` to flip routing keys. There is no init-time path and no single command that activates a provider end-to-end. This forces every new node (most recently `tour-scheduler`) to start local and stay there, and turns "rotate keys" into a per-node ritual.

This feature lands the **operator-config layer** (operator-wide defaults at `~/.ccanvil/operator.json`, hub-default + node-override semantics from BTS-380 Q3) and the **`provider-activate` switch** that composes existing primitives into one operator-facing verb. It works at init time (via `/ccanvil-init` flags or interactive prompt) AND post-init (operator runs the verb against an existing local-routed node to flip it). Closes BTS-313 (init-time activation) and BTS-314 (heal flow for drifted nodes) as folded scope; bolts onto the BTS-326 provider-heal umbrella.

## Job To Be Done

**When** I initialize a new project (e.g. `tour-scheduler`) or decide an existing local-routed node should start using Linear,
**I want to** flip provider routing for that node end-to-end with one command (or one prompt at init), pulling default team/credentials from operator-wide config so I don't re-enter them per-node,
**So that** activation is a deterministic switch and key rotation is a single edit to `~/.ccanvil/operator.json` rather than a per-node visit.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Operator-config layer

- [ ] **AC-1:** `bash docs-check.sh operator-config init --provider linear --team "<name>"` writes `~/.ccanvil/operator.json` with `{providers:{linear:{team:"<name>"}}, default_routes:{spec:"linear", plan:"linear", stasis:"linear", idea:"linear"}}`. Idempotent — running twice produces no diff.
- [ ] **AC-2:** `bash docs-check.sh operator-config get providers.linear.team` reads the dotted key from `~/.ccanvil/operator.json` and prints to stdout. Returns exit 0 + empty string when key absent (not an error).
- [ ] **AC-3:** `bash docs-check.sh operator-config set <dotted.key> <value>` updates the key in `~/.ccanvil/operator.json` (jq deep-set). Creates the file if absent. Writes via temp+mv (atomic).
- [ ] **AC-4:** `bash docs-check.sh operator-config show` prints the merged operator config as pretty-printed JSON. Returns `{}` (not an error) when the file does not exist.
- [ ] **AC-5:** `merge_config` in `operations.sh` reads three tiers in order — operator (`~/.ccanvil/operator.json`) → hub (`.claude/ccanvil.json`) → node (`.claude/ccanvil.local.json`) — and returns the deep-merged result. Node wins on conflict; hub overrides operator; operator provides defaults. Works when any tier is missing (no error).
- [ ] **AC-6:** When `~/.ccanvil/operator.json` exists but contains invalid JSON, `merge_config` exits 1 with a stderr error naming the file. Mirror of existing hub/node behavior.

### provider-activate switch

- [ ] **AC-7:** `bash docs-check.sh provider-activate --provider linear --team "<name>" --project "<name>" --routes spec,plan,stasis,idea --project-dir <path>` resolves IDs via the existing `provider-heal` umbrella (auth → drift gate → ID resolution), then writes `integrations.routing.{spec,plan,stasis,idea}=linear` into `<path>/.claude/ccanvil.local.json`. Exit 0 on success.
- [ ] **AC-8:** When `--team` is omitted but `~/.ccanvil/operator.json` carries `providers.linear.team`, `provider-activate` falls back to the operator-config value. Same for `--routes` (defaults to `default_routes` from operator-config; hard default `spec,plan,stasis,idea` when neither set).
- [ ] **AC-9:** `provider-activate` is idempotent — running twice on the same node produces zero diff in `.claude/ccanvil.local.json` (verified via `git diff --quiet` after second run).
- [ ] **AC-10:** `--routes spec,plan` activates only the named routes; stasis and idea remain on the prior provider (or `local` default). Partial activation works without touching unmentioned routes.
- [ ] **AC-11:** When any provider-heal phase fails (auth / drift / resolve), `provider-activate` halts with non-zero exit, surfaces the phase failure on stderr, and writes NOTHING to `.claude/ccanvil.local.json`. No half-flipped state.
- [ ] **AC-12:** `provider-activate --json` emits a structured envelope `{status, provider, team, project, routes, ids:{team_id, project_id, state_count, label_count}, viewer_id}` on success, or `{status:"<phase>-failed", error}` on failure.

### route-of paper-cut fix (BTS-276 finding 4)

- [ ] **AC-13:** `bash docs-check.sh route-of idea --project-dir <path>` returns the configured idea route (e.g. `linear` or `local`); no longer errors with "Usage:". Same for `route-of backlog`.

### /ccanvil-init integration

- [ ] **AC-14:** `/ccanvil-init` skill prose accepts `--provider linear --team "<name>" --project "<name>" --routes <list>` flags. When provider flags are present, init runs `provider-activate` after registration (Step 10) and surfaces the result.
- [ ] **AC-15:** When `--provider` is absent AND stdin is a TTY, `/ccanvil-init` prompts: "Activate a provider for this node? [linear/local] (default: local)". On `linear`, prompts for team (default from operator-config), project, and routes (default from operator-config). On `local` or empty, skips activation.
- [ ] **AC-16:** When `--provider` is absent AND stdin is NOT a TTY (CI / agent without flags), `/ccanvil-init` defaults to local without prompting. Surfaces a one-line message: "to activate a provider later: bash docs-check.sh provider-activate --provider linear --team <name> --project <name>".

### Tests + manifests

- [ ] **AC-17:** New bats fixture `hub/tests/operator-config.bats` — covers init/get/set/show/merge with operator+hub+node tiers, missing-tier cases, invalid-JSON case. Uses `HOME` override pattern to avoid touching the real `~/.ccanvil/`.
- [ ] **AC-18:** New bats fixture `hub/tests/provider-activate.bats` — covers happy path, idempotency, partial-routes, operator-config team fallback, all three phase-failure modes (using `LINEAR_QUERY_OVERRIDE` stub). Stubs Linear API calls; never touches live API in tests.
- [ ] **AC-19:** New bats fixture `hub/tests/route-of-idea-backlog.bats` — covers route-of with idea + backlog kinds across linear/local routing.
- [ ] **AC-20:** All new `cmd_*` functions carry `@manifest` blocks (purpose, input, output, depends-on, side-effect, failure-mode, contract, anchor). Added to `.ccanvil/manifest-allowlist.txt`. `bash .ccanvil/scripts/module-manifest.sh validate` exits 0 with `drift: 0`.
- [ ] **AC-21:** Full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel`. Test count grows from 2035 to 2035 + N (where N is the count from AC-17 + AC-18 + AC-19).

### End-to-end dogfood

- [ ] **AC-22:** Real activation against `~/projects/tour-scheduler` succeeds: `bash ~/projects/ccanvil/.ccanvil/scripts/docs-check.sh provider-activate --provider linear --team "Blocktech Solutions" --project "tour-scheduler" --project-dir ~/projects/tour-scheduler` flips all four routes; `route-of {spec,plan,stasis,idea}` returns `linear` for each. Verified before merge. (No live-API contract risk — composing already-verified primitives.)

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/operations.sh` | Modify `merge_config()` to 3-tier (operator → hub → node); requires reading from `$HOME/.ccanvil/operator.json` |
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_operator_config_*` (init/get/set/show), `cmd_provider_activate`. Modify: `cmd_route_of` allowlist (+idea, +backlog) |
| `global-commands/ccanvil-init.md` | Skill prose: add provider flags + interactive prompt branch (TTY-aware) |
| `hub/tests/operator-config.bats` | New |
| `hub/tests/provider-activate.bats` | New |
| `hub/tests/route-of-idea-backlog.bats` | New |
| `.ccanvil/manifest-allowlist.txt` | Add new cmd_* surfaces |
| `.claude/ccanvil.json` | Possibly: declare schema-version for operator-config tier (TBD during implementation) |

## Dependencies

- **Requires:** BTS-326 (`provider-heal` umbrella shipped), BTS-331 (LINEAR_API_KEY auth chain), BTS-319 (`provider-resolve-ids`), `linear-query.sh` http substrate.
- **Blocked by:** none.

## Out of Scope

- Agent army / role definitions (BTS-380 component 2 — stays parked).
- Overnight autonomy / Ralph loops (BTS-380 component 3 — stays parked).
- Interrupt boundary semantics (BTS-380 Q1 — stays parked).
- Stuck-state recovery defaults (BTS-380 Q4 — stays parked).
- Legacy-data-scan pre-flip (BTS-337 — captured as follow-up; bolts onto `provider-activate` as an optional `--legacy-data-scan` flag in a later PR).
- `work.resolve` rejecting bare `BTS-N` on local-provider (BTS-276 finding 3 — separate paper-cut PR).
- `ticket.transition` local-provider error (BTS-276 finding 2 — separate paper-cut PR; depends on local-provider transition semantics design).
- Multi-provider per node (e.g. specs in Linear + ideas in Notion). Single-provider-per-node enforced by current substrate; multi-provider is a future spec.

## Implementation Notes

- **Three-tier merge order:** operator → hub → node. Earlier tiers are defaults; later tiers override. Mirrors how `merge_config` already handles 2 tiers — extend the existing jq `.[0] * .[1] * .[2]` reduce.
- **Operator-config home:** `$HOME/.ccanvil/operator.json`. Outside the workspace, so substrate that reads it must be in scripts that explicitly handle the path (no `guard-workspace.sh` issues — the script invocation reads HOME directly, no path arg crossing the guard).
- **`provider-activate` composition:** call `cmd_provider_heal` for auth+drift+resolve, then a separate `_set_routes` helper that jq-edits `integrations.routing.{spec,plan,stasis,idea}` in `.claude/ccanvil.local.json`. Atomic write via temp+mv.
- **TTY detection in init prose:** the skill prose instructs the agent to test `[[ -t 0 ]]` before prompting. Agents (no TTY) skip the prompt; humans (TTY) get the prompt.
- **Test-stubbing pattern:** existing `LINEAR_QUERY_OVERRIDE` (BTS-203) covers Linear API; for `~/.ccanvil/operator.json` use `HOME` override (export `HOME="$BATS_TMPDIR/fake-home"` per test). No new test substrate needed.
- **Manifest discipline:** every new `cmd_*` carries the full `@manifest` block. Failure-modes must enumerate auth-failed, drift-detected, resolve-failed, missing-flag, invalid-json. New surfaces added to `.ccanvil/manifest-allowlist.txt` BEFORE running validate.
- **No breaking changes:** existing nodes that don't have `~/.ccanvil/operator.json` continue working unchanged — `merge_config` returns `{}` for the missing tier.
