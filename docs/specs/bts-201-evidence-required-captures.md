# Feature: Capture-time evidence requirement for bug reports

> Feature: bts-201-evidence-required-captures
> Work: linear:BTS-201
> Created: 1777236317
> Status: Complete

## Summary

Bug-shape captures (via `/idea` mid-session and via `/stasis` at session boundaries) must be backed by reproducible evidence — exact failing command, exact error output, exit code — before they can be logged as fix-shaped tickets. Hypothesis-backed captures (no evidence) must instead use `DIAGNOSE: <symptom>` titling, where the first ship is the diagnostic capture, not the fix. This closes the failure mode that produced BTS-198: a "guard-destructive jq dict-literal false-positive" ticket whose hypothesized regex did not exist; we almost shipped a carve-out for a phantom rule.

## Job To Be Done

**When** I'm at a session boundary or capturing a bug mid-session,
**I want** the protocol to refuse hypothesis-shaped fix tickets,
**So that** future-me cannot read a "Likely root cause" capture and treat it as actionable work.

## Acceptance Criteria

- [ ] **AC-1:** New rule file exists at `.claude/rules/evidence-required-for-captures.md` and is referenced by `/idea`, `/stasis`, and `/recall` skill bodies (drift-guard verifies file exists + each of the three skill files contains a literal `evidence-required-for-captures` reference).
- [ ] **AC-2:** Rule body documents the four required evidence fields (exact command, exact error output, exit code, one-line reproducer) AND the `DIAGNOSE:`-vs-`FIX:` titling convention. Drift-guard greps for the literal phrases `exact command`, `exit code`, `reproducer`, `DIAGNOSE:`, and `FIX:`.
- [ ] **AC-3:** `/idea` skill prose includes a Step 0.5 (between flag extraction and title generation) that scans body text for bug-shape language using a documented heuristic regex (case-insensitive: `fail|false[- ]positive|broken|errored?|blocked by|doesn'?t work|crashes?|hang(s|ing)?`). When matched AND no evidence block is present, the skill MUST refuse fix-shaped capture and offer `DIAGNOSE:`-titled capture as the only path forward. Drift-guard asserts the heuristic regex is present in `SKILL.md`.
- [ ] **AC-4:** `/idea` skill defines what counts as an "evidence block" deterministically: a body containing all four anchor markers `Command:`, `Output:`, `Exit:`, `Reproduce:` (case-sensitive, line-leading). Drift-guard greps `SKILL.md` for these four anchor strings.
- [ ] **AC-5:** `/stasis` skill includes a new step (between data-gathering and synthesis) that calls a new substrate primitive `docs-check.sh evidence-scan-session --since <last-stasis-commit> --project-dir .` which returns JSON `{evidence_gaps: [{id, title, reason}], scanned: N}`. The scan inspects ideas captured since the prior stasis (via `idea.list` filtered by createdAt) for bug-shape titles lacking evidence anchors in their bodies.
- [ ] **AC-6:** `/stasis` skill writes detected gaps into a new `## Evidence Gaps` section of `docs/stasis.md`. When `evidence_gaps` is empty, the section emits the literal line `No evidence gaps this session.` so it is always present (parseable by `/recall`). The stasis template at `.ccanvil/templates/stasis.md` is updated to include the section with that empty-state literal.
- [ ] **AC-7:** `/recall` skill reads the prior stasis's `## Evidence Gaps` section and surfaces non-empty entries in the cold-start briefing under a heading `**Evidence Gaps from prior session:**` with one line per gap (`- BTS-X — <title> — <reason>`). When the section is the empty-state literal, the recall briefing OMITS the heading entirely (no noise).
- [ ] **AC-8:** New substrate primitive `docs-check.sh evidence-scan-session` is implemented and unit-tested via `hub/tests/evidence-scan-session.bats`. Tests cover: (a) zero captures returns `{evidence_gaps: [], scanned: 0}`; (b) one capture matching bug-shape but lacking anchors returns one gap with reason `missing-evidence-anchors`; (c) one capture with all four anchors returns zero gaps even if title matches bug-shape; (d) one capture with `DIAGNOSE:` title is exempt from evidence requirement; (e) malformed JSON from upstream `idea.list` exits non-zero with a clear error.
- [ ] **AC-9:** Drift-guards file at `hub/tests/evidence-required-protocol.bats` asserts AC-1, AC-2, AC-3, AC-4, AC-6 (template content), and AC-7 (recall prose).
- [ ] **AC-10:** Edge: `evidence-scan-session` correctly classifies a capture whose body uses `DIAGNOSE:` in the title — this is exempt (no evidence required, since it's explicitly a diagnostic-first capture). Test case in AC-8(d) covers this.
- [ ] **AC-11:** Edge: when run on a fresh node with no prior stasis (no `--since` resolvable), `evidence-scan-session` falls back to scanning the last 24h of captures and emits `{evidence_gaps: [...], scanned: N, fallback: "24h"}`. This prevents the substrate from breaking on first-stasis nodes (mirrors `/recall`'s sessions-list fallback in BTS-22).

## Affected Files

| File | Change |
|------|--------|
| `.claude/rules/evidence-required-for-captures.md` | New |
| `.claude/skills/idea/SKILL.md` | Modified (add Step 0.5, evidence-block definition, DIAGNOSE: convention reference) |
| `.claude/skills/stasis/SKILL.md` | Modified (add evidence-scan step, write `## Evidence Gaps` section) |
| `.claude/skills/recall/SKILL.md` | Modified (read + surface `## Evidence Gaps` from prior stasis) |
| `.ccanvil/templates/stasis.md` | Modified (add `## Evidence Gaps` section with empty-state literal) |
| `.ccanvil/scripts/docs-check.sh` | New subcommand `evidence-scan-session` |
| `hub/tests/evidence-scan-session.bats` | New |
| `hub/tests/evidence-required-protocol.bats` | New (drift-guards on rule + 3 skills + template) |

## Dependencies

- **Requires:** `idea.list` substrate (existing, BTS-175) for fetching session captures.
- **Blocked by:** None.

## Out of Scope

- Backfilling evidence for historical bug captures already in Linear. This protocol applies forward — existing tickets stay as-is unless re-triaged.
- Server-side enforcement (Linear webhooks, GitHub PR checks). Enforcement is local at capture time only.
- Evidence requirements for non-bug captures (feature ideas, refactor candidates, strategic notes). Only bug-shape captures are gated.
- Auto-converting a refused fix-shape capture into a DIAGNOSE: capture without operator confirmation. The skill prompts; the operator decides.
- Heuristic refinement beyond the documented regex. False-positives on the heuristic are accepted; the operator can always invoke `/idea` with explicit `DIAGNOSE:` titling to bypass the gate when a body is technical narrative rather than a bug report.

## Implementation Notes

- The bug-shape heuristic deliberately uses common English bug phrasings, not technical jargon — captures that come through agent narrative or operator dictation tend to use these words consistently.
- The four evidence anchors (`Command:`, `Output:`, `Exit:`, `Reproduce:`) are line-leading and case-sensitive to be unambiguously detectable. Keep the spec strict; ergonomics for the operator is a one-line reminder in `/idea`'s refusal message.
- `evidence-scan-session` should reuse the `idea.list` resolver via `operations.sh` rather than calling Linear directly — preserves provider neutrality.
- The drift-guard pattern follows `idea-safe-markdown-rule.bats` (BTS-125) — that file is the canonical model for "skill body must reference rule file" tests.
- Anchored on BTS-198 — the capture body literally said "Likely root cause" and slipped through stasis review. This protocol catches that exact wording (`Likely` does not satisfy the four anchors).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
