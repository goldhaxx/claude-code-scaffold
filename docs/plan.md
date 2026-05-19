# Implementation Plan: Wire telemetry helper into all hub/tests/*.bats

> Feature: bts-504-wire-telemetry-into-all-bats
> Work: linear:BTS-504
> Created: 1779220275
> Spec hash: 4ec89125
> Based on: docs/spec.md

## Objective

Ship `.ccanvil/scripts/inject-telemetry-source.sh` (deterministic, idempotent, category-dispatched), its drift-guard companion test, and the bulk rollout commit that wires the remaining ~165 `hub/tests/*.bats` files into the BTS-497 telemetry pipeline — taking suite coverage from ~7% → ~100%.

## Sequence

Each step is one red-green-refactor cycle. Categories A/B/C/E/F refer to the truth table in `docs/spec.md` Implementation Notes.

### Step 1: Skeleton script + manifest (AC-9)
- **Test:** `bats hub/tests/inject-telemetry-source.bats` asserts the script exists, is executable, and `--help` prints the supported invocation forms.
- **Implement:** Create `.ccanvil/scripts/inject-telemetry-source.sh` with @manifest block (purpose, input, output, exit-codes, anchor), `set -euo pipefail`, dispatch shell on `--help`/`--all`/`<file>`. Add to `.ccanvil/manifest-allowlist.txt`.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh` (new), `hub/tests/inject-telemetry-source.bats` (new), `.ccanvil/manifest-allowlist.txt`.
- **Verify:** Targeted bats run green. `bash .ccanvil/scripts/module-manifest.sh validate --json` returns `status:"ok"` drift `[]`.

### Step 2: Classifier — boolean detection + category dispatch (AC-3)
- **Test:** Fixture-driven cases per category. Given fixture files matching each row of the spec's truth table, `inject-telemetry-source.sh classify <fixture>` returns the expected letter; mismatched combinations return `UNCLASSIFIED`; skip-listed files return `SKIP`.
- **Implement:** Add `_classify()` function: line-leading regex sweep of top 40 lines for `^(setup_file|teardown_file|setup|teardown)\s*\(\s*\)`; produce 4-tuple; dispatch via case statement matching the 5 supported rows; default = `UNCLASSIFIED`.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`; `hub/tests/fixtures/inject-telemetry/cat-{a,b,c,e,f,unclassified}.bats`.
- **Verify:** All classify-tests green.

