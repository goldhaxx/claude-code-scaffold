---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/tdd-foundations.md
manifest:
  id: tdd
  purpose: Codify red-green-refactor TDD discipline, live-API contract gate, strict-mode bats, and run-the-suite tooling expectations for ccanvil
  input:
    - "read-only: rule consumed by Claude during /plan + implementation"
  output:
    - "behavior-shape: forces test-first cycle, halts implementation drift"
  caller:
    - .claude/commands/plan.md
    - .claude/skills/tdd/SKILL.md
  depends-on:
    - bats-report.sh
  side-effect:
    - "shapes-implementation-flow (no file mutation; behavioral influence on Claude)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=test-debt-accumulates | mitigation=stasis-evidence-gap-section"
    - "live-api-gate-skipped | exit=n/a | visible=stub-passes-then-prod-fails | mitigation=BTS-171-explicit-gate"
  contract:
    - one-failing-test-at-a-time
    - never-refactor-and-add-features-simultaneously
    - live-api-validation-before-commit-when-flagged
  anchor:
    - BTS-127 (strict-mode bats)
    - BTS-118 (bats-report.sh)
    - BTS-171 (live-API validation gate)
    - BTS-240 (reference manifest seed)
    - BTS-387 (atomized for tier-0)
---

# Test-Driven Development

**Red-Green-Refactor cycle:** write ONE failing test → minimum code to pass → refactor with all green → repeat. One acceptance criterion at a time.

**Live-API gate:** when a plan step flags contract uncertainty (phrasings like *"if the live API rejects"*, *"verify against live"*, *"exact filter shape may not work"*), run ONE live call against the risky endpoint and confirm success BEFORE committing AND BEFORE `/review`. Stubs accept any shape; only live verifies contract. Doesn't apply to pure-prose, gitignore, or doc-only diffs.

**When tests break after a change:** the change is wrong, not the tests. Fix implementation, not the test — unless the spec changed (then update test FIRST, confirm fail, then update implementation).

**Per-cycle scope:** targeted test files only — never the full suite mid-cycle. The full suite is the pre-merge gate, not a per-cycle confirmation. See `.claude/rules/test-discipline.md`.

For the expanded R-G-R rationale, BTS-115/170 incident detail, test-structure conventions, what-to-test heuristic, hooks-integration mechanism, strict-mode-bats discipline (BTS-127), `bats-report.sh` tooling reference (BTS-118/137), and test-execution discipline (BTS-383): see evidence anchor `docs/research/tdd-foundations.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
