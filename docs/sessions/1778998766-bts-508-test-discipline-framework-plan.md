# Implementation Plan: Test-run discipline framework — research + codify state/intent/logic gates

> Feature: bts-508-test-discipline-framework
> Work: linear:BTS-508
> Created: 1778988800
> Spec hash: 4ea9c296
> Based on: docs/spec.md

## Objective

Land an audit + framework codification + state-tracking substrate in 7 TDD cycles, so that ccanvil skills can deterministically skip redundant test runs (manifest validate / full bats suite) when nothing on the relevant axis has changed since the last run.

## Sequence

### Step 1: Research doc — audit catalog (AC-1)

* **Test:** `hub/tests/test-discipline-doc.bats` — structural grep against `docs/research/test-discipline-research.md`. Verify the doc exists and the Audit table has rows for every grep-discoverable invocation site of `bats-report.sh`, `module-manifest.sh validate`, and `test-suite-run` under `.claude/` and `hub/tests/` (one row per site; columns: phase / trigger / scope / observed-redundancy). The test enumerates expected rows from a one-shot grep at test time and asserts each appears in the doc.
* **Implement:** Create the research doc skeleton (Title, Audit, Redundancy Analysis, Framework, Decision Tree, Anti-Patterns sections). Fill ONLY the Audit table — run `grep -rEn 'bats-report\.sh|module-manifest\.sh validate|test-suite-run' .claude/ hub/tests/` and catalog each hit.
* **Files:** `docs/research/test-discipline-research.md` (NEW), `hub/tests/test-discipline-doc.bats` (NEW)
* **Verify:** RED → GREEN on the new bats file; full structural test passes; no full-suite run yet.

### Step 2: Research doc — redundancy + framework + decision tree (AC-2, AC-3)

* **Test:** Extend `hub/tests/test-discipline-doc.bats` — assert (a) Redundancy Analysis section contains ≥3 numbered overlap patterns, each naming the duplicate sites + a candidate state-key; (b) Framework section contains the gate table with all 6 phases (TDD-cycle / pre-review / pre-commit / pre-merge / session-boundary / post-merge) and 3 columns (state / intent / scope); (c) Decision Tree section has one tree per gate.
* **Implement:** Fill the Redundancy Analysis + Framework + Decision Tree sections of the research doc based on the audit catalog from Step 1.
* **Files:** `docs/research/test-discipline-research.md` (extend), `hub/tests/test-discipline-doc.bats` (extend)
* **Verify:** RED → GREEN; targeted bats run on the doc-validation file only.

### Step 3: `test-state` verb + edge cases (AC-6, AC-9)

* **Test:** `hub/tests/test-state.bats` (NEW) — 4 @tests: (a) returns `{}` when no state file exists; (b) returns `{}` when state file is malformed JSON; (c) returns the full 7-field envelope when state file is populated; (d) `manifest_tracked_files_changed_since_last_validate` correctly intersects `git diff --name-only` output with `.ccanvil/manifest-allowlist.txt` glob entries.
* **Implement:** Add `cmd_test_state()` to `.ccanvil/scripts/docs-check.sh`. Read `.ccanvil/state/test-state.json` (default `{}`); when populated, call `git diff --name-only <SHA>...HEAD` for both full-suite and manifest-validate SHAs and emit the 7-field envelope. Allowlist-intersection helper uses `.ccanvil/manifest-allowlist.txt`. Fail-safe: any read/parse error returns `{}` and never aborts.
* **Files:** `.ccanvil/scripts/docs-check.sh` (extend with `cmd_test_state` + dispatch case), `hub/tests/test-state.bats` (NEW)
* **Verify:** RED → GREEN; targeted bats run on `test-state.bats`.

### Step 4: State writers in [bats-report.sh](<http://bats-report.sh>) + [module-manifest.sh](<http://module-manifest.sh>) (AC-7)

* **Test:** Extend `hub/tests/test-state.bats` with 2 @tests: (a) after a successful `bats-report.sh --parallel` invocation on a tiny fixture suite (gated by an env var indicating "this counts as a full-suite run"), `.ccanvil/state/test-state.json` contains `last_full_suite_at` (epoch) and `last_full_suite_commit` (SHA matching `git rev-parse HEAD`); (b) after a successful `module-manifest.sh validate`, the file contains `last_manifest_validate_at` and `last_manifest_validate_commit`. Use a `BATS_REPORT_STATE_DIR` / `MANIFEST_STATE_DIR` override (mirrors the BTS-277 `BATS_REPORT_STATE_DIR` pattern already in place) to keep tests sandboxed from the real state file.
* **Implement:** In `bats-report.sh`, on successful EXIT (non-error path) AND when invoked as the canonical full-suite (see R1), append/merge the two `last_full_suite_*` fields into the state file using `jq`. In `module-manifest.sh validate`, on exit-0, do the same for the two `last_manifest_validate_*` fields. Both writes use `jq -n --slurpfile prior ...` to be atomic-by-replace and preserve the other substrate's fields.
* **Files:** `.ccanvil/scripts/bats-report.sh` (modify), `.ccanvil/scripts/module-manifest.sh` (modify), `hub/tests/test-state.bats` (extend)
* **Verify:** RED → GREEN; targeted bats run; spot-check the produced JSON shape.

### Step 5: `/review` consumer + skip logic (AC-8)

