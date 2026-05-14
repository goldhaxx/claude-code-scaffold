# Implementation Plan: Split hub-managed CI checks into own workflow + heal across nodes

> Feature: bts-488-ccanvil-checks-workflow-split
> Work: linear:BTS-488
> Created: 1778728200
> Spec hash: abec394c
> Based on: docs/spec.md

## Objective

Land the operational fix for the CI fire drill: ship hub-owned `ccanvil-checks.yml` workflow + new `cmd_heal_ci_workflows` substrate verb so the lifecycle-docs draft-guard + security gates actually reach all 14 production downstream nodes, while preserving per-node `test:` customization.

## Sequence

### Step 1: Author hub's `ccanvil-checks.yml` template

* **Test:** Deferred to Step 2 (test-first for the yaml structure assertions).
* **Implement:** Write `.ccanvil/templates/github/workflows/ccanvil-checks.yml` per spec Implementation Notes — `name: ccanvil-checks`, `on.pull_request` with `types: [opened, synchronize, reopened, ready_for_review]`, `lifecycle-docs:` job with draft-guard, `security:` job.
* **Files:** `.ccanvil/templates/github/workflows/ccanvil-checks.yml` (new)
* **Verify:** `python3 -c 'import yaml,sys; yaml.safe_load(open(".ccanvil/templates/github/workflows/ccanvil-checks.yml"))'` exits 0.

### Step 2: Bats coverage for ccanvil-checks.yml (AC-1)

* **Test:** Create `hub/tests/ccanvil-checks-workflow.bats` with assertions: file exists, `name: ccanvil-checks` line, `ready_for_review` in types list, `draft == false` in lifecycle-docs `if:`, `Security audit` step present.
* **Implement:** N/A — file from Step 1 is the implementation; tests verify.
* **Files:** `hub/tests/ccanvil-checks-workflow.bats` (new)
* **Verify:** `bats hub/tests/ccanvil-checks-workflow.bats` passes 5+ tests.

### Step 3: Reduce hub's ci.yml + update existing bats (AC-2)

* **Test:** Add assertions to `ccanvil-checks-workflow.bats`: `ci.yml` does NOT contain `lifecycle-docs:` or `security:` job blocks; `test:` job survives. Update existing `hub/tests/ci-template-lifecycle-docs.bats` — those AC-1/AC-2 assertions now apply to ccanvil-checks.yml, so either delete that file (its assertions move to the new file) or repoint them. Cleanest: delete the BTS-482 file once equivalent assertions land on the new file.
* **Implement:** Edit `.ccanvil/templates/github/workflows/ci.yml` — remove `lifecycle-docs:` and `security:` blocks (lines \~25–53 of current). Keep only `test:` placeholder.
* **Files:** `.ccanvil/templates/github/workflows/ci.yml` (modified), `hub/tests/ci-template-lifecycle-docs.bats` (deleted), `hub/tests/ccanvil-checks-workflow.bats` (extended)
* **Verify:** Both new tests pass; old test file no longer present; `git grep "lifecycle-docs" .ccanvil/templates/github/workflows/ci.yml` returns nothing.

### Step 4: Register new template in INIT_GITHUB_TEMPLATES (AC-3)

* **Test:** Extend `ccanvil-checks-workflow.bats` with grep-assertion on the source script: `INIT_GITHUB_TEMPLATES` array contains the mapping `workflows/ccanvil-checks.yml:.github/workflows/ccanvil-checks.yml`.
* **Implement:** Edit `.ccanvil/scripts/ccanvil-sync.sh` line \~66 to add the new entry to `INIT_GITHUB_TEMPLATES`.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh` (modified), `hub/tests/ccanvil-checks-workflow.bats` (extended)
* **Verify:** `bats hub/tests/ccanvil-checks-workflow.bats` all green.

### Step 5: Implement `cmd_heal_ci_workflows` (AC-4)

* **Test:** Deferred to Step 6 (test-first per Step-6's red-then-green cycle).
* **Implement:** In `.ccanvil/scripts/ccanvil-sync.sh`, add `cmd_heal_ci_workflows` function with full `# @manifest` block (purpose, input flag `--dry-run`, output JSON-ish summary, depends-on jq/git/sha256sum, side-effects writes-target-files / writes-target-lockfiles / commits-on-node-main, failure-modes per AC-7/AC-8). Body iterates `.ccanvil/registry.json` entries; for each node skip-if-path-missing (mirror `cmd_broadcast`'s predicate at line \~3440); per-reachable-node: (a) compute `hub_hash = sha256(dist_root/.ccanvil/templates/github/workflows/ccanvil-checks.yml)`, (b) ensure `<node>/.github/workflows/` directory exists, (c) write file if `local_hash != hub_hash` else log SKIP-CLEAN, (d) jq-upsert lockfile entry, (e) when `<node>/.github/workflows/ci.yml` exists strip lifecycle-docs+security via awk pattern from spec Implementation Notes, (f) git -C <node> add . && git -C <node> commit -m "chore(ccanvil-checks): split hub-managed CI gates" (idempotent: skip commit if git status clean). Add `heal-ci-workflows)` to main case dispatch at line \~4625.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh` (modified, +\~100 lines)
* **Verify:** Step-6 bats suite passes.

