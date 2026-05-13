# Feature: Test-provider indirection: /pr dispatcher reads node config

> Feature: bts-460-test-provider-indirection
> Work: linear:BTS-460
> Created: 1778687980
> Subject: Test-provider indirection: /pr dispatcher reads node config
> Status: In Progress

## Summary

The `/pr` skill (and any future hub-shipped rule that runs the test suite) currently hardcodes `bash .ccanvil/scripts/bats-report.sh --parallel --progress`. This is correct for the hub and any bats-stack downstream node, but breaks for nodes running pytest, vitest, jest, etc. — exactly the BTS-460 hub/node-separation gap. This ship introduces (1) a `test-provider` config key in `.claude/ccanvil.json` (optional, default `bats`), (2) a `docs-check.sh test-suite-run` dispatcher verb that reads the key and invokes the right runner, and (3) migrates `/pr` to call the dispatcher. Documents the "describe behavior at hub, describe implementation at node" pattern in `.ccanvil/guide/configuration.md` with this migration as the worked example. First concrete instance of the BTS-460 architectural seam.

## Job To Be Done

**When** I author a hub-shipped rule or skill that needs to invoke the project's test suite,
**I want to** describe the *behavior* (run the test suite, fail on regression) declaratively, with tooling resolved from node-local config,
**So that** the same rule operates correctly on bats, pytest, vitest, and future stacks without per-node forks or hardcoded tool names leaking through hub content.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `docs-check.sh test-suite-run --project-dir <p>` exists; reads `.test-provider` (or `.stacks[0]` fallback) from `<p>/.claude/ccanvil.json`. Missing key defaults to `bats` (back-compat).
- [ ] **AC-2:** When provider resolves to `bats`, the dispatcher invokes `bash .ccanvil/scripts/bats-report.sh --parallel --progress` and forwards stdout/stderr/exit verbatim. Any positional args (e.g. `--json`) pass through to `bats-report.sh`.
- [ ] **AC-3:** When provider resolves to an unimplemented value (`pytest`, `vitest`, `jest`, `go`, anything non-`bats`), the dispatcher exits 2 with stderr `ERROR: test-provider '<v>' dispatcher not yet implemented — see BTS-460-followup`. No partial execution.
- [ ] **AC-4:** `.claude/commands/pr.md` Step 2 prose calls `bash .ccanvil/scripts/docs-check.sh test-suite-run --project-dir . --parallel --progress` instead of `bash .ccanvil/scripts/bats-report.sh --parallel --progress`. The BTS-118/BTS-383 explanatory text (single-invocation discipline + 30s heartbeat) is preserved.
- [ ] **AC-5:** `.ccanvil/guide/configuration.md` gains a new "Hub describes behavior, node describes implementation (BTS-460)" section that (a) documents `test-provider` as the first config indirection key, (b) shows a worked example (rule cites `test-suite-run`, node config selects provider, dispatcher reads provider), (c) lists the inventory of hub-shared content currently leaking tool names (`tdd.md`, `pr.md`, `stasis/SKILL.md`) as captured follow-up work.
- [ ] **AC-6:** Module manifest declared for the new `cmd_test_suite_run` function in `docs-check.sh` (purpose, input, output, caller, depends-on=`bats-report.sh`, side-effect=`spawns-test-runner`, failure-mode=`unimplemented-provider`, contract, anchor). `module-manifest.sh validate` exits 0 on the change.
- [ ] **AC-7 (Regression):** Running `/pr` from the hub (where `.claude/ccanvil.json` has `stacks: ["bats"]` and no `test-provider` key) produces a `test-suite-run` invocation that calls `bats-report.sh` with the same flags as today — observable end-state identical to the hardcoded path.
- [ ] **AC-8 (Error path):** Bats test exists at `hub/tests/test-suite-run.bats` exercising: bats provider success (stub `bats-report.sh` via env override), unimplemented-provider error message + exit 2, missing-key bats default, `--project-dir` flag, positional pass-through.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_test_suite_run` function + dispatch case + manifest |
| `.claude/commands/pr.md` | Step 2 invocation rewritten to dispatcher |
| `.ccanvil/guide/configuration.md` | New "Hub describes behavior" section |
| `hub/tests/test-suite-run.bats` | New bats test |
| `.ccanvil/manifest-allowlist.txt` | Add new `cmd_test_suite_run` entry if not auto-detected |

## Dependencies

- **Requires:** existing `bats-report.sh` (BTS-118), `docs-check.sh` umbrella, module-manifest substrate (BTS-239).
- **Blocked by:** nothing.

## Out of Scope

- Rewriting `.claude/rules/tdd.md` body to remove `bats-report.sh` references (captured as follow-up).
- Migrating `.claude/skills/stasis/SKILL.md` line 131 (`bash .ccanvil/scripts/bats-report.sh --parallel`) to the dispatcher (captured as follow-up — `/stasis` only reports counts, lower urgency than `/pr`'s gate).
- Implementing pytest / vitest / jest / go dispatchers — explicit `not-yet-implemented` error is the contract.
- Expanding `module-manifest.sh`'s `LEAK_LITERALS` rule-vocabulary-leak guard to enforce on more tokens.
- Mirroring the dispatcher pattern to other tooling axes (linter, formatter, package manager). Test-suite is the highest-leverage first instance; others follow if friction surfaces.

## Implementation Notes

- Follow the same shape as existing `cmd_*` functions in `docs-check.sh` (e.g., `cmd_lifecycle_state`). Read-flag pattern via the standard `--project-dir` resolver.
- Provider resolution: prefer explicit `test-provider`. Fall back to `stacks[0]` (e.g., `["bats"]` → bats). Fall back to literal `"bats"` default. This matches the operator's mental model from the BTS-460 ticket *and* respects existing `stacks: ["bats"]` declarations.
- Use the `LINEAR_QUERY_OVERRIDE`-style env-var pattern (`BATS_REPORT_OVERRIDE`) to make `hub/tests/test-suite-run.bats` testable without actually invoking the bats suite. Stub a fixture script; dispatcher invokes the override when set.
- Manifest `failure-mode: unimplemented-provider` with matching inline `# @failure-mode: unimplemented-provider` marker at the die-site (BTS-257 Layer 3 deterministic gate).
- Doc-pattern section in `.ccanvil/guide/configuration.md` should explicitly call out the inventory of leak sites as captured follow-ups (so future contributors know the scope of remaining work without re-discovering it).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
