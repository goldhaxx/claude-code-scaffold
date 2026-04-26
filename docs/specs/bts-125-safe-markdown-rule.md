# Feature: Document safe-markdown rule for Linear-bound idea bodies

> Feature: bts-125-safe-markdown-rule
> Work: linear:BTS-125
> Created: 1777178566
> Status: Complete

## Summary

BTS-125 was filed against Linear's MCP `save_issue` after a 2026-04-23 incident where a 6-item nested numbered list lost items 2-6 entirely on save. A 2026-04-26 reproduction (in BTS-174 test ticket) shows that catastrophic truncation **no longer reproduces** — Linear server-side has fixed it. A residual normalization persists on both http and MCP routes: numbered-list items whose leading bold contains a backticked code-span at the start (`**`code` text.**`) get the bold markers stripped on round-trip. Items where bold starts with plain text are preserved. The mutation is cosmetic (no content lost, only formatting) but silent and reproducible. Document the avoidance rule in the `/idea` skill prose so capture flows that push markdown-heavy bodies into Linear don't surface formatting drift on refetch.

## Job To Be Done

**When** I'm capturing an idea body that uses bold-emphasized list-item leads (a common ccanvil convention),
**I want** the `/idea` skill to point me at a safe-markdown pattern (codespan-then-bold-text, or plain-text-leading-bold),
**So that** my bold formatting survives the round-trip through Linear's parser without me having to discover the silent mutation by re-reading my own ticket later.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.claude/skills/idea/SKILL.md` contains a `## Safe-markdown for Linear-bound bodies` section (or equivalent named subsection) describing the bold-around-leading-codespan trigger and the recommended rewrite shapes. Validated by drift-guard grep on the literal heading.
- [ ] **AC-2:** The new section names at least three concrete shapes: (a) the failing pattern `**`code` text.**`, (b) a passing rewrite `` `code` — text.``, (c) a passing rewrite `**Text with `code` later.**`. Validated by drift-guard grep on the bracketed pattern strings.
- [ ] **AC-3:** The section anchors on BTS-125 by name so future readers can cross-link to the repro evidence and the Linear server-side observation. Validated by `grep -q "BTS-125" .claude/skills/idea/SKILL.md`.
- [ ] **AC-4:** Drift-guard test in `hub/tests/idea-safe-markdown-rule.bats` asserts AC-1, AC-2, AC-3 simultaneously, plus the hub-managed-section bracket check (rule lives ABOVE `<!-- NODE-SPECIFIC-START -->`). All four assertions pass under `set -e` (BTS-127 strict mode).
- [ ] **AC-5:** Existing skill behavior unchanged — `/idea <text>` capture continues to forward the body verbatim through both providers. No new validation, no rewrite-on-the-fly. Documentation only.

## Affected Files

| File | Change |
|------|--------|
| `.claude/skills/idea/SKILL.md` | Modified — add `## Safe-markdown for Linear-bound bodies` section above NODE-SPECIFIC-START |
| `hub/tests/idea-safe-markdown-rule.bats` | New — drift-guard tests for AC-1 through AC-4 |

## Dependencies

- **Requires:** none. Pure prose + drift-guard test.
- **Blocked by:** none.

## Out of Scope

- **Round-trip validation wrapper.** Adding `linear-query.sh save-issue --verify` to refetch + byte-diff the description was the original BTS-125 proposal. With catastrophic truncation fixed and only cosmetic bold-stripping remaining, a wrapper is overinvestment. Capture as a follow-up if a third class of silent mutation surfaces.
- **Pre-send linter.** A regex linter that flags risky patterns before save is similarly disproportionate to the current cost. Documentation puts the rule where capture flows already read.
- **Reaching out to Linear upstream.** Out of scope for this ticket; if the residual normalization becomes load-bearing, file with Linear separately.
- **Broader markdown-pattern audit.** Other normalizations may exist (e.g., bullet character `-` → `*` is already observed and benign). Don't enumerate exhaustively; document the one observed-bad pattern and the avoidance shape.

## Implementation Notes

- **Where the section lives.** Insert above the `<!-- NODE-SPECIFIC-START -->` marker so it propagates via `ccanvil-pull` to all downstream nodes — this is hub-managed substrate.
- **Section shape.** Three short paragraphs: (1) what the trigger is and what gets stripped, (2) the rewrite rules, (3) anchor mention of BTS-125 for cross-link. ~80 words total. Don't over-document; the rule is narrow.
- **Drift-guard test pattern.** Mirror `hub/tests/live-api-validation-rule.bats` (BTS-171) — single bats file with 4 `grep -q` assertions wrapped in `set -e`. The hub-managed bracket check ensures the rule lands in the propagating section, not the node-specific tail.
- **No live-API gate triggered.** No plan step calls a risky API; this is a pure-prose substrate change. /review can be skipped per skip-feedback memory.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
