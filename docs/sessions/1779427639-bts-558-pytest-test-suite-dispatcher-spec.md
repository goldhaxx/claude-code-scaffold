# Feature: pytest dispatcher arm for test-suite-run

> Feature: bts-558-pytest-test-suite-dispatcher
> Work: linear:BTS-558
> Created: 1779417157
> Subject: pytest dispatcher arm for test-suite-run
> Status: In Progress

## Summary

`cmd_test_suite_run` (`.ccanvil/scripts/docs-check.sh`, BTS-460) is the provider-aware
test dispatcher `/pr` calls so it never hardcodes a runner. Only the `bats` arm landed;
every other provider falls through to `*)` and exits 2 (`not yet implemented`). This adds
the `pytest` arm so a node with `test-provider: pytest` routes `test-suite-run` to its
real pytest suite. The interpreter path and test directory are node-specific
(fieldnation-toolbox runs `.venv/bin/python -m pytest src/`), so they come from node
config (`test-command`, `test-path`) — the hub describes behavior, the node describes
implementation. No new hub script: pytest's own ecosystem (xdist, exit codes, progress)
already provides what `bats-report.sh` hand-rolls.

## Job To Be Done

**When** a pytest-stack downstream node runs `/pr` (which invokes `test-suite-run`),
**I want to** route the call to that node's real pytest suite with correct exit-code propagation,
**So that** the `/pr` pre-merge gate reflects actual pytest pass/fail instead of erroring (exit 2) or silently false-greening against an empty `hub/tests/`.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given `.claude/ccanvil.json` with `test-provider: pytest` and a `test-command` (and optional `test-path`), when `test-suite-run` runs and every pytest test passes, then the dispatcher executes the node's pytest command (with `test-path` appended when present) in the project dir and exits 0.
- [ ] **AC-2:** Given a failing pytest test, when `test-suite-run` runs, then the dispatcher exits non-zero — so `/pr` step 2 stops.
- [ ] **AC-3:** Given `test-provider: pytest` and `--parallel` is passed, when `test-suite-run` runs, then the dispatcher *translates* it — `-n auto` (pytest-xdist) is appended to the pytest command, and the literal `--parallel` token is NOT forwarded to pytest (pytest does not recognize it).
- [ ] **AC-4 (error):** Given `test-provider: pytest` but no `test-command` key, when `test-suite-run` runs, then the dispatcher exits 2 with a stderr error naming the missing `test-command` key — a loud dispatch-time failure, never a false green.
- [ ] **AC-5 (edge):** Given `test-provider: pytest` and pytest collects no tests (exit 5), when `test-suite-run` runs, then the dispatcher exits non-zero (normalized to 1) with a clear `no tests collected` stderr message.
- [ ] **AC-6:** Given `test-provider: pytest`, when `test-suite-run` runs, then the OTel Collector healthcheck is skipped — a deliberate, temporary provider carve-out, since pytest nodes have no OTel stack yet. The `bats` provider's healthcheck is unchanged. This is NOT the intended end state: BTS-559 builds OTel test tooling for non-bats stacks and then re-enables the healthcheck for all providers.
- [ ] **AC-7:** Given `test-provider` resolves to `bats` (or is absent), when `test-suite-run` runs, then bats-arm behavior is byte-for-byte unchanged — every existing `test-suite-run.bats` and `docs-check-test-suite-run-healthcheck.bats` test still passes.
- [ ] **AC-8:** Given `test-provider: pytest` and a bats-only flag (`--json`, `--timings`, `--progress`, `--slow-top N`, `--no-telemetry`), when `test-suite-run` runs, then the dispatcher recognizes and *drops* the flag — it is NOT forwarded to pytest (which would reject it), the dispatcher does not crash, and these are documented v1 no-ops for pytest.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/docs-check.sh` | Modified — `cmd_test_suite_run`: add `pytest)` arm; gate the OTel healthcheck to `provider == bats`; update the `# @manifest` block + `# @failure-mode:` code markers |
| `hub/tests/test-suite-run.bats` | Modified — replace the obsolete `pytest provider exits 2` test with pytest-arm behavior tests (AC-1/2/3/4/5/8); keep the `vitest` exit-2 test |
| `hub/tests/docs-check-test-suite-run-healthcheck.bats` | Modified — add AC-6 test: pytest provider skips the healthcheck |
| `.ccanvil/guide/configuration.md` | Modified — document the `test-command` / `test-path` node-config keys |

## Dependencies

* **Requires:** BTS-460 (`cmd_test_suite_run` dispatcher) — already shipped.
* **Blocked by:** nothing.
* **Blocks:** fieldnation-toolbox BTS-552 (the node-side `test-provider: pytest` config flip).

## Out of Scope

* A hub-shipped `pytest-report.sh` analog — decided against (config-driven seam chosen).
* Mapping `--json` to a structured pytest envelope — v1 documents it as a no-op.
* The `vitest` dispatcher arm — stays unimplemented (exit 2).
* The bats-arm no-args trap is NOT replicated for pytest — a zero-arg pytest call runs the node's full suite, which is intended.
* Re-enabling the OTel healthcheck for pytest (and other non-bats providers) — that needs the cross-language test-observability tooling tracked in BTS-559.

## Implementation Notes

* Follow the existing `bats)` arm shape in `cmd_test_suite_run` (`docs-check.sh:8244`).
* `test-command` is a multi-word operator-supplied string (e.g. `.venv/bin/python -m pytest`); run it word-split inside `project_dir` so relative venv/test paths resolve. `test-path` (e.g. `src/`) is appended when present; absent → pytest's own default discovery.
* The pytest arm interprets `forward_args` itself rather than forwarding them blindly — the bats arm forwards verbatim because `bats-report.sh` understands the flags; pytest does not. Per token: `--parallel` → append `-n auto`; `--json` / `--timings` / `--progress` / `--no-telemetry` → drop (recognized no-op); `--slow-top` → drop the flag and its following value (2-token no-op); everything after a `--` separator → forward to pytest verbatim; bare positional args → forward verbatim.
* pytest exit codes: `0` pass → `0`; `1` tests failed → pass through; `5` no tests collected → normalize to `1` + the AC-5 message; any other non-zero → pass through.
* The OTel healthcheck block (`docs-check.sh:8225-8242`) currently runs before the `case` for every provider. Guard it with `[[ "$provider" == bats ]]` (or move it into the `bats)` arm) so only bats runs it. Mark the gate with a `# BTS-559:` comment — this carve-out is temporary; BTS-559 re-enables the healthcheck for all providers once non-bats OTel tooling exists.
* Keep the `# @manifest` block in sync: add `failure-mode` lines for `missing-test-command` and `pytest-no-tests-collected`, and matching `# @failure-mode:` code markers — the BTS-268 drift-guard blocks the PR otherwise.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
