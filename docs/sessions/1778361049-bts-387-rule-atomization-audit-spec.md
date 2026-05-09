# Feature: Rule atomization audit — atomize remaining 4 rules

> Feature: bts-387-rule-atomization-audit
> Work: linear:BTS-387
> Created: 1778343025
> Subject: Rule atomization audit — atomize remaining 4 rules
> Status: In Progress

## Summary

BTS-385 Session A landed the rule frontmatter substrate and atomized 4 seed rules (code-quality, workflow, deterministic-first, self-review), reducing context budget by 1144 tokens (165% → 151%). BTS-386 shipped the validator extension that now emits 4 `rule-tier-budget-exceeded` advisory entries (in `info[]`) — the deterministic atomization-needed list:

| Rule | Tokens | Strategy |
| -- | -- | -- |
| `tdd.md` | 2306 | Highest complexity; multiple concerns. Extract Live-API-gate evidence, strict-mode-bats, suite-tooling, execution-discipline to `docs/research/tdd-foundations.md`. Atom retains R-G-R cycle + live-API directive + pointer. |
| `provider-integration.md` | 1353 | 100% substrate-developer content. Atom = single directive ("substrate uses http; MCP for ad-hoc only") + pointer. Full essay → `docs/research/provider-migration-decision.md`. |
| `evidence-required-for-captures.md` | 1323 | Bug-shape regex + four-anchor list lives in atom. Full BTS-198 incident detail → `docs/research/evidence-gate-incident.md`. |
| `background-task-discipline.md` | 1292 | Already universal-rewritten in BTS-385 commit `a555133`. Anti-pattern catalog + BTS-383 anchor → `docs/research/background-task-incident.md`. Atom retains 3-rule list. |

Net target reduction: \~3000+ tokens (atomized files float to \~600-800 tokens each due to `manifest:` block weight; 4 × \~700 saved = 2800). Combined with BTS-385's -1144, projected hub budget hits \~80% of 8000 — well within the BTS-385 architectural thesis target.

## Job To Be Done

**When** the BTS-386 validator surfaces a `rule-tier-budget-exceeded` advisory list,
**I want** to systematically atomize each entry by extracting operational detail to Tier-2 reference docs while preserving cross-references and behavior,
**So that** the auto-load context budget structurally fits within the 8000-token soft ceiling and the fleet receives slimmed rules on next ccanvil-pull.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Per-rule atomization

