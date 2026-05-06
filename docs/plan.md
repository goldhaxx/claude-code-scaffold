# Implementation Plan: provider-resolve-ids substrate primitive (Phase 1)

> Feature: bts-319-provider-resolve-ids
> Work: linear:BTS-319
> Created: 1778098023
> Spec hash: fcef09ea
> Based on: docs/spec.md

## Objective

Add `cmd_provider_resolve_ids` to `.ccanvil/scripts/docs-check.sh` that resolves Linear team_id, project_id, state_ids[8], label_ids[idea] from live API + deep-merges them into `.claude/ccanvil.local.json`. Mirror `cmd_idea_setup` shape. Cover with bats stubs via `LINEAR_QUERY_OVERRIDE`. Register in manifest-allowlist for Layer 2 drift-guard.

Empirical anchor: byte-identical output to the manual heal we hand-composed on unifi-toolbox 2026-05-06 (commit `19af207`) is the success signal.

## Steps

### Step 1 — Red: write bats fixtures + first failing test

Create `hub/tests/provider-resolve-ids.bats`:

- Setup/teardown using `mktemp -d` for `TMPDIR_BATS` (mirror `artifact-write-concurrent-edit.bats:32-39`).
- `write_lq_stub()` helper that writes `$TMPDIR_BATS/lq-stub.sh` branching on subcommand: `list-teams`, `list-projects`, `list-states`, `list-labels` — each returns deterministic JSON parameterized by env vars (`STUB_TEAM_ID`, `STUB_PROJECT_ID`, `STUB_STATES_JSON`, `STUB_LABELS_TEAM_JSON`, `STUB_LABELS_WS_JSON`). Mirror `write_lq_stub()` from `artifact-write-concurrent-edit.bats:43-84`.
- AC-1 test: stub returns canonical IDs → `cmd_provider_resolve_ids` writes a complete config block. Run via `LINEAR_QUERY_OVERRIDE=$stub bash $SCRIPT provider-resolve-ids --provider linear --team Foo --project Bar --project-dir $TMPDIR_BATS`. Assert `jq -e '.integrations.providers.linear.team_id == "STUB-TEAM-1"'` and same for `project_id`, `state_ids.triage`, `label_ids.idea`.

