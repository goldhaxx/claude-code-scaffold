# Implementation Plan: /spec dispatches via artifact-write on Linear-routed nodes

> Feature: bts-213-spec-skill-linear-routing
> Work: linear:BTS-213
> Created: 1777268075
> Spec hash: 5594c273
> Based on: docs/spec.md

## Objective

Make `/spec` and `cmd_activate` route-aware so that on Linear-routed nodes
the spec Document exists in Linear post-activation, eliminating the silent
`state: no-active-spec` inconsistency that BTS-204 left behind.

## Sequence

### Step 1: AC-2/AC-5 drift-guards — pure-local node fires no curl

- **Test:** New `@test`s in `hub/tests/ssot-linear.bats` (or new
  `hub/tests/spec-skill-linear-routing.bats`):
  1. Fixture builds a tmp ccanvil project with NO `routing.spec` set.
  2. Stub `linear-query.sh` to fail-fast when invoked
     (`LINEAR_STUB_FAIL_LOUD=1`) so any accidental network call surfaces.
  3. Call `cmd_artifact_write --kind spec --feature bts-213-x` after
     creating `docs/specs/bts-213-x.md` (driven through the existing
     local path).
  4. Assert: stub capture file is empty (no curl invocation).
- **Implement:** No production code yet — write the drift-guard so the
  later changes can't regress the local path.
- **Files:** `hub/tests/ssot-linear.bats` (extend with `routing.spec`
  scenarios) or new `hub/tests/spec-skill-linear-routing.bats`.
- **Verify:** `bash .ccanvil/scripts/bats-report.sh -f 'BTS-213'` — new
  test passes against current substrate.

### Step 2: AC-1 drift-guard — Linear-routed dispatch invokes save-document

- **Test:** Fixture builds a tmp project with
  `.claude/ccanvil.local.json` carrying `{integrations:{routing:{spec:"linear"},providers:{linear:{project_id:"<uuid>",team_id:"<uuid>"}}}}`.
  Stub `linear-query.sh` (or curl) to capture invocation args; respond
  with deterministic JSON.
  - Pre-arrange: `docs/specs/bts-213-x.md` already on disk (simulating
    just-completed local archive write).
  - Drive: `cat docs/specs/bts-213-x.md | bash docs-check.sh artifact-write --kind spec --feature bts-213-x`.
  - Assert: capture file contains `documentCreate` (first call) with
    correct `parent.issueId`, `id` (deterministic UUID), `title`.
- **Implement:** No production code; this exercises BTS-204's existing
  substrate to lock the contract before the skill prose changes.
- **Files:** Same test file as Step 1.
- **Verify:** Test passes — confirms the substrate already does the
  right thing when invoked.

### Step 3: AC-7 idempotency drift-guard — second dispatch takes update path

- **Test:** Same fixture as Step 2. Stub responds:
  - First call (resolve `document-updated-at` 404 → not found) →
    `documentCreate` succeeds, returns `{id, updatedAt}`.
  - Second call (`document-updated-at` returns updatedAt) →
    `documentUpdate` succeeds, returns `{updatedAt}`.
  - Assert: second dispatch hits update path (request body contains
    `documentUpdate`, not `documentCreate`).
- **Implement:** None.
- **Files:** Same test file.
- **Verify:** Test passes.

### Step 4: AC-1 production change — `/spec` skill prose dispatches when routed

- **Test:** Skill prose change isn't directly bats-testable, but Step 5
  exercises the end-to-end flow.
- **Implement:** Edit `.claude/commands/spec.md` and `.claude/skills/spec/SKILL.md`
  step 8 to add this block AFTER `stamp-spec`:
  ```bash
  if [[ "$(bash .ccanvil/scripts/docs-check.sh _lifecycle_route spec 2>/dev/null || echo local)" == "linear" ]]; then
    if ! bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature "$feature_id" < "docs/specs/$feature_id.md"; then
      echo "WARN: /spec wrote local archive but Linear dispatch failed. Retry: bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature $feature_id < docs/specs/$feature_id.md" >&2
      exit 1
    fi
  fi
  ```
  Note: `_lifecycle_route` is internal — expose it via a new public
  subcommand `route-of <kind>` so the skill doesn't reach into private
  helpers. (Sub-step 4a.)
- **Files:** `.claude/commands/spec.md`, `.claude/skills/spec/SKILL.md`,
  `.ccanvil/scripts/docs-check.sh`.
- **Verify:** Manual read; AC-2 drift-guard from Step 1 still passes.

### Step 4a: Add `route-of <kind>` public subcommand