* **Test:** `hub/tests/review-skip-validate.bats` (NEW) — 3 @tests: (a) when state-file empty/missing, the skip-check produces no SKIP and proceeds to run validate (fail-safe per AC-9); (b) when state file's `last_manifest_validate_commit == HEAD` AND `manifest_tracked_files_changed_since_last_validate == 0`, the skip-check emits the SKIP line on stdout AND does NOT invoke `module-manifest.sh validate`; (c) when SHAs match but manifest-tracked files changed, the skip is bypassed and validate runs.
* **Implement:** Add a tiny substrate helper (`cmd_check_skip_validate` or `docs-check.sh check-skip-validate`) so the bats tests can exercise the same decision logic the command runs. Then modify `.claude/commands/review.md` Step 0 to call that helper, parse its decision, and emit the SKIP line on stdout when the skip condition holds; otherwise proceed to the existing validate.
* **Files:** `.claude/commands/review.md` (modify), `.ccanvil/scripts/docs-check.sh` (extend with `cmd_check_skip_validate`), `hub/tests/review-skip-validate.bats` (NEW)
* **Verify:** RED → GREEN; targeted bats run.

### Step 6: Rule file + references (AC-4, AC-5)

* **Test:** `hub/tests/test-discipline-rule.bats` (NEW) — 4 @tests: (a) `.claude/rules/test-discipline.md` exists and contains the BTS-387 tier-0 frontmatter (`tier: 0`, `scope: universal`, `stack: any`, `anchors.evidence: [docs/research/test-discipline-research.md]`); (b) atom file token-count ≤ 900 via `bash .ccanvil/scripts/context-budget.sh check --json | jq` against the rule file; (c) `manifest:` block present and the manifest validator accepts the file; (d) each of `.claude/commands/review.md`, `.claude/commands/pr.md`, `.claude/skills/stasis/SKILL.md`, `.claude/rules/tdd.md` contains a `test-discipline.md` literal reference.
* **Implement:** Write the atomized rule body (gate table + 3 anti-patterns + SHOULD-I-RUN decision rule). Add `manifest:` block. Add one-line `See: .claude/rules/test-discipline.md` (or directive) to each of the 4 referencing files.
* **Files:** `.claude/rules/test-discipline.md` (NEW), `.claude/commands/review.md` (one-line edit), `.claude/commands/pr.md` (one-line edit), `.claude/skills/stasis/SKILL.md` (one-line edit), `.claude/rules/tdd.md` (one-line edit), `hub/tests/test-discipline-rule.bats` (NEW)
* **Verify:** RED → GREEN; targeted bats run; `bash .ccanvil/scripts/context-budget.sh check` confirms hub budget didn't regress.

### Step 7: Manifest allowlist + .gitignore + guide updates + full-suite verification (AC-10)

* **Test:** Manifest validation passes (`bash .ccanvil/scripts/module-manifest.sh validate --json | jq -e '.status == "ok"'`); full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel`. This is the single load-bearing full-suite run for the ship (per the rule the ship codifies).
* **Implement:** Add `.ccanvil/state/test-state.json` to `.gitignore`. Add the new rule + research doc + any new substrate to `.ccanvil/manifest-allowlist.txt` (if Layer 2 covers them). Update the relevant `.ccanvil/guide/` section file with a one-line entry for `test-discipline.md` under the rules catalog. Update CLAUDE.md hub-managed Commands block IF a new command verb was added (none here — only sub-verbs on `docs-check.sh`).
* **Files:** `.gitignore`, `.ccanvil/manifest-allowlist.txt`, `.ccanvil/guide/<relevant>.md`
* **Verify:** Single full-suite run at the end of this step; manifest validate exit 0; no drift.

## Risks

* **R1 — **[**bats-report.sh**](<http://bats-report.sh>)** state writer fires during the BTS-507 stub-helper flow.** The stub helper bypasses the BTS-281 pre-warm by exporting `BTS_MANIFEST_VALIDATE_CACHE`. If the writer unconditionally writes on every [bats-report.sh](<http://bats-report.sh>) exit, the stub's tiny fixture suites will pollute the real state file. **Mitigation:** writer fires only when [bats-report.sh](<http://bats-report.sh>) is invoked on the canonical full-suite (gate on an env var like `BTS_REPORT_FULL_SUITE=1` set by docs-check's `test-suite-run` dispatcher, OR detect by the file argument set covering the whole `hub/tests/` directory). Single-file invocations skip the writer.
* **R2 — **[**module-manifest.sh**](<http://module-manifest.sh>)** validate is on the BTS-498 hot path.** Adding a writer in the post-exit hook adds \~50ms; acceptable but verify it doesn't compound with the existing \~7min wall.
* **R3 — Skip logic fires on a stale state file from a different branch.** Mitigation: commit-SHA check IS the cross-branch guard — `last_manifest_validate_commit == HEAD` fails immediately when HEAD differs from the recorded SHA. Edge case: rebased branches with the same content but different SHA correctly re-validate (no false-skip).
* **R4 — Concurrent-edit on Linear plan/spec Documents during /review or /pr.** Same race we already navigate; no new exposure.

## Definition of Done

- [ ] All 10 acceptance criteria pass
- [ ] All existing tests still pass (single full-suite run at Step 7)
- [ ] Manifest validate exit 0, drift 0
- [ ] Code reviewed via /review
- [ ] Linear Document spec + plan reflect any mid-impl tighten/scope-up