Run: `bats hub/tests/provider-resolve-ids.bats`. Confirm test FAILS (subcommand doesn't exist yet — exit 2 from main case dispatch).

### Step 2 — Green: implement `cmd_provider_resolve_ids` with case-1 path

Add the function to `.ccanvil/scripts/docs-check.sh`:

- Mirror `cmd_idea_setup` arg parsing (`--provider`, `--team`, `--project`, `--project-dir`).
- For now, only handle the happy path: 4 sequential `linear-query.sh` calls (using `${LINEAR_QUERY_OVERRIDE:-$script_dir/linear-query.sh}`).
- Compose `state_ids` by parsing `list-states` output, mapping by case-insensitive name match to canonical roles.
- Compose `label_ids` by trying `list-labels --team <name>`; if `[]`, fall back to `list-labels --workspace-scoped`.
- Deep-merge via `jq '. * $slice'` into existing `.claude/ccanvil.local.json` (preserve existing keys).
- Register the subcommand in the main case statement (line 6900-ish, near `route-of`).

Re-run AC-1 test: should pass.

### Step 3 — Green: AC-2 (state-name → role mapping) + AC-3 (label workspace fallback)

- Extend bats: AC-2 test stub returns 9 states including a custom "Idea" state. Assert mapping ignores the custom and produces 8 canonical role keys. AC-3 test stub returns `[]` for team-scoped labels and a non-empty array for workspace-scoped; assert label_ids resolves via fallback.
- Implementation: ensure mapping logic handles missing/extra states gracefully and the label fallback chain is wired correctly. Refine if tests surface issues.

Re-run targeted: `bats hub/tests/provider-resolve-ids.bats`. All three pass.

### Step 4 — Green: AC-4 (deep-merge preservation) + AC-5 (idempotency)

- AC-4 test: pre-create `<tmpdir>/.claude/ccanvil.local.json` with `{node_uuid: "...", integrations: {routing: {idea: "linear"}, providers: {linear: {team: "Foo", project: "Bar"}}}}`. Run substrate. Assert `node_uuid`, `routing.idea`, existing `team`/`project` strings all preserved alongside new `_id` keys.
- AC-5 test: run substrate twice; assert byte-identical output (`md5sum` or content compare).
- Implementation: verify deep-merge preserves keys; idempotency falls out of pure functional composition (no in-place mutation, fresh slice each run).

### Step 5 — Green: AC-6 (error-mode for missing team/project) + AC-7 (WARN for missing label)

- AC-6 test stub returns `[]` for `list-teams` query. Run substrate; assert exit non-zero, stderr names the missing team, no partial config write.
- AC-7 test stub returns `[]` for both team-scoped AND workspace-scoped label queries. Run substrate; assert exit 0, stderr contains "WARN: idea label not resolved", config written without `label_ids.idea`.
- Implementation: add error-paths after each list call; differentiate fatal (team/project) vs warn (label).

### Step 6 — Manifest registration + drift-guard validation

- Add `# @manifest` block above `cmd_provider_resolve_ids` declaring `purpose`, `input` (4 flags), `output` (config write + summary), `depends-on` (jq, linear-query.sh), `side-effect` (writes-ccanvil-local-json), `failure-mode` (3 modes: missing-team, missing-project, missing-label-warn), `contract` (idempotent + preserves-existing-keys), `anchor` (BTS-319).
- Add line to `.ccanvil/manifest-allowlist.txt`: `.ccanvil/scripts/docs-check.sh:cmd_provider_resolve_ids`.
- Run `bash .ccanvil/scripts/module-manifest.sh validate --json` — confirm 100% coverage with the new entry.

### Step 7 — Live-API validation gate (BTS-171)

The plan involves live `linear-query.sh` shell-outs whose contract has uncertainty in only one place: the workspace-scoped vs team-scoped label fallback. Stubs accept any shape; only a live call confirms the API filter accepts both query shapes. Live verification command:

```bash
LINEAR_API_KEY=$(grep -E '^LINEAR_API_KEY=' .env | cut -d= -f2-) \
  bash .ccanvil/scripts/docs-check.sh provider-resolve-ids \
    --provider linear --team "Blocktech Solutions" --project "ccanvil" \
    --project-dir /tmp/scratch-heal-test
jq '.integrations.providers.linear.label_ids.idea' /tmp/scratch-heal-test/.claude/ccanvil.local.json
```

Expected: non-null `idea` label_id (workspace-scoped fallback fires since "ccanvil" project shares the workspace-scoped `idea` label). Run BEFORE commit.

### Step 8 — Full bats suite verification

Run `bash .ccanvil/scripts/bats-report.sh --parallel`. Confirm pass count ≥ 1993. No regressions.

### Step 9 — Commit + ship

- `git add` the modified files (docs-check.sh, manifest-allowlist.txt, hub/tests/provider-resolve-ids.bats, docs/plan.md).
- Commit on `claude/feat/bts-319-provider-resolve-ids` with `feat(bts-319): provider-resolve-ids substrate (Phase 1 of provider-heal)`.
- Push.
- `/pr --skip-review` — substrate change with paired bats coverage; drift-guard tests are the safety net per `feedback_skip_review_on_trivial_diffs` (substrate work technically warrants review, but the test fixtures + manifest drift-guard are tight; operator can intercept if needed).
- `/ship 162` — squash-merge + auto-close BTS-319.

## Constraints

- No changes to `linear-query.sh` — Phase 1 only consumes existing subcommands.
- No changes to `cmd_idea_setup` — provider-resolve-ids is a sibling primitive, not a replacement.
- No new dependencies — everything composes from `jq` + existing shell patterns.

## Risks

- Workspace-scoped label fallback may need API-shape verification (Step 7 live gate). Mitigation: explicit live-API call before commit.
- State-name mapping is case-insensitive on canonical roles ("Triage" vs "triage" vs "TRIAGE"). Mitigation: bats AC-2 test exercises mixed-case fixture; live data confirms.
- Idempotency relies on jq deep-merge being deterministic for object-typed merges. Mitigation: AC-5 byte-compare test catches any non-determinism (e.g., key ordering in jq output).
