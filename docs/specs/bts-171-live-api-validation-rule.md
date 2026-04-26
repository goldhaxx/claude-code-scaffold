# Feature: Encode live-API validation rule in tdd.md + /plan skill

> Feature: bts-171-live-api-validation-rule
> Work: linear:BTS-171
> Created: 1777173845
> Status: Complete

## Summary

Plans frequently flag live-API contract risks ("if the live API rejects this shape, adjust"; "the exact filter syntax may not work"; "verify against live before committing"). Implementations have repeatedly relied on stub-only test coverage and committed without live-validating, leading to a 2× cycle: stub-pass → commit → /review-flags → live-test-fails → fix → recommit. Two prior incidents (BTS-115 dual-capture, BTS-170 filter shape) and one near-miss in the same day (BTS-150 — successfully live-validated only because a fresh auto-memory existed) confirm the pattern. Promote the auto-memory into substrate: amend `.claude/rules/tdd.md` with an explicit "live-API validation gate" subsection and update the `/plan` skill prose to require risky-API plan steps to enumerate the live command that proves the contract.

## Job To Be Done

**When** I write a plan step that flags a live-API contract risk (or read a plan that does so),
**I want** the substrate (rules + plan-skill prose) to require an explicit live-validation gate before commit at that step,
**So that** the "stub-pass → commit → /review-flags → live-test-fails" cycle is structurally avoided rather than relying on the implementer remembering an auto-memory that may or may not be in scope.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.claude/rules/tdd.md` contains a new section (heading literally `## Live-API validation gate` or `## Plan-flagged live-API risks`) that states explicitly: when a plan step contains language implying live-API contract uncertainty, the implementation MUST run one live call against the risky endpoint and verify success BEFORE committing — and BEFORE running `/review`. The section names the recurring incident class with at least two prior-incident references (BTS-115 and BTS-170 are sufficient anchors).
- [ ] **AC-2:** `.claude/skills/plan/SKILL.md` (the `/plan` skill source-of-truth) is amended so its rules / instructions section requires plans to include an explicit "Live-API validation" callout under the "Risks" section (or as a dedicated step) when any plan step contains risk-language matching: `live API`, `live endpoint`, `exact filter shape`, `may not work`, `if the live API rejects`, `verify against live`, or equivalent phrasings. The skill prose tells the implementer to run the validation BEFORE marking the plan step complete.
- [ ] **AC-3:** `.claude/rules/self-review.md` (or `tdd.md`'s self-review section) adds one bullet to the "When to Flag" determinism-review checklist that explicitly mentions the live-API validation gap as a candidate-class, so future stasis self-reviews surface this pattern when it recurs.
- [ ] **AC-4:** Drift-guard test: a bats test in `hub/tests/` (new file or addition to existing rule-content tests) asserts that `.claude/rules/tdd.md` contains the literal token `live-API` (or the chosen heading wording) AND references at least one BTS-XXX prior-incident anchor. This prevents silent removal of the rule by future hub edits.
- [ ] **AC-5:** Hub guide cross-reference: `.ccanvil/guide/index.md` or the relevant section file (`core-workflow.md` or `decision-guide.md`) is updated to mention the live-API validation gate as part of the TDD discipline. One sentence is sufficient — full prose lives in `tdd.md`.
- [ ] **AC-6:** Idempotency: re-running the documentation update (e.g., a downstream `ccanvil-sync.sh pull`) doesn't double-add the section. The new section uses a stable heading anchor and is bracketed in the hub-managed portion of `tdd.md` (above the `<!-- NODE-SPECIFIC-START -->` marker).

## Affected Files

| File | Change |
|------|--------|
| `.claude/rules/tdd.md` | Modified — new `## Live-API validation gate` section appended to hub-managed portion |
| `.claude/skills/plan/SKILL.md` | Modified — risk-language instruction added to skill prose |
| `.claude/rules/self-review.md` | Modified — one bullet added to determinism-review flag checklist |
| `hub/tests/live-api-validation-rule.bats` (or addition to existing) | New/Modified — drift-guard test for tdd.md content |
| `.ccanvil/guide/core-workflow.md` (or `index.md`) | Modified — one-sentence cross-reference |

## Dependencies

- **Requires:** `.claude/rules/tdd.md` and `.claude/skills/plan/SKILL.md` exist (they do).
- **Blocked by:** none.

## Out of Scope

- **Automated regex-scan of plans for risk-language.** A pre-commit hook that scans `docs/plan.md` for phrases like "live API may reject" and blocks commit until a corresponding validation step exists is too brittle (false-positives on prose narrative) and adds friction not yet justified by the incident rate. The rule + skill-prose update is the proportionate response. If the pattern surfaces a fourth time after this ship, revisit and consider mechanizing.
- **Generic "all API calls require live validation" rule.** Most API calls are on well-stabilized contracts (e.g., `git`, `gh`, internal scripts). Only plan-flagged uncertain contracts get the gate. The rule is precision-targeted, not blanket.
- **Retroactive auditing of past plans.** Existing `docs/specs/*.md` archives stay as-is. The rule applies to plans written after this ship.
- **Updating downstream nodes' plans/specs.** Downstream propagation rides `ccanvil-sync.sh pull` on each node's own cadence.

## Implementation Notes

- **Section placement in `tdd.md`.** Insert the new section between the existing "Hooks Integration" and "Strict-mode bats tests" sections, OR after the Red-Green-Refactor cycle (reader should find it before reaching the strict-mode bats discussion since live-API validation is more foundational). Either is fine; pick the spot where the rule reads naturally in flow.
- **Skill prose update.** The `/plan` skill currently doesn't have a risk-language instruction. Add a new bullet under the existing "Steps" section (or in a new "When writing risk language" subsection). Keep it concise — the rule lives in `tdd.md`, the skill just enforces awareness.
- **Drift-guard test simplicity.** The bats test just needs `grep -q "live-API" .claude/rules/tdd.md` and `grep -q "BTS-115\|BTS-170" .claude/rules/tdd.md`. Two assertions, deterministic.
- **Wording: precision over verbosity.** The rule's value is its terseness. Two sentences of "what" + one example anchor + one "why" sentence. Total ~6 lines of prose.
- **Cross-reference economy.** `self-review.md`'s flag-list bullet should be one line referencing the gap. Don't duplicate the full rule prose.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
