# Implementation Plan: substrate-staleness drift-guard

> Feature: bts-419-substrate-staleness-drift-guard
> Work: linear:BTS-419
> Created: 1778445000
> Spec hash: 9939cd48
> Based on: docs/spec.md

## Objective

Add a runtime self-consistency check in `linear_mcp_adapter` that hard-fails (with `ALLOW_STALE_SUBSTRATE=1` bypass) when `project_id` is configured but the emitted command for any of the six project-scoped verbs lacks `--project-id`, plus a hub-side drift-guard fixture that proves the contract on every CI run.

## Architectural decisions (resolving spec's open questions)

1. **Where the guard lives:** **Option 2 — centralized post-emit helper inside** `linear_mcp_adapter`. New function `linear_assert_project_id_emitted <verb> <project_id> <cmd_json>` that round-trips the emitted JSON, validates the invariant, exits non-zero on mismatch. Called from each of the 6 project-scoped verbs after their `jq -n` block. Six call-sites BUT one source-of-truth for the assertion semantics. Option 1 (inline) duplicates the check; Option 3 (`cmd_resolve` post-pass) duplicates verb-set knowledge across the boundary.
2. **Hard-fail vs warn:** **Hard-fail with** `ALLOW_STALE_SUBSTRATE=1` env bypass. Matches existing `ALLOW_DESTRUCTIVE` / `ALLOW_MAIN` / `ALLOW_OUTSIDE_WORKSPACE` precedent. Loud signal by default; operator-controlled escape valve when a legacy node deliberately runs old-shape config.
3. **Pair-ship with BTS-418:** **Independent.** BTS-418 hardens a different contract surface (resolver→wrapper flag set); shipping it sequentially keeps each PR scope-bounded and review-friendly.

## Sequence

Twelve TDD steps. Each is one red-green cycle, \~5-15 minutes.

### Step 1: helper-stub-and-clean-cases

* **Test:** New file `hub/tests/operations-drift-guard.bats`. First test: `linear_assert_project_id_emitted` exists in `operations.sh` (grep for function definition) AND passes through unchanged JSON when `project_id` is empty (no fire). Second test: passes through when emitted command already contains `--project-id ` substring.
* **Implement:** Add `linear_assert_project_id_emitted()` to `operations.sh` directly above `linear_mcp_adapter` (line 437). Body: if `$project_id` is empty OR the JSON's `.invocation.command` contains `--project-id `, echo input verbatim and return 0. Otherwise (next step) fire.
* **Files:** `.ccanvil/scripts/operations.sh`, `hub/tests/operations-drift-guard.bats`.
* **Verify:** `bats hub/tests/operations-drift-guard.bats` — 2/2 GREEN.

### Step 2: AC-3-core-staleness-fire

* **Test:** Given `project_id="UUID-1"`, verb=`backlog.list`, and a `cmd_json` whose `.invocation.command` lacks `--project-id`, helper exits non-zero AND stderr contains literal `stale substrate` AND stderr contains literal `ccanvil-sync.sh pull`.
* **Implement:** Extend helper — when project_id non-empty and command lacks `--project-id`, write the AC-7-shape error to stderr and `exit 1`. Use the exact message body shown in spec Implementation Notes.
* **Files:** `.ccanvil/scripts/operations.sh` (helper body), `hub/tests/operations-drift-guard.bats`.
* **Verify:** new test GREEN; Step 1 tests still GREEN.

### Step 3: AC-7-operator-grade-message

* **Test:** Same fire-condition as Step 2 — additionally assert stderr contains: (a) the literal project_id value, (b) the literal verb name (e.g., `resolve(backlog.list)`), (c) the `cd <project-dir> && bash .ccanvil/scripts/ccanvil-sync.sh pull` recipe.
* **Implement:** Interpolate `$verb` + `$project_id` into the stderr template. Use `PWD` (or pass project-dir as a 4th arg) to render the `cd` path.
* **Files:** `.ccanvil/scripts/operations.sh`.
* **Verify:** new asserts GREEN; Step 2 still GREEN.

