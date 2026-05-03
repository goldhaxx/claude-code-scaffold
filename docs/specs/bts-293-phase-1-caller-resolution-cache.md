# Feature: Phase 1 — caller-resolution cache for cmd_validate

> Feature: bts-293-phase-1-caller-resolution-cache
> Work: linear:BTS-293
> Created: 1777789773
> Subject: Phase 1 — caller-resolution cache for cmd_validate
> Status: Complete

## Summary

Pre-compute a caller-resolution index inside `cmd_validate` so the per-entry caller check becomes an in-memory map lookup instead of repeated grep+awk file scans. Source-walk inspection (added during BTS-282/281 follow-up): the dominant cost in `cmd_validate` at hub scale is NOT `cmd_extract` (~189 fast bash parses) but `_caller_actually_calls_primitive` — for every bare-form caller declaration it re-walks `.ccanvil/scripts/*.sh` + `.claude/hooks/*.sh` and runs grep+`_function_body_grep` (awk) per file. With ~189 manifests × ~2 caller declarations × ~20 file scans per check, that's ~7,500 awk/grep forks per validate run, dominating the 7-minute wall on M4 Max. Phase 1 walks the source dirs ONCE up-front, builds an in-memory index, and replaces the inner search loop with a hash-shaped lookup. Phases 2 (parallelize) and 3 (incremental) are queued as **BTS-294** and **BTS-295**.

## Job To Be Done

**When** `module-manifest.sh validate` runs against the full hub allowlist (~189 entries),
**I want to** pay the file-scan cost ONCE per validate invocation rather than ~20× per entry,
**So that** validate wall-time drops from ~7 min to ~3-4 min on M4 Max, compounding the BTS-281 caching wins (suite wall ~9:39 → ~5-6 min).

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** **Given** the hub allowlist (~189 entries) on a clean tree, **when** `bash .ccanvil/scripts/module-manifest.sh validate --json` runs, **then** the resulting JSON envelope is byte-for-byte identical to the pre-refactor output (same `coverage.covered`, same `coverage.total`, same `drift` array — order may differ but set-equal). Verified by capturing pre- and post-refactor `validate --json` output, normalizing `drift` order, and asserting deep-equal via `jq`.

- [ ] **AC-2:** When `validate` is invoked, the new helper `_build_caller_index` runs at most ONCE per invocation (verified by adding a temporary trace counter under an env-gated debug mode, asserting count == 1 across the allowlist walk). The trace counter is removed before commit.

- [ ] **AC-3:** **Given** the hub allowlist, **when** `time bash .ccanvil/scripts/module-manifest.sh validate --json > /dev/null` runs, **then** the wall-time is at least 30% lower than the pre-refactor baseline of ~7 min (target: ≤4:50 on M4 Max). Verified by capturing pre- and post-refactor wall-time, recording both in the PR body. Acceptable failure: wall reduction ≥20% if total CPU reduction is ≥40%.

- [ ] **AC-4:** All existing module-manifest tests pass (`bats hub/tests/module-manifest-*.bats`). The drift-guard's mutation tests in particular MUST still detect every kind of drift the pre-refactor code detected — the index optimization is observation-only, not behavior-changing. Verified by running every drift-shape test and asserting same DRIFT lines emitted.

- [ ] **AC-5 (regression / cache invalidation):** **Given** a stale fixture where the index was built before a source-file edit (simulated via a unit-test that calls `_build_caller_index` once, modifies a source file's content, then re-validates), **when** validate runs, **then** the index is rebuilt for the current invocation (caches do NOT persist across invocations — each `cmd_validate` call gets a fresh index). Verified by a bats test that invokes validate twice with a mid-flight source edit between them; both runs see the post-edit content.

- [ ] **AC-6:** Manifest declarations on `module-manifest.sh` itself remain self-consistent (drift-guard clean). Any new helper functions (`_build_caller_index`, `_caller_index_lookup`) gain `# @manifest` blocks if they are reachable as substrate primitives, OR are documented inline as private helpers (per existing pattern for `_function_body_grep` etc.). Verified by `bash .ccanvil/scripts/module-manifest.sh validate --json` returning `status: ok` after the refactor.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/module-manifest.sh` | Modified — add `_build_caller_index` (walks source dirs once, builds in-memory map of function-name → file + body refs); refactor `_caller_actually_calls_primitive` to consult the index when present; pass the index into `cmd_validate`'s entry loop |
| `hub/tests/module-manifest-validate-deep.bats` | Modified — add an AC-5 regression test that proves the index is per-invocation (no stale-cache surprise) |
| `hub/tests/module-manifest-self-application.bats` | Modified — bump verb count if new helper functions need manifest declarations (per existing pattern) |

## Dependencies

- **Requires:** nothing. Stand-alone optimization within `module-manifest.sh`.
- **Blocked by:** nothing.

## Out of Scope

- **Phase 2 — parallelize the per-manifest validation loop** (captured as **BTS-294**). Pre-req: this Phase 1 lands first, so the parallel workers consume the cached index instead of re-scanning per worker.
- **Phase 3 — incremental validate via hash-based skip** (captured as **BTS-295**). Adds a state file + invalidation rules; requires more spec time. Pre-req: Phases 1 + 2 land first.
- **Caching across invocations.** Each `cmd_validate` call gets a fresh index. Cross-invocation persistence is BTS-295's territory.
- **Modifying `cmd_extract`.** The original BTS-293 capture framed this as "cmd_extract caching." Source walk shows extract is fast relative to caller-resolution; the actual bottleneck is the inner grep+awk loop in `_caller_actually_calls_primitive`. Spec narrows the scope accordingly.

## Implementation Notes

- **Index shape.** A bash associative array (or — bash 3.2 fallback — a temp JSON file consumed via jq):
  ```
  index_by_fn["docs-check.sh:cmd_artifact_write"] = "/abs/path/to/docs-check.sh"
  index_pattern_hits["/abs/path/to/file.sh:cmd_X"] = "1" if grep -qE "$pattern" file.sh
  ```
  Bash 3.2 does NOT support `declare -A` (per memory `feedback_avoid_per_entry_cmd_extract_at_full_scale`). Use either:
  - (a) Two-list pattern (`names=(); paths=()`; linear search), OR
  - (b) JSON tempfile + jq lookups (mirrors BTS-269 cmd_graph pattern).
  Pick (b) — already proven at scale, jq lookups are O(1) shape and don't hit fork pressure.

- **Build phase.** `_build_caller_index` walks `.ccanvil/scripts/*.sh`, `.claude/hooks/*.sh`, `.claude/hooks/_lib/*.sh` ONCE. For each file, captures: (1) all function-name declarations (`^cmd_X()`, `^_helper()`, etc.), (2) the file's full content (or pre-greps for primitive-id patterns and stores hits). Emits to `$BATS_TEST_TMPDIR/.../caller-index.json` (or process-local equivalent — must be reachable from the per-entry loop in cmd_validate).

- **Lookup phase.** `_caller_actually_calls_primitive` checks the index first; on hit (caller-found-and-references-primitive), return 0 immediately. On miss, the slow path still runs (preserves all current correctness). Live-validation gate: assert that the slow-path NEVER fires on a clean hub run (counter == 0).

- **Live-API gate (BTS-171, TDD rule):** Stubs accept any index shape. The contract is that the index produces the SAME drift output as the pre-refactor code on every existing manifest. Live-validate by running pre- AND post-refactor against the same hub, capturing both `validate --json` outputs, and asserting they're set-equal.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