- **Test:** `@test` asserts:
  - `docs-check.sh route-of spec` returns `local` on a project with no
    routing config.
  - With `routing.spec=linear`, returns `linear`.
  - Unknown kind returns exit 2 with `Usage:`.
- **Implement:** Add `route-of)` case to dispatcher; thin wrapper around
  `_lifecycle_route`.
- **Files:** `.ccanvil/scripts/docs-check.sh`.
- **Verify:** Bats green.

### Step 5: AC-4 end-to-end — post-activate `lifecycle-state == spec-activated` on Linear-routed

- **Test:** Drift-guard fixture:
  1. Build tmp project with `routing.spec=linear` + git-init.
  2. Write spec to `docs/specs/<id>.md`.
  3. Stub `linear-query.sh` so `document-updated-at` returns 200 (doc
     exists) for the deterministic UUID derived from `<feat>`.
  4. Run `cmd_activate <feat>` (from a test harness that calls into
     the script directly).
  5. Run `cmd_lifecycle_state --project-dir .`; assert
     `.state == "spec-activated"`.
- **Implement:** Modify `cmd_activate` (after the existing `git commit`
  for the activate commit) — when `_lifecycle_route spec == linear`,
  dispatch `cmd_artifact_write --kind spec --feature "$feature_id"` with
  the In-Progress-stamped content read from `docs/spec.md`.
- **Files:** `.ccanvil/scripts/docs-check.sh` (`cmd_activate` body),
  test file.
- **Verify:** New test passes; existing activate tests
  (`activate-push-guard.bats`) still pass.

### Step 6: AC-6 error-path drift-guard — local archive survives Linear dispatch failure

- **Test:** Fixture: `routing.spec=linear`, stub
  `linear-query.sh save-document` exit 3.
  - Drive: `cat docs/specs/<id>.md | docs-check.sh artifact-write --kind spec --feature <id>`.
  - Assert: exit non-zero AND `docs/specs/<id>.md` still on disk
    unchanged.
- **Implement:** No production change required — `cmd_artifact_write`
  already returns the upstream exit code; local archive isn't touched
  by the dispatch path. This test locks that invariant.
- **Files:** Test file.
- **Verify:** Test passes.

### Step 7: Update command-reference and surface in `/plan` notes

- **Test:** Doc-coverage check (existing
  `bats hub/tests/docs-coverage.bats` style) — confirm command-reference
  carries the `route-of` entry.
- **Implement:** Add `route-of <kind>` row to
  `.ccanvil/guide/command-reference.md`. Add a one-line note in
  `.claude/commands/spec.md` step 8 footer linking to AC-6 retry recipe.
- **Files:** `.ccanvil/guide/command-reference.md`,
  `.claude/commands/spec.md`.
- **Verify:** `bats hub/tests/docs-coverage.bats` passes (if such a
  test exists; otherwise smoke-grep).

### Step 8: Live-validation gate — single Linear call against api.linear.app

- **Test:** Manual live invocation only (per
  `.claude/rules/tdd.md#live-api-validation-gate`):
  ```bash
  export LINEAR_API_KEY=$(cat .env | grep LINEAR_API_KEY | cut -d= -f2)
  echo '# test spec body' | bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature BTS-213
  bash .ccanvil/scripts/linear-query.sh trash-document <doc-id>
  ```
  Confirm: `documentCreate` succeeds with deterministic UUID, then
  cleanup trashes it. This step exists because the `cmd_activate`
  dispatch path is new and the BTS-204 ship verified
  `cmd_artifact_write` for stasis but only stub-tested for spec.
- **Implement:** None — this is a verification gate.
- **Files:** None modified.
- **Verify:** Live call returns success; document trashed.

## Risks

- **Activate-flow regression on local nodes.** Mitigation: AC-2 drift-guard
  asserts curl never fires when `routing.spec` is unset; existing
  `activate-push-guard.bats` exercises the local-route activate flow.
- **Skill prose drift.** Both `.claude/commands/spec.md` AND
  `.claude/skills/spec/SKILL.md` carry the step. Mitigation: edit both in
  the same commit; grep for divergence in `/review`.
- **Race between local archive write and Linear dispatch.** AC-6 documents
  the retry recipe; not a true race since both writes are sequential.
- **Stub miss → live API contract gap.** Mitigation: Step 8 live gate.

## Definition of Done

- [ ] All 7 acceptance criteria from spec pass
- [ ] All 1681 existing tests still pass; new drift-guards added
- [ ] No type errors
- [ ] Live-API call against api.linear.app confirms artifact-write spec path
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