### Step 4: AC-5-no-fire-on-non-project-scoped

* **Test:** Direct helper invocation: even if `project_id` is set, the helper is only called from inside the 6 project-scoped verb branches. To prove the contract structurally, add a test that resolves `ticket.transition BTS-100 done` against a config with `project_id` set — assert exit 0 and no stderr `stale substrate` substring.
* **Implement:** No code change — the helper is wired in Step 6; this test pre-locks the AC-5 contract before wiring. Should already pass (helper is dormant until called).
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** test GREEN.

### Step 5: ALLOW_STALE_SUBSTRATE=1-bypass

* **Test:** Given fire-condition from Step 2 AND `ALLOW_STALE_SUBSTRATE=1` env, helper echoes input JSON verbatim AND exit 0 AND stderr is empty OR contains only a single-line `WARN:` advisory.
* **Implement:** First branch of helper body: `[[ "${ALLOW_STALE_SUBSTRATE:-}" == "1" ]] && { echo "$cmd_json"; return 0; }`. Optionally emit `WARN: stale-substrate bypass active for <verb>` to stderr.
* **Files:** `.ccanvil/scripts/operations.sh`.
* **Verify:** bypass test GREEN; Step 2 still GREEN.

### Step 6: wire-helper-into-six-verbs

* **Test:** Existing BTS-407 ACs (lines 260-348 in `operations-resolve-http.bats`) MUST stay GREEN. Plus per-verb fire test: for each of 6 verbs, with `project_id` set AND a synthetically-corrupted resolved emission (achieved by overriding `linear_assert_project_id_emitted` to a no-op in test setup, OR by patching `operations.sh` to flip the conditional — choose the option that requires less test plumbing).
* **Implement:** For each of `backlog.list` / `idea.add` / `idea.list` / `idea.count` / `idea.triage` / `idea.review-icebox` in `linear_mcp_adapter`: capture the `jq -n` output into `local cmd_json`, then call `cmd_json=$(linear_assert_project_id_emitted "<verb>" "$project_id" "$cmd_json")` (or pipe via `|`), then `echo "$cmd_json"` to stdout. Refactor surface: 6 verbs × \~3-line change each.
* **Files:** `.ccanvil/scripts/operations.sh`.
* **Verify:** `bats hub/tests/operations-resolve-http.bats hub/tests/operations-drift-guard.bats` — all GREEN; 6 verbs now defended end-to-end.

### Step 7: AC-1-verb-loop-positive-fixture

* **Test:** New parameterized test in `operations-drift-guard.bats` that loops over the 6-verb set with `project_id="UUID-1"` config (no `project` name); for each verb, resolve via full `operations.sh resolve <verb>` and assert output contains `--project-id `.
* **Implement:** Test only — exercises the existing BTS-407 fix through the end-to-end dispatcher path. Failure would indicate verb-list drift OR resolver regression.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** GREEN — 6 subtests.

### Step 8: AC-2-no-empty-flag-emission

* **Test:** Loop over 6 verbs with BOTH `project_id` and `project` empty; assert resolved command contains NEITHER `--project ''` NOR `--project-id ''`. Mirrors BTS-407 AC-5 but iterates.
* **Implement:** Test only.
* **Files:** `hub/tests/operations-drift-guard.bats`.
* **Verify:** GREEN — 6 subtests.

### Step 9: AC-6-manifest-declaration

* **Test:** `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0 with `.coverage.covered == .coverage.total` and `.drift == []`. Specifically, the `linear_mcp_adapter` manifest should now declare the new exit path; the new `linear_assert_project_id_emitted` helper itself needs a `# @manifest` block.
* **Implement:** Add `# @manifest` block above `linear_assert_project_id_emitted` (purpose/input/output/caller `linear_mcp_adapter`/depends-on `jq`/failure-mode `stale-substrate-emit | exit=1 | visible=stderr-ERROR-with-pull-recipe | mitigation=run-ccanvil-sync.sh-pull-OR-ALLOW_STALE_SUBSTRATE=1-prefix` / contract `env-prefix-bypass-via-ALLOW_STALE_SUBSTRATE=1` / anchor `BTS-419`). Append the new function symbol to `.ccanvil/manifest-allowlist.txt`. Update `linear_mcp_adapter`'s `# depends-on:` list to include the new helper.
* **Files:** `.ccanvil/scripts/operations.sh`, `.ccanvil/manifest-allowlist.txt`.
* **Verify:** `module-manifest.sh validate --json` reports `.status == "ok"`; allowlist count +1.