### Step 6: Bats coverage for cmd_heal_ci_workflows (AC-4, AC-5, AC-6, AC-7, AC-8)

* **Test:** Create `hub/tests/heal-ci-workflows.bats`. Fixture helper: `setup_fake_node()` — mktemp + git init + write minimal `.ccanvil/registry.json` (pointing at fake node) + `.ccanvil/ccanvil.lock` (89-entry shape — copy a real one from one of the registered nodes for realism) + commit. Cases:
  * AC-4 happy: heal writes `ccanvil-checks.yml` to fake node, jq verifies lockfile entry exists with origin=hub, ci.yml is stripped, `git log -1 --format=%s` shows the chore message.
  * AC-5 idempotency: run heal twice, second run emits SKIP-CLEAN, `git rev-parse HEAD` matches between runs.
  * AC-6 preservation: seed `ci.yml` with customized `test:` (Install bats + bats tests/ steps); heal preserves both steps.
  * AC-7 no-ci.yml: fake node has no `ci.yml`; heal still writes ccanvil-checks.yml; no strip-phase error.
  * AC-8 isolation: seed a SECOND fake node with dirty tree (untracked file); heal logs the error and continues to a clean third node which gets healed.
* **Implement:** N/A — Step 5 is the implementation.
* **Files:** `hub/tests/heal-ci-workflows.bats` (new)
* **Verify:** `bats hub/tests/heal-ci-workflows.bats` 5+ tests pass.

### Step 7: Manifest registration (AC-9)

* **Test:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json | jq '.status'` — expect "ok".
* **Implement:** Add `.ccanvil/scripts/ccanvil-sync.sh:cmd_heal_ci_workflows` to `.ccanvil/manifest-allowlist.txt`. Verify the `# @manifest` block from Step 5 declares all required fields (purpose, input, output, depends-on, side-effect, failure-mode, contract, anchor).
* **Files:** `.ccanvil/manifest-allowlist.txt` (modified)
* **Verify:** manifest validate exits 0, status=ok, coverage 196/196.

### Step 8: Regression — full bats suite (AC-9)

* **Test:** None new — run the whole suite.
* **Implement:** N/A.
* **Files:** None.
* **Verify:** `bash .ccanvil/scripts/docs-check.sh test-suite-run --project-dir . --parallel --progress` returns 0; PASS count > 2298 (added \~10 new tests across new files).

## Risks

* **Risk: awk job-strip pattern brittleness.** If a node's `ci.yml` has `lifecycle-docs:` or `security:` jobs with unusual indentation (4 spaces instead of 2, or a leading tab) the strip pattern misfires. Mitigation: Step-6 fixture uses the exact shape from the hub template (2-space indent). For production nodes that may have customized indentation, document in the heal output a per-node "no jobs stripped" warning so the operator sees a manual-cleanup signal rather than silent failure.
* **Risk: lockfile JSON corruption from jq pipe.** Direct jq write to lockfile can leave it half-written on failure. Mitigation: write to temp file + `mv` (atomic on same fs) — same pattern used by existing lockfile mutations in [ccanvil-sync.sh](<http://ccanvil-sync.sh>) (`validate_json_or_die` helper appears in nearby code).
* **Risk: git -C commit failure on dirty tree** (AC-8 error path). Mitigation: explicit `git status --porcelain` check before commit; on dirty, log `SKIP-DIRTY` for that node and continue. NEVER force-commit.
* **Risk: Step-3 deletes ci-template-lifecycle-docs.bats — breaks BTS-482 PR retroactively.** No — that test file was added in BTS-482's merged PR; removing it in BTS-488 is fine because BTS-482's intent now lives on ccanvil-checks.yml's bats. Verified by Step-3 assertion equivalence.

## Definition of Done

- [ ] All AC-1 through AC-9 pass (AC-10 is manual post-merge operator step)
- [ ] All existing tests still pass (full hub bats suite ≥ 2308 / parallel)
- [ ] Module manifest: 196/196, drift 0
- [ ] No type errors (bash -n on [ccanvil-sync.sh](<http://ccanvil-sync.sh>) after Step 5)
- [ ] Code reviewed (run /review)
