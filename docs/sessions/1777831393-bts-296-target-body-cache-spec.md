# Feature: Phase 1.5 — target-body cache for cmd_validate markers

> Feature: bts-296-target-body-cache
> Work: linear:BTS-296
> Created: 1777826148
> Subject: Phase 1.5 — target-body cache for cmd_validate markers
> Status: In Progress

## Summary

Pre-extract every (path, id) → function-body once at the start of `cmd_validate`, and have the per-marker check (`_target_body_grep` for depends-on / failure-mode / side-effect) consume the cache instead of re-running an awk file walk per marker. Per BTS-293 follow-up analysis: each manifest declares \~5 depends-on + \~5 failure-mode + \~5 side-effect markers, each marker triggers a `_target_body_grep` call, each call awk-walks the entry's source file. At 189 manifests × \~15 markers = \~2,800 file reads per validate run. Caching collapses this to one extract per unique (path, id) pair (\~189) + \~2,800 in-memory greps. Mirrors the BTS-293 caller-index pattern but for marker resolution.

## Job To Be Done

**When** `module-manifest.sh validate` runs against the full hub allowlist,
**I want to** pay the function-body extraction cost ONCE per (path, id) pair, not once per marker check on that pair,
**So that** validate wall drops from \~5:52 (post-BTS-293) to \~3-4 min, compounding the BTS-281 + BTS-293 caching wins (suite wall \~516s → \~400s).

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** **Given** the hub allowlist (\~189 entries) on a clean tree, **when** `bash .ccanvil/scripts/module-manifest.sh validate --json` runs, **then** the resulting JSON envelope is set-equal to the pre-refactor output (same `coverage.covered`, same `coverage.total`, same `drift` set). Verified by capturing pre- and post-refactor `validate --json` and asserting deep-equal via `jq`.
- [ ] **AC-2:** When `validate` runs, the new helper `_build_target_body_index` runs at most ONCE per invocation (verified by structural inspection — single call site at the top of `cmd_validate`, before the entry loop).
- [ ] **AC-3:** **Given** the hub allowlist, **when** `time bash .ccanvil/scripts/module-manifest.sh validate --json` runs, **then** the wall-time is at least 20% lower than the post-BTS-293 baseline of \~5:52 (target: ≤4:40 on M4 Max). Acceptable failure: wall reduction ≥10% if total CPU reduction is ≥30%.
- [ ] **AC-4:** All existing module-manifest tests pass (`bats hub/tests/module-manifest-*.bats`). The drift-guard's mutation tests in particular MUST still detect every kind of drift the pre-refactor code detected (caller-not-found, missing-failure-mode-marker, missing-side-effect-marker, depends-on-not-found, etc.). Verified by running every drift-shape test and asserting same DRIFT lines.
- [ ] **AC-5 (regression / cache invalidation):** **Given** a stale fixture where the index was built before a target-file edit, **when** validate runs again, **then** the index is rebuilt for the current invocation (caches do NOT persist across invocations). Verified by a bats test that invokes validate twice with a mid-flight source edit between them; both runs see the post-edit content.
- [ ] **AC-6:** Manifest declarations on `module-manifest.sh` itself remain self-consistent (drift-guard clean). New helper functions are file-level helpers (per existing pattern for `_function_body_grep` and `_build_caller_index`) — no new `# @manifest` blocks needed unless they are reachable as substrate primitives. Verified by `validate --json` returning `status: ok`.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified — add `_build_target_body_index` (walks unique (path, id) pairs from allowlist, awk-extracts each function body once); refactor `_target_body_grep` to consult the index when present; pass index path through cmd_validate's entry loop |
| `hub/tests/module-manifest-validate-deep.bats` | Modified — add an AC-5 regression test that proves the index is per-invocation (no stale-cache surprise) |

## Dependencies

* **Requires:** BTS-293 (Phase 1: caller-resolution cache) — already shipped. The caller-index pattern is the reference shape for the new target-body index.
* **Blocked by:** nothing.

## Out of Scope

* **Caching across invocations.** Each `cmd_validate` call gets a fresh index. Cross-invocation persistence is BTS-295 (Phase 3) territory.
* **Phase 2 — parallelize the per-manifest validation loop** (captured as **BTS-294**). Pre-req: this Phase 1.5 lands first; parallel workers consume the cached indices instead of re-scanning per worker.
* **Markdown body extraction.** `_target_body_grep` already short-circuits to `_extract_markdown` for `.md` paths; that branch is fast (single awk pass) and not the bottleneck.
* **Caller index integration.** The caller index built by BTS-293 stays as-is; this ticket adds a SEPARATE target-body index. Merging them is BTS-295 territory.

## Implementation Notes

* **Index shape.** Same TSV pattern as BTS-293's `MM_CALLER_INDEX`: tempfile with one row per (path, id) where row = `<abspath>\t<id>\t<body-with-newlines-encoded-as-\\n>`. Bash 3.2 / awk only.
* **Build phase.** `_build_target_body_index` walks the allowlist once: for each `<path>:<id>` entry, awk-extracts the function body (or whole-file content for file-level shell, or markdown body for `.md`) into the TSV. Single awk per unique path.
* **Lookup phase.** `_target_body_grep` checks the index first via awk-filter on path+id; on hit, sed-decode body + grep for pattern. On miss (e.g., directly invoked outside cmd_validate), fall through to existing slow path. Live-validation gate: assert that the slow-path NEVER fires on a clean hub run.
* **Live-API gate (BTS-171, TDD rule):** Stubs accept any index shape. The contract is that the index produces the SAME drift output as the pre-refactor code on every existing manifest. Live-validate by running pre- AND post-refactor against the same hub, capturing both `validate --json` outputs, and asserting they're set-equal.
* **Awk extraction subtleties.** Mirror the BTS-293 awk pattern: count opens/closes on the function-declaration line itself (one-liner functions like `die() { ...; }` would otherwise swallow the file). For `.md` paths, the index entry's body is the markdown post-frontmatter content; for file-level `.sh` (no `fn()` decl), the entire file is the body.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
