# Implementation Plan: CI fire drill — lifecycle-docs design bug fix + canonical example-data SSOT

> Feature: bts-482-lifecycle-docs-canonical-ssot
> Work: linear:BTS-482
> Created: 1778706800
> Spec hash: 6bf13efb
> Based on: docs/spec.md

## Objective

Stop the perpetual CI failure email firehose across 14 downstream nodes by (a) fixing the lifecycle-docs CI job's design bug so it doesn't fire on draft (in-flight) PRs, and (b) shipping a canonical example-data SSOT that documents the reserved-namespace fixture conventions `security-audit.sh` already auto-allowlists.

## Sequence

### Step 1: Author canonical SSOT JSON file

* **Test:** None yet — pure data foundation. Tested in Step 2.
* **Implement:** Create `.ccanvil/fixtures/canonical-example-data.json` with version, emails (≥3 in `@example.{com,org,net}`), names, user_ids, domains, notes.
* **Files:** `.ccanvil/fixtures/canonical-example-data.json` (new)
* **Verify:** `jq . .ccanvil/fixtures/canonical-example-data.json` exits 0.

### Step 2: Bats test for SSOT structure (AC-3, AC-4, AC-9)

* **Test:** Write `hub/tests/canonical-fixtures.bats` covering:
  * File exists + parses as JSON
  * `.version` is a positive integer
  * `.emails` is an array with ≥3 entries; every `address` matches `@example\.(com|org|net)$`
  * Malformed-JSON helper (overwrite with garbage, jq fails) — AC-9 contract proof
* **Implement:** No script code yet — assertions read the JSON directly. Tests run green against the file from Step 1.
* **Files:** `hub/tests/canonical-fixtures.bats` (new)
* **Verify:** `bats hub/tests/canonical-fixtures.bats` passes; running the same test against an artificially-deleted SSOT shows red.

### Step 3: Bats test for lifecycle-docs CI yaml (AC-1, AC-2)

* **Test:** Write `hub/tests/ci-template-lifecycle-docs.bats` asserting:
  * The shipped template `.ccanvil/templates/github/workflows/ci.yml` contains a `lifecycle-docs:` job
  * The job's `if:` condition contains both `pull_request` and `draft == false`
  * The workflow `on:` block still lists `pull_request` (regression on AC-2)
  * The `lifecycle-docs` step still emits the `Lifecycle docs must be cleaned up before merge` error message (regression — fix shape, not intent)
* **Implement:** No template change yet. Test should fail red (template currently has no `draft == false` check).
* **Files:** `hub/tests/ci-template-lifecycle-docs.bats` (new)
* **Verify:** `bats hub/tests/ci-template-lifecycle-docs.bats` shows red on the "draft == false" assertion.

### Step 4: Modify CI template — add the draft guard

* **Test:** Step-3 tests; flip from red to green.
* **Implement:** Edit `.ccanvil/templates/github/workflows/ci.yml` — change the `lifecycle-docs.if:` line from `github.event_name == 'pull_request'` to `github.event_name == 'pull_request' && github.event.pull_request.draft == false`.
* **Files:** `.ccanvil/templates/github/workflows/ci.yml` (modified)
* **Verify:** `bats hub/tests/ci-template-lifecycle-docs.bats` passes 4/4.

### Step 5: Documentation in configuration.md (AC-5)

* **Test:** Extend `hub/tests/canonical-fixtures.bats` with grep-assertions on `.ccanvil/guide/configuration.md` — must cite `canonical-example-data.json`, mention the `security-audit.sh` exclusion regex, and explain the SSOT's purpose. Mirrors AC-5's structural shape (BTS-460 used the same drift-guard pattern).
* **Implement:** Add a new subsection under the BTS-460 "Hub describes behavior, node describes implementation" pattern in `.ccanvil/guide/configuration.md` documenting the canonical SSOT.
* **Files:** `.ccanvil/guide/configuration.md` (modified), `hub/tests/canonical-fixtures.bats` (extended)
* **Verify:** Extended bats test passes; visual review of the new section reads coherently.

### Step 6: Regression — full bats suite (AC-7)

* **Test:** No new test; run the whole suite.
* **Implement:** N/A.
* **Files:** None.
* **Verify:** `bash .ccanvil/scripts/docs-check.sh test-suite-run --project-dir . --parallel --progress` returns 0 with all tests green (\~2280+ tests + \~7 new).

## Risks

* **Risk:** `if:` **condition syntax wrong.** GitHub Actions has a specific expression grammar. Mitigation: assert the exact string in the bats test; cross-reference an existing `if:` in any ccanvil hub workflow (none exists, so we'll cite the GH docs pattern inline in the test comment). The condition is plain string-equality in our test (grep), so syntactic issues only surface when the workflow runs in CI — but the change is mechanically simple (single condition AND-combined) and the failure mode is "job runs anyway" (regress to current behavior), not catastrophic.
* **Risk: bats test brittleness on whitespace/quoting in yaml.** Mitigation: assert on a minimum-content substring, not on exact line shape. Use `grep -F` for fixed-string match where possible.
* **Risk: configuration.md edits trigger drift-guard on the BTS-460 worked example section.** Mitigation: add the new SSOT subsection AFTER the BTS-460 section, not inside it. Validate by running the full suite at Step 5.
* **Risk: SSOT file gets manifest-tracked accidentally.** Mitigation: JSON files are not in the manifest allowlist by default; no change to `manifest-allowlist.txt`. Verified by running `module-manifest.sh validate --json` at Step 6 (part of the full suite).

## Definition of Done

- [ ] All acceptance criteria from spec pass (AC-1 through AC-9; AC-8 deferred to post-merge operator step)
- [ ] All existing tests still pass (full hub bats suite)
- [ ] No type errors (bash -n on any touched scripts — only template + JSON + doc edits in this PR, no shell code change)
- [ ] Module manifest: 195/195, drift 0
- [ ] Code reviewed (run /review)