### Step 10: bats-full-suite-regression

* **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel --progress` (BTS-118 / BTS-383 streaming).
* **Implement:** No code; verification step. If failures surface, fix before proceeding.
* **Files:** none.
* **Verify:** zero new failures vs. baseline (2161 GREEN, modulo BTS-263 flake territory).

### Step 11: live-API-verify-no-false-fire

* **Live-API gate (BTS-171):** the staleness guard is in-band on every Linear-routed verb dispatch. Stubs accept any command shape; only a live call against the configured hub config (`project_id` set, real GraphQL endpoint) verifies the guard doesn't fire false on the actual contract. The commands that prove the contract:

  ```
  bash .ccanvil/scripts/operations.sh resolve idea.count --project-dir .
  bash .ccanvil/scripts/operations.sh resolve backlog.list --project-dir .
  ```

  Both MUST emit `mechanism: http` with `--project-id` present and no `stale substrate` stderr. Run before commit on Step 6 AND before `/review`.
* **Implement:** none (verification).
* **Files:** none.
* **Verify:** both commands print clean JSON envelopes. Optionally chase one through to actual Linear query: `eval "$(bash .ccanvil/scripts/operations.sh resolve idea.count --project-dir . | jq -r '.invocation.command')"` returns a numeric count, not an error.

### Step 12: docs-update-if-needed

* **Test:** none (docs review).
* **Implement:** Check `.ccanvil/guide/scripts.md` for resolver patterns documentation. If the section mentions `linear_mcp_adapter` semantics or post-emit invariants, add a one-paragraph note about the staleness guard + bypass token. If no resolver-internals section exists, skip — this is substrate-internal, no operator-facing surface introduced.
* **Files:** `.ccanvil/guide/scripts.md` (conditionally).
* **Verify:** read the file; either edit made + reviewed OR skipped with rationale captured in commit message.

## Risks

* **R1: Helper signature change breaks parallel work.** Adding a 4th arg to the helper mid-flow (Step 3 might need project-dir) would invalidate Step 1/2 tests. Mitigation: in Step 1, define the signature as `linear_assert_project_id_emitted <verb> <project_id> <cmd_json>` and pin to that — read project-dir from `$PWD` or env at call site if needed for AC-7 cd-recipe.
* **R2: Test plumbing for Step 6's synthetic-corrupt path.** The cleanest way to force the 6 wired verbs to emit a no-`--project-id` command is hard. Mitigation: skip the synthetic-corrupt per-verb test in Step 6 — the helper's unit tests in Steps 2-3 already prove the assertion fires; Step 6 only proves wiring (BTS-407 ACs + AC-1 loop are sufficient).
* **R3: Manifest drift on commit.** New helper symbol may not be on the allowlist; missing `# @manifest` block. Mitigation: Step 9 is mandatory before `/pr`.
* **R4: Live-API false-fire.** If the hub config has been edited to omit `project_id`, the guard won't fire but the underlying behavior also won't differ. Mitigation: Step 11's live-API call confirms expected shape.

## Definition of Done

- [ ] All 7 acceptance criteria from spec pass (AC-1 through AC-7).
- [ ] All existing tests still pass (2161 baseline, modulo BTS-263 flake).
- [ ] `module-manifest.sh validate` reports `status: ok`, drift count 0.
- [ ] Live-API smoke (Step 11) confirms no false-positive on hub config.
- [ ] Code reviewed (run /review before /pr).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
