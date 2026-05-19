# Feature: Wire telemetry helper into all hub/tests/*.bats

> Feature: bts-504-wire-telemetry-into-all-bats
> Work: linear:BTS-504
> Created: 1779220275
> Subject: Wire telemetry helper into all hub/tests/*.bats
> Status: In Progress

## Summary

BTS-497 ships the test-observability foundation with a 10-file sample proving the wiring template works across the 6 setup-function categories found in `hub/tests/*.bats`. 165 bats files remain unwired, so AC-7's "every test emits a span" coverage is at ~7%. This feature lands a deterministic injector script that applies the per-category template across the remaining files in one atomic rollout, plus a drift-guard test that fails fast if any future `.bats` file lands unwired.

## Job To Be Done

**When** the operator runs the full bats suite on a Collector-backed stack,
**I want to** see one OTel span emitted per `@test` across every `hub/tests/*.bats` file (minus a small documented skip-list),
**So that** the Grafana dashboard reflects the whole suite's behavior — not just the 11 files BTS-497 sampled — and the substrate's flakiness/latency telemetry covers real load.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given a single `hub/tests/<file>.bats` matching any of Categories A/B/C/E/F (per the truth table in Implementation Notes), when `.ccanvil/scripts/inject-telemetry-source.sh <file>` is invoked, then the file is rewritten with the wiring action that row prescribes. Verification is order-sensitive: where the row says PREPEND, `telemetry_teardown` appears BEFORE the existing teardown body; where the row says APPEND, `telemetry_setup` appears AFTER the existing setup body. Asserted via parsed-AST-equivalent diff (line-anchored regex against expected order, not bare presence-grep).
- [ ] **AC-2:** Given an already-wired file (sourceline marker present), when the injector runs on it, then exit code is 0 AND the file is byte-identical to the pre-invocation state.
- [ ] **AC-3:** Given any `hub/tests/*.bats` file, when the injector classifies it, then it returns exactly one of `A|B|C|E|F|SKIP|UNCLASSIFIED` on stdout — multi-classification is structurally impossible because the 5 supported rows partition the 4-tuple boolean space disjointly.
- [ ] **AC-4:** When `.ccanvil/scripts/inject-telemetry-source.sh --all` is invoked, then every non-skip-listed `hub/tests/*.bats` ends in the wired state; final report counts `wired`, `already_wired`, `skipped`, `unclassified` and exits 0 iff `unclassified == 0`.
- [ ] **AC-5:** Skip-list — the injector carries a documented skip-list (at minimum: `telemetry-helper.bats`, which tests the helper itself); each entry has a one-line rationale comment in the script source.
- [ ] **AC-6:** Drift-guard — a new `hub/tests/telemetry-coverage.bats` fails when any non-skip-listed `hub/tests/*.bats` lacks the wiring marker; passes once full rollout lands.
- [ ] **AC-7:** Error path — given a file whose top-of-file shape matches no category (e.g., `setup_file` + `teardown_file` + `setup` + `teardown` all present with bespoke bodies), the injector exits non-zero AND emits `UNCLASSIFIED: <file>: <reason>` on stderr AND leaves the file unmodified.
- [ ] **AC-8:** Full suite green — after the rollout commit, `bash .ccanvil/scripts/bats-report.sh --parallel --no-telemetry` exits 0 AND every test name in the parent-commit's passing set is also in the post-rollout passing set (no regressions on pre-existing tests; new tests added by this feature are exempt). Concretely: capture the JSON pass-set at `HEAD^` of the rollout commit and the JSON pass-set at the rollout commit; assert `pre_pass_set − post_pass_set == ∅`.
- [ ] **AC-9:** Manifest — `.ccanvil/scripts/inject-telemetry-source.sh` declares a complete `@manifest` block (purpose, input, output, exit-codes, anchor) and `bash .ccanvil/scripts/module-manifest.sh validate --json` returns `status:"ok"` with `drift:[]`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/inject-telemetry-source.sh` | New |
| `hub/tests/inject-telemetry-source.bats` | New (unit tests for the injector) |
| `hub/tests/telemetry-coverage.bats` | New (drift-guard) |
| `hub/tests/*.bats` (~165 files) | Modified — wiring applied by injector |
| `.ccanvil/manifest-allowlist.txt` | Modified — add new scripts/tests |

## Dependencies

- **Requires:** BTS-497 (telemetry foundation, helper at `hub/tests/_helpers/telemetry.bash`) — shipped.
- **Requires:** BTS-507 (bats-report stub helper) — shipped; ensures the rollout suite runs without the ~7-min pre-warm toll.
- **Blocked by:** Nothing.

## Out of Scope

- BTS-281 pre-warm optimization for `bats-report.sh` invocations from inside test fixtures (separate ticket).
- BTS-499 Stage-2 distillation of the helper to pytest/vitest nodes.
- Per-test `test.error_excerpt` capture on failed spans (bats does not expose a structured fail-message env var; requires per-test stderr-wrap, separate ticket).
- Use of bats 1.10+ `setup_suite.bash` (Path 3 in BTS-504 body) — complementary, not a replacement; not part of this rollout.
- `bats_load_library`-based wiring (Path 2 in BTS-504 body) — rejected due to silent-override failure mode.

## Implementation Notes

- **Path 1 chosen** per BTS-504 body recommendation. Path 2 risks silent override when files define their own `setup()`; Path 3 cannot replace per-file wiring.
- **Category detection** is line-leading regex against the top of each file. The classifier evaluates 4 booleans — `has_setup_file`, `has_teardown_file`, `has_setup`, `has_teardown` — and dispatches via this truth table. The `load` directive is orthogonal to classification (the wiring action never touches `load`); BTS-504's body distinguishes Cat C from Cat D by `load` presence, but they share identical wiring and both map to Cat C here:

  | Cat | `setup_file` | `teardown_file` | `setup` | `teardown` | Wiring action |
  |-----|:---:|:---:|:---:|:---:|---|
  | **A** | no | no | no | no | Source helper + add all 4 lifecycle wrappers (`telemetry_setup_file`/`telemetry_teardown_file`/`telemetry_setup`/`telemetry_teardown`). |
  | **B** | no | no | yes | no | Append `telemetry_setup` to existing `setup`; add `setup_file`/`teardown_file`/`teardown`. |
  | **C** | no | no | yes | yes | Append `telemetry_setup` to `setup`; PREPEND `telemetry_teardown` to `teardown` (bats state vars must be pristine when read); add `setup_file`/`teardown_file`. Covers BTS-504's Cat C and Cat D — `load` directive is non-conflicting. |
  | **E** | yes | no | yes | no | Prepend `telemetry_setup_file` to `setup_file` (healthcheck before expensive init); append `telemetry_setup` to `setup`; add `teardown`/`teardown_file`. |
  | **F** | yes | yes | no | no | Source helper; add `setup`/`teardown`; prepend `telemetry_setup_file` to `setup_file`; append `telemetry_teardown_file` to `teardown_file`. |

  Any 4-tuple outside these 5 rows (e.g., `teardown_file=yes` with `setup_file=no`, or `setup_file=yes` + all other hooks present) → `UNCLASSIFIED` (AC-7). The 5 rows partition disjointly, so multi-match is structurally impossible. Reference output: `hub/tests/lifecycle-state.bats` (Cat C) and `hub/tests/canonical-fixtures.bats` (Cat A).
- **Wiring template** per category lives at the top of the injector as a documented constant; mirrors the wiring in the BTS-497 sample (e.g., `hub/tests/lifecycle-state.bats:9-12,21,25`, `hub/tests/canonical-fixtures.bats:12-17`).
- **Idempotency marker** — detect `source.*_helpers/telemetry.bash` at column 0 in the file's top 20 lines. Already-wired files short-circuit without re-parsing.
- **Drift-guard test** runs in the standard suite, so it gates every PR and `/ccanvil-pull` automatically — no separate cron needed.
- **Rollout commit** is the second commit on the feature branch (after injector + tests land green); applied by running `--all` and committing the resulting diff atomically.
- **Failure-mode preference:** `--all` is accumulate-then-exit (per AC-4): the injector iterates every non-skip-listed file, leaves UNCLASSIFIED files unmodified (per AC-7), and exits non-zero only after walking the full set. "Halt the rollout" means: with non-zero exit, the operator does NOT commit the resulting diff — corrupt files remain untouched, and the operator hand-wires the residual UNCLASSIFIED set (expected count ≤5 based on BTS-497 sample survey) before retrying.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