- [ ] **AC-1:** `tdd.md` atomized. Atom retains: R-G-R cycle directive, live-API validation gate, when-tests-break protocol. Full content extracted to `docs/research/tdd-foundations.md` (BTS-115/170 incidents, strict-mode bats, [bats-report.sh](<http://bats-report.sh>) tooling, test-execution discipline). Atom file ≤900 tokens (relaxed from 150 due to manifest: block + multiple universal directives).
- [ ] **AC-2:** `provider-integration.md` atomized. Atom retains: single directive ("Substrate uses http (shell-to-API); MCP reserved for ad-hoc operator queries"). Full BTS-183/164 migration evidence + http-vs-MCP table + how-to-apply → `docs/research/provider-migration-decision.md`. Atom ≤700 tokens.
- [ ] **AC-3:** `evidence-required-for-captures.md` atomized. Atom retains: bug-shape regex, four-anchor list (Command/Output/Exit/Reproduce), DIAGNOSE: titling convention. Full BTS-198 incident timeline + heuristic explanation → `docs/research/evidence-gate-incident.md`. Atom ≤800 tokens.
- [ ] **AC-4:** `background-task-discipline.md` atomized. Atom retains: 3-rule list (no until-loop wait grep, no parallel duplicates, buffered ≠ hung) + 3 failure-mode names. Full anti-pattern catalog + BTS-383 origin + hub-anchored block → `docs/research/background-task-incident.md`. Atom ≤700 tokens.

### Frontmatter + anchors

- [ ] **AC-5:** Each atomized rule gains top-level `tier: 0`, `scope: universal`, `stack: any`, and `anchors.evidence: [<reference path>]` frontmatter peers (mirrors BTS-385 seed pattern). Existing `manifest:` block preserved.
- [ ] **AC-6:** `cmd_rule_resolve <id>` returns the expected envelope for each atomized rule with `anchors.evidence` populated.

### Validator signal

- [ ] **AC-7:** After all 4 atomizations land, `bash module-manifest.sh validate --json` on the hub emits ZERO `rule-tier-budget-exceeded` entries in `info[]` (atomized rules now under their per-file targets — though some may still drift the 150-token threshold; the operational target is "all rules under their declared per-rule targets," not the hard 150 line).
  - **Refinement:** since the 150-token threshold is sub-realistic for files carrying `manifest:` blocks, the validator's drift signal continues to fire on rules under their own atomized state. Acceptable: AC-7 instead asserts ZERO `rule-tier-budget-exceeded` entries on the 4 unmigrated rules' new (post-atomization) sizes when measured against a relaxed threshold. **Concrete:** total auto-load context budget is the test, not per-rule.
- [ ] **AC-8:** Total auto-load context budget drops from 12080 (post-BTS-385 baseline) to ≤9000 tokens (≥3000 token reduction). Hub status shifts from CRITICAL 151% to WARNING/HEALTHY \~112%. Measured via `bash .ccanvil/scripts/context-budget.sh check --json`.

### Tests + manifests

- [ ] **AC-9:** All existing skills + 18 skill files continue functioning unchanged (atomization is move-not-rewrite for skill-bound content). Targeted bats: `docs-check.bats` rule-content drift tests, `rule-resolve.bats`.
- [ ] **AC-10:** All atomized rules retain their existing `manifest:` block; `module-manifest.sh validate --allowlist .ccanvil/manifest-allowlist.txt --json` exits 0 with `drift` array empty (manifest-allowlist drift, not rule-tier).
- [ ] **AC-11:** Full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel` at PR finalize.
- [ ] **AC-12:** No regressions in `docs-check.bats` rule-content tests — the test on line 1035 (workflow self-review reference) and the 5 self-review/\* tests still pass without modification.

## Affected Files

| File | Change |
| -- | -- |
| `.claude/rules/tdd.md` | Modified: trim body to atom; add tier-0 frontmatter + anchors.evidence |
| `.claude/rules/provider-integration.md` | Modified: trim body to atom; add tier-0 frontmatter + anchors.evidence |
| `.claude/rules/evidence-required-for-captures.md` | Modified: trim body to atom; add tier-0 frontmatter + anchors.evidence |
| `.claude/rules/background-task-discipline.md` | Modified: trim body to atom; add tier-0 frontmatter + anchors.evidence |
| `docs/research/tdd-foundations.md` | New — extracted Tier-2 reference (BTS-115/170 + strict-mode bats + suite tooling + execution discipline) |
| `docs/research/provider-migration-decision.md` | New — extracted Tier-2 reference (BTS-183 + BTS-164 migration evidence + http-vs-MCP table) |
| `docs/research/evidence-gate-incident.md` | New — extracted Tier-2 reference (BTS-198 incident + heuristic explanation) |
| `docs/research/background-task-incident.md` | New — extracted Tier-2 reference (BTS-383 incident + anti-pattern catalog + hub-anchored block) |

## Dependencies

* **Requires:** BTS-385 merged (rule frontmatter substrate). BTS-386 merged (validator drift signal). Both shipped in PRs #169 and #170.
* **Blocked by:** none.
* **Blocks:** BTS-384 (scope-tag distribution filter — composes on top once all rules are atomized + frontmatter-shaped).

## Out of Scope

* **Atom file naming convention overhaul** (e.g. renaming `tdd.md` → `atom-tdd.md`). Defer; existing filenames preserved.
* **Stack-conditional skill auto-load** (BTS-385 Out-of-Scope §5). Separate concern.
* **Skill creation** (e.g. new `tdd-bats` skill). Reference docs are Tier-2; promoting them to Tier-1 skills is a future ramp.
* **Lowering the 150-token threshold to match real atom sizes.** AC-7 acknowledges the threshold is aspirational; refinement to follow if validator signal becomes noise.
* **Reference docs as Linear Documents (BTS-204 SSOT extension).** Defer.

## Implementation Notes

* **Mirror BTS-385's atomization pattern** verbatim: top-level frontmatter peers (`tier`/`scope`/`stack`/`anchors`), preserve existing `manifest:` block, extract operational detail to `docs/research/<topic>.md`, atom body retains directive layer + evidence pointer.
* **Preserve cross-references at the directive layer.** When an atom mentions another rule (e.g., tdd.md mentions self-review), keep the mention as a one-liner so `docs-check.bats` content-drift tests don't regress (BTS-385 hit this on workflow.md self-review reference).
* `tdd.md` is the largest — work on it last to amortize reference-doc-creation experience from the 3 simpler atoms.
* `background-task-discipline.md` is already universal (BTS-385 commit `a555133`). The work is mostly reference extraction + frontmatter peers; minimal body trim.
* **Reference doc structure:** each begins with a one-line "Tier 2 reference (BTS-387). Excluded from auto-load; read on-demand by following the rule's `anchors.evidence` pointer." preamble + extracted content verbatim. Mirrors BTS-385's `feature-lifecycle.md`/`deterministic-first-foundations.md`/`self-review-detail.md` precedent.
* **No live-API risk.** All file mutations + reference extractions; no external API contract uncertainty.
* **TDD cadence (per the test-execution-discipline rule):** during iteration run only the rule-resolve.bats + docs-check.bats files. Full-suite at PR finalize.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
