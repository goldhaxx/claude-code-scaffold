# Feature: Test-run discipline framework — research + codify state/intent/logic gates

> Feature: bts-508-test-discipline-framework
> Work: linear:BTS-508
> Created: 1778988477
> Subject: Test-run discipline framework — research + codify state/intent/logic gates
> Status: Complete

## Summary

ccanvil's development process has NO clearly-defined gates for when test suites run; tests fire ad-hoc with zero awareness of cumulative cost or redundancy. BTS-497 session 57 burned ~2+ hours on redundant test-waits (manifest validate ran 6-8× at ~7min each; full bats suite ran 3× where 1 was load-bearing). This ship audits current invocation sites, codifies a state/intent/logic-driven framework as a project rule, and builds a `docs-check.sh test-state` substrate primitive that skills consult to skip redundant verification. Thesis (operator-locked): full suite + manifest validate run ONCE, as one of the very last steps before merge.

## Job To Be Done

**When** Claude (or a skill) is about to invoke a long-running test substrate (full bats suite, manifest validate),
**I want** a deterministic decision: is this run state/intent/logic-justified, or is it a reflexive re-verification of work nothing has changed since,
**So that** session test-wait time drops from hours to single-digit minutes without losing the load-bearing pre-merge gate.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Research lap

- [ ] **AC-1:** `docs/research/test-discipline-research.md` exists and catalogs ALL current invocation sites of `bats-report.sh`, `module-manifest.sh validate`, and `test-suite-run` across `.claude/skills/`, `.claude/commands/`, and `hub/tests/`. For each site: phase (TDD / review / commit / pr / stasis / recall), trigger (operator-explicit / skill-step), scope (touched-files / full-suite / allowlisted-files-only), and observed redundancy with neighboring sites.
- [ ] **AC-2:** Redundancy analysis section in the same doc identifies at least 3 same-gate or cross-gate overlap patterns (e.g., `/stasis` re-runs manifest validate that `/review` already ran on the same diff). Each pattern names the duplicate sites and a candidate state-key that would deduplicate (e.g., `last_manifest_validate_commit == HEAD`).
- [ ] **AC-3:** Framework definition section presents the gate table (TDD-cycle / pre-review / pre-commit / pre-merge / session-boundary / post-merge) with one column for each axis (state / intent / scope) and an explicit decision tree per gate.

### Rule file

- [ ] **AC-4:** `.claude/rules/test-discipline.md` exists, atomized per BTS-387 pattern: tier-0 universal frontmatter (`tier: 0`, `scope: universal`, `stack: any`, `anchors.evidence: [docs/research/test-discipline-research.md]`), manifest block, atom body retains the gate table + 3 anti-patterns + the SHOULD-I-RUN decision rule. Atom file ≤900 tokens (measured via `bash .ccanvil/scripts/context-budget.sh check --json`).
- [ ] **AC-5:** The rule is referenced (one-line directive or `See:` pointer) from at least: `.claude/commands/review.md`, `.claude/commands/pr.md`, `.claude/skills/stasis/SKILL.md`, and `.claude/rules/tdd.md`.

### Substrate

- [ ] **AC-6:** `bash .ccanvil/scripts/docs-check.sh test-state --project-dir .` returns a JSON envelope: `{last_full_suite_commit, last_full_suite_at, last_manifest_validate_commit, last_manifest_validate_at, files_changed_since_last_full_suite, files_changed_since_last_manifest_validate, manifest_tracked_files_changed_since_last_validate}`. Reads `.ccanvil/state/test-state.json` for persistence; computes diffs against current HEAD on the fly via `git diff --name-only <SHA>...HEAD`. Returns the empty envelope (`{}`) when no prior run is recorded.
- [ ] **AC-7:** `bats-report.sh` (on successful full-suite completion) and `module-manifest.sh validate` (on exit-0 validate) each write/update the relevant fields in `.ccanvil/state/test-state.json` (epoch + commit SHA at run-time). State file is gitignored.
- [ ] **AC-8:** `/review` (Step 0: manifest validate) consults `test-state` and skips the validate when `manifest_tracked_files_changed_since_last_validate == 0` — i.e., no allowlisted file has changed since the last successful validate, regardless of whether HEAD has advanced past the cached commit. This captures the common mid-PR case where commits churn (doc edits, test-only changes, comment fixes) but no manifest-tracked source has changed. The skip is logged on stdout (`SKIP: manifest validate — no manifest-tracked files changed since <SHA>`) so the operator sees what was skipped. **Consumer pattern:** `/review` calls `bash .ccanvil/scripts/docs-check.sh check-skip-validate --project-dir .` and parses the JSON envelope — it does NOT read `.ccanvil/state/test-state.json` directly or re-implement the diff/intersect logic. Intersection lives once, in `cmd_test_state` (function-level allowlist entries `<path>:<function>` are normalized to bare `<path>` before matching). This is the demonstration consumer; wider rewires are deferred to follow-up.

