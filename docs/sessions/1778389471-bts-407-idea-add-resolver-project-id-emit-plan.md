# Implementation Plan: idea.add resolver emits --project-id when configured

> Feature: bts-407-idea-add-resolver-project-id-emit
> Work: linear:BTS-407
> Created: 1778387840
> Spec hash: d9a940ea
> Based on: docs/spec.md

## Objective

Make `operations.sh` Linear-routed verbs emit `--project-id <uuid>` when `provider_config.project_id` is set, falling back to `--project <name>` only when the UUID is absent — eliminating the `--project ''` empty-string emission that fails on downstream nodes.

## Sequence

### Step 1: Add a failing fixture for the AC-1 shape (project_id only)

* **Test:** Add a `_with_linear_routing_uuid_only` helper to `hub/tests/operations-resolve-http.bats` that writes a config with `project_id: "PROJ-UUID-1"` and NO `project` field. Add `@test "BTS-407 AC-1: idea.add with project_id only emits --project-id, never --project ''"`.
* **Implement:** Test only; no impl yet.
* **Files:** `hub/tests/operations-resolve-http.bats` (modified — add helper + test).
* **Verify:** Run the new test; it MUST fail RED with "got `--project ''`, expected `--project-id 'PROJ-UUID-1'`".

### Step 2: Implement the dual-flag emission for idea.add

* **Test:** Step 1's failing test.
* **Implement:** In `.ccanvil/scripts/operations.sh`'s `linear_mcp_adapter()`, after line 446 add `local project_id; project_id=$(echo "$provider_config" | jq -r '.project_id // ""')`. In the `idea.add` verb's `jq -n` block, add `--arg project_id "$project_id"` and replace the `--project` concat with `(if $project_id != "" then " --project-id " + ($project_id | @sh) elif $project != "" then " --project " + ($project | @sh) else "" end)`.
* **Files:** `.ccanvil/scripts/operations.sh` (modified).
* **Verify:** Step 1's test passes GREEN. The pre-existing `BTS-164 AC-4` test (which uses fixture without `project_id`) still passes via the `elif $project != ""` fallback.

### Step 3: Add AC-2 (both set, UUID wins) and AC-3 (name-only fallback) tests for idea.add

* **Test:** Add three new tests to the operations-resolve-http.bats file:
  * `@test "BTS-407 AC-2: idea.add with both project_id AND project prefers --project-id"`
  * `@test "BTS-407 AC-3: idea.add with project name only still emits --project (existing behavior)"` — duplicates an existing assertion intentionally for explicit AC traceability.
* **Implement:** Test only; impl from Step 2 should already cover both.
* **Files:** `hub/tests/operations-resolve-http.bats` (modified).
* **Verify:** All three tests pass GREEN against Step 2's impl.

### Step 4: Apply the same pattern to the remaining 5 verbs (AC-4)

* **Test:** Add per-verb AC-1-shape tests (project_id only → emits `--project-id`, never `--project ''`) for `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`, `backlog.list`. Author one test per verb. Run; confirm all 5 fail RED.
* **Implement:** Apply the same `(if $project_id != "" then " --project-id " + ... ...)` pattern to the `jq -n` blocks at [operations.sh](<http://operations.sh>) lines 547, 573, 601, 648, 498 (backlog.list).
* **Files:** `.ccanvil/scripts/operations.sh` (modified — 5 more verbs).
* **Verify:** All 5 new tests + Step 1's idea.add test pass GREEN.

### Step 5: AC-5 (both empty → no flag) and AC-6 (shell-meta escaping) edge tests

* **Test:** Add `@test "BTS-407 AC-5: when both project_id and project are empty, no --project* flag is emitted"` — fixture with empty config; assert `.invocation.command` does NOT contain `--project ` and does NOT contain `--project-id`. Add `@test "BTS-407 AC-6: project_id with shell-meta is @sh-quoted"` — fixture with `project_id: "uu'id"`; assert command contains `'uu'\\''id'` (the `@sh` round-trip shape).
* **Implement:** Existing impl from Steps 2+4 should cover both — verify, no new code expected.
* **Files:** `hub/tests/operations-resolve-http.bats` (modified).
* **Verify:** Both tests pass GREEN. If AC-6 fails, the `@sh` filter is missing and needs to be added (it's already in the proposed pattern).

### Step 6: Full-suite validation + manifest probe

* **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel`. Confirm 0 failures. Re-run on a 1/N spurious fail to mitigate BTS-263 flakiness.
* **Implement:** Run `bash .ccanvil/scripts/module-manifest.sh validate --json` — confirm 194/194, drift 0.
* **Files:** None.
* **Verify:** Tests PASS. Manifest unchanged.

## Risks

* **Hub config has both** `project` AND `project_id` set. AC-2 says UUID wins, which is the desired behavior, but the existing `BTS-164 AC-4` test asserts `.invocation.command | contains("ccanvil")` — that's the project NAME. With UUID-preference, this assertion would now fail because the resolved command no longer contains "ccanvil" (it contains the UUID instead). Mitigation: the existing test fixture (`_with_linear_routing` at lines 22-29) sets only `project: "ccanvil"` with NO `project_id` — so AC-3 fallback fires and the test still passes. **Verified by reading the fixture before drafting.**
* **No live-API call needed.** Pure resolver logic; no Linear round-trip; stub fixtures suffice. (No live-API gate per `.claude/rules/tdd.md`.)
* **6 verbs × 1-3 tests each = \~10-15 new tests** — keep them tight; don't over-mirror existing AC-4 broad-shape assertions.

## Definition of Done

- [ ] All 6 ACs from spec pass
- [ ] All 2151 existing tests still pass (baseline)
- [ ] No new shellcheck warnings on [operations.sh](<http://operations.sh>)
- [ ] Code reviewed (run /review)
- [ ] Manifest 194/194, drift 0
  <!-- NODE-SPECIFIC-START -->
  <!-- Add project-specific content below this line. -->
  <!-- Hub content above is updated via /ccanvil-pull. -->