### Step 3: Wiring action for Cat A (AC-1 partial)
- **Test:** Given a Cat-A fixture (no hooks), `inject-telemetry-source.sh <file>` rewrites it to include the source line + all 4 telemetry wrapper functions in the expected order; line-anchored grep confirms each.
- **Implement:** Add `_wire_cat_a()` that emits the BTS-497-template block after the last `bats_require_minimum_version` line (or after the shebang if absent).
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`.
- **Verify:** Cat-A test green. Diff vs `hub/tests/canonical-fixtures.bats` (reference Cat-A) matches the wiring shape.

### Step 4: Wiring actions for Cat B, C, E, F (AC-1 full)
- **Test:** One test per category. For Cat B/C: assert `telemetry_setup` appears AFTER existing setup body; for Cat C: assert `telemetry_teardown` appears BEFORE existing teardown body (PREPEND); for Cat E: assert `telemetry_setup_file` appears BEFORE existing setup_file body; for Cat F: assert prepend on setup_file + append on teardown_file. Each verified via line-anchored regex, not bare presence-grep.
- **Implement:** `_wire_cat_b()`, `_wire_cat_c()`, `_wire_cat_e()`, `_wire_cat_f()` — each uses sed/awk to surgically inject inside the existing function body (append before `}`, prepend after `{`) or appends a fresh function declaration when adding.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`.
- **Verify:** All Cat A/B/C/E/F wiring tests green. Diff against `hub/tests/lifecycle-state.bats` (reference Cat-C) matches.

### Step 5: Idempotency (AC-2)
- **Test:** Given an already-wired Cat-A fixture, running the injector returns exit 0 AND `diff before after` shows no changes.
- **Implement:** Early-return when `grep -q '^source.*_helpers/telemetry\.bash"' <file>` matches in the top 20 lines.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`.
- **Verify:** Idempotency test green; re-running on the wired Cat-A fixture produces byte-identical output.

### Step 6: UNCLASSIFIED error path (AC-7)
- **Test:** Given a fixture with `setup_file()` + `teardown_file()` + `setup()` + `teardown()` all present (no supported row matches), the injector exits non-zero, prints `UNCLASSIFIED: <file>: <reason>` to stderr, and leaves the file unmodified (sha256 unchanged).
- **Implement:** UNCLASSIFIED branch in classifier dispatches to a stderr-emit-and-exit-3 path; never mutates the file.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`; `hub/tests/fixtures/inject-telemetry/all-hooks-unclassified.bats`.
- **Verify:** Error-path test green.

### Step 7: Bulk `--all` + skip-list + JSON report (AC-4, AC-5)
- **Test:** Stand up a tmp dir with mixed-category fixtures + one skip-listed file. Running `inject-telemetry-source.sh --all --root <tmpdir>` returns a JSON report counting `wired/already_wired/skipped/unclassified`, exits 0 iff `unclassified == 0`. With an UNCLASSIFIED file present, exits non-zero AND every other file is still wired (accumulate-then-exit per spec).
- **Implement:** `--all` loop iterates `*.bats`, accumulates counts, honors a top-of-file `SKIP_LIST=( ... )` array. Each skip entry carries a `# <rationale>` inline comment in the script source. JSON via `jq -n`.
- **Files:** `.ccanvil/scripts/inject-telemetry-source.sh`; `hub/tests/inject-telemetry-source.bats`.
- **Verify:** Bulk + skip-list tests green.

### Step 8: Drift-guard companion test (AC-6)
- **Test:** Write `hub/tests/telemetry-coverage.bats` — iterates `hub/tests/*.bats` (minus skip-list, sourced from the injector script via `bash inject-telemetry-source.sh print-skip-list`), asserts each file contains the wiring marker. Initially FAILS (165 unwired). One test per coverage assertion.
- **Implement:** Add `print-skip-list` subcommand to the injector (single source of truth); drift-guard reads from it.
- **Files:** `hub/tests/telemetry-coverage.bats` (new); `.ccanvil/scripts/inject-telemetry-source.sh` (add subcommand).
- **Verify:** Drift-guard test FAILS pre-rollout (expected). This is the red side of the cycle; green comes after Step 9.

### Step 9: Rollout commit + AC-8 pass-set diff (AC-4, AC-6, AC-8)
- **Test (live-API equivalent — pre/post bats run):** Capture pre-rollout pass-set: `bash .ccanvil/scripts/bats-report.sh --parallel --no-telemetry --json > /tmp/pre.json`. Run `bash .ccanvil/scripts/inject-telemetry-source.sh --all` against `hub/tests/`. Commit the diff atomically. Capture post-rollout pass-set: same command → `/tmp/post.json`. Assert `pre_pass_set − post_pass_set == ∅` via jq diff.
- **Implement:** Execute the rollout. Commit message: `feat(bts-504-wire-telemetry-into-all-bats): apply injector to ~165 hub/tests/*.bats`. NOTE: this step's "implementation" is operator-driven execution of the substrate, not code authoring.
- **Files:** `hub/tests/*.bats` (~165 modified). Possibly small residual UNCLASSIFIED list that gets hand-wired in a fixup commit.
- **Verify:** Drift-guard (Step 8) now GREEN. AC-8 pass-set diff is `∅`. Manifest validate still clean.

### Step 10: Documentation update (preset infrastructure changed)
- **Test:** None — pure docs.
- **Implement:** Add `inject-telemetry-source.sh` row to `.ccanvil/guide/command-reference.md` under "Substrate Scripts" (or equivalent). One-line entry per format. Update `CLAUDE.md` Commands section if appropriate.
- **Files:** `.ccanvil/guide/command-reference.md`; possibly `CLAUDE.md`.
- **Verify:** Diff reads cleanly; no broken refs.

## Risks

- **Sed/awk regex fragility across 165 files.** Mitigation: line-anchored regex with explicit bats-syntax patterns; Step 6's UNCLASSIFIED branch is the fail-safe so unknown shapes halt the rollout rather than corrupt. Expected residual ≤5 files needing hand-wiring.
- **Cat E ambiguity in the wild.** Step 4's Cat-E test may not cover all `setup_file + setup + no teardown` permutations the codebase actually has. Mitigation: Step 7 surfaces UNCLASSIFIED in the JSON report before any commit; operator inspects.
- **AC-8 baseline drift.** Capturing `pre.json` requires the bats suite to be GREEN at `HEAD^` of the rollout commit. If Step 8's drift-guard accidentally lands in the same commit as the rollout, the baseline includes a failing test. Mitigation: Step 8 commits the drift-guard ON ITS OWN (failing-red); Step 9's rollout commit makes it green. Two separate commits, two separate baselines.
- **No live-API risk.** The injector is pure bash/regex — no external calls, no contract uncertainty.

## Definition of Done

- [ ] All acceptance criteria from spec pass (AC-1 through AC-9).
- [ ] Full bats suite green: `bash .ccanvil/scripts/bats-report.sh --parallel --no-telemetry` exit 0.
- [ ] Manifest validate clean: `bash .ccanvil/scripts/module-manifest.sh validate --json` returns `status:"ok"` drift `[]`.
- [ ] AC-8 pass-set diff is `∅` (no pre-rollout test regressed).
- [ ] `/review` run; substrate findings addressed.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