### Edge / error

- [ ] **AC-9:** When `.ccanvil/state/test-state.json` is missing OR malformed JSON, `test-state` returns the empty envelope (`{}`) without erroring, and the skill consumers default to RUNNING the verification (fail-safe — never SKIP when state is uncertain).
- [ ] **AC-10:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel`) at PR finalize. New bats coverage for `test-state` verb (≥3 tests: empty-state envelope, populated envelope, malformed-file recovery).

## Affected Files

| File | Change |
|------|--------|
| `docs/research/test-discipline-research.md` | New — audit catalog + redundancy analysis + framework + decision tree |
| `.claude/rules/test-discipline.md` | New — atomized rule (BTS-387 pattern); gate table + anti-patterns + anchors.evidence pointer |
| `.claude/commands/review.md` | Modified — Step 0 consults `test-state`; reference test-discipline.md |
| `.claude/commands/pr.md` | Modified — reference test-discipline.md (rule codifies WHY /pr is the canonical full-suite gate) |
| `.claude/skills/stasis/SKILL.md` | Modified — reference test-discipline.md (justifies why /stasis no longer reflexively re-runs manifest validate) |
| `.claude/rules/tdd.md` | Modified — one-line reference to test-discipline.md (per-cycle scope is and isn't) |
| `.ccanvil/scripts/docs-check.sh` | Modified — add `test-state` verb (cmd_test_state); state-file write helpers |
| `.ccanvil/scripts/bats-report.sh` | Modified — write `last_full_suite_*` fields on successful completion |
| `.ccanvil/scripts/module-manifest.sh` | Modified — write `last_manifest_validate_*` fields on exit-0 validate |
| `.gitignore` | Modified — add `.ccanvil/state/test-state.json` |
| `hub/tests/test-state.bats` | New — covers AC-6, AC-7, AC-9 |

## Dependencies

- **Requires:** BTS-507 merged (bats-report-stub-helper eliminates pre-warm trap that would otherwise distort the full-suite state writer's commit-SHA semantics).
- **Blocked by:** none.
- **Blocks:** real downstream-velocity work — until gates are clear, every dev cycle inherits the current 2+ hour test-wait tax.

## Out of Scope

- **Manifest-validate's own efficiency** (captured separately as BTS-498). State-tracking can skip redundant runs but doesn't make each run faster.
- **Cross-run test caching** (no parallel-test result memoization across runs, no CI cache integration).
- **Auto-skip inside the TDD inner loop.** Per-AC running is targeted-file, not full-suite; not in scope for test-state consumption.
- **Schema versioning of the state file.** Premature; empty-on-missing (AC-9) covers forward-compat.
- **Migration of every reflexive-run site.** /review is the demonstration consumer (AC-8); rewiring /stasis, /recall, and others is deferred to /plan or follow-up tickets.

## Implementation Notes

- **Atom + research-doc pattern** mirrors BTS-387 verbatim: tier-0 frontmatter + manifest block in the atom; full audit + decision tree in `docs/research/test-discipline-research.md`; atom references via `anchors.evidence`.
- **State file format** is a flat JSON object with epoch + commit SHA fields; no schema header. The empty-on-missing fail-safe (AC-9) is the forward-compat mechanism.
- **No live-API risk** — pure local-state substrate; no external contracts.
- **TDD cadence (per the rule this ship codifies):** during iteration run only `bash bats hub/tests/test-state.bats` plus any directly-touched bats. Full-suite at PR finalize per AC-10.
- **AC-8 picks `/review` as the first consumer** because it's the lowest-blast-radius skip path — already a documentation-and-review pass, and skipping the validate when nothing changed is a clean win with a clean log message.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
