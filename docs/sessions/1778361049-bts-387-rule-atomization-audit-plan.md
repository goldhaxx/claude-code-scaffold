# Implementation Plan: Rule atomization audit

> Feature: bts-387-rule-atomization-audit
> Work: linear:BTS-387
> Created: 1778343200
> Spec hash: c9e7c8b4
> Based on: docs/spec.md

## Objective

Atomize the 4 remaining unmigrated rules (background-task-discipline, provider-integration, evidence-required-for-captures, tdd) by extracting operational detail to Tier-2 reference docs and trimming bodies to directive layer + evidence pointer. Mirrors BTS-385's seed atomization pattern verbatim. Net target: ≥3000 token reduction (12080 → ≤9000), hub status CRITICAL → WARNING/HEALTHY.

## Sequence

Each step is one logical atomization unit. Per BTS-383 test-execution-discipline: targeted bats during iteration; full-suite at PR finalize.

### Step 1: `background-task-discipline.md` (smallest delta — already universal-rewritten)

* **Test:** verify `cmd_rule_resolve background-task-discipline` returns envelope with `anchors.evidence: ["docs/research/background-task-incident.md"]`. Reference doc exists with extracted content. Manifest extract still resolves the existing manifest: block.
* **Implement:** extract anti-pattern catalog + BTS-383 origin incident + hub-anchored block to `docs/research/background-task-incident.md`. Add tier-0 frontmatter peers (`tier`, `scope`, `stack`, `anchors.evidence`). Trim atom body to: 3-rule list + 3 failure-mode names + pointer.
* **Files:** `.claude/rules/background-task-discipline.md`, `docs/research/background-task-incident.md` (new).
* **Verify:** smoke-test `bash docs-check.sh rule-resolve background-task-discipline | jq '.anchors.evidence[0]'` returns the reference path.

### Step 2: `provider-integration.md`

* **Test:** smoke-test rule-resolve envelope.
* **Implement:** extract full BTS-183 + BTS-164 migration evidence + http-vs-MCP table + how-to-apply to `docs/research/provider-migration-decision.md`. Add tier-0 frontmatter. Trim atom body to: single directive ("Substrate uses http (shell-to-API); MCP reserved for ad-hoc operator queries inside interactive sessions") + pointer.
* **Files:** `.claude/rules/provider-integration.md`, `docs/research/provider-migration-decision.md` (new).
* **Verify:** smoke-test rule-resolve.

### Step 3: `evidence-required-for-captures.md`

* **Test:** smoke-test rule-resolve envelope.
* **Implement:** extract full BTS-198 incident timeline + heuristic explanation + idea-skill protocol detail to `docs/research/evidence-gate-incident.md`. Add tier-0 frontmatter. Trim atom body to: bug-shape regex + four-anchor list (Command/Output/Exit/Reproduce) + DIAGNOSE: titling convention + pointer.
* **Files:** `.claude/rules/evidence-required-for-captures.md`, `docs/research/evidence-gate-incident.md` (new).
* **Verify:** smoke-test rule-resolve.

### Step 4: `tdd.md` (largest — multiple concerns)

* **Test:** smoke-test rule-resolve envelope. Verify `docs-check.bats` content-drift tests on tdd still pass (test names mentioning "tdd" or strict-mode-bats).
* **Implement:** extract to `docs/research/tdd-foundations.md`: BTS-115/170 incident detail + Test Structure conventions + What-to-Test heuristic + When-Tests-Break protocol + Hooks Integration note + Strict-mode-bats subsection (BTS-127) + Running-the-suite tooling (BTS-118/137) + Test-execution-discipline (BTS-383). Add tier-0 frontmatter peers. Atom retains: R-G-R cycle directive, Live-API validation gate, when-tests-break (1 sentence), pointer.
* **Files:** `.claude/rules/tdd.md`, `docs/research/tdd-foundations.md` (new).
* **Verify:** smoke-test rule-resolve. Run `bats hub/tests/docs-check.bats hub/tests/rule-resolve.bats` to catch any content-drift regressions.

### Step 5: Final validation

* **Test:** `bash .ccanvil/scripts/context-budget.sh check --json | jq '.total_tokens'` returns ≤9000 (≥3000 reduction from 12080 baseline).
* **Implement:** observation only. If reduction falls short, identify which atom didn't trim sufficiently.
* **Files:** none.
* **Verify:** numeric assertion holds. AC-8 satisfied.

### Step 6: Update preset documentation

* **Test:** none (documentation step).
* **Implement:** if `.ccanvil/guide/configuration.md` Rules subsection lists per-rule key behaviors, the table doesn't need updating — directives stay; only operational detail moved. Verify the table still reflects atom directives accurately.
* **Files:** `.ccanvil/guide/configuration.md` (modify only if drift detected).
* **Verify:** docs read cleanly.

## Risks

* **Atomization losing nuance.** Atom must preserve meaning, not rewrite. Mitigation: extract content verbatim to reference doc; atom carries the directive + pointer. Same approach as BTS-385's 4 seed atoms.
* **Content-drift test regressions in** `docs-check.bats`. Tests grep specific phrases in rule files. Mitigation: each step verifies relevant tests still pass; preserve key directive phrasings (e.g., tdd.md must still mention "Red-Green-Refactor", "Live-API gate"; evidence-required must still mention "DIAGNOSE:" titling).
* `tdd.md` is bigger than other 3 combined. Higher cognitive load. Mitigation: do it last (Step 4) after pattern is amortized across simpler atoms.
* `manifest:` block weight floor. Each atomized file still \~600-700 tokens due to manifest block. Acceptable per BTS-385 §10 open question; will be addressed in future Tier-2 manifest substrate iteration.
* **No live-API risk.** All file mutations + reference extractions; no external API contract uncertainty.

## Definition of Done

- [ ] All 12 acceptance criteria from `docs/spec.md` pass.
- [ ] Targeted bats (`hub/tests/rule-resolve.bats`, `hub/tests/docs-check.bats`) pass during iteration.
- [ ] Full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel` at PR finalize.
- [ ] `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0 with `drift` array empty (manifest-allowlist drift).
- [ ] `info[].rule-tier-budget-exceeded` count drops or stays flat (concrete: per AC-8, total auto-load tokens drop ≥3000).
- [ ] Code reviewed via the review skill.
