# Feature: Replace /clear with /compact throughout workflow

> Feature: compact-over-clear
> Created: 1776122291
> Status: Draft

## Summary

Replace `/clear` with `/compact` as the default context management recommendation throughout ccanvil's rules, guide docs, templates, and public-facing documentation. `/compact` retains a compressed summary of the conversation, providing better continuity when combined with checkpoints and `/catchup`. `/clear` remains available as a nuclear option but is no longer the default recommendation.

## Job To Be Done

**When** a session reaches a natural boundary (checkpoint, feature complete, stuck, long session),
**I want to** recommend `/compact` instead of `/clear` as the default next step,
**So that** context is preserved across session boundaries, reducing the cold-start penalty of `/catchup` and improving continuity.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.claude/rules/workflow.md` recommends `/compact` as the default session boundary action; `/clear` is mentioned only as a fallback for full task switches
- [ ] **AC-2:** `.ccanvil/guide/session-management.md` flowchart uses `/compact` as the end-of-session node; "When to `/clear`" section is renamed to "When to reset context" with `/compact` as the primary recommendation
- [ ] **AC-3:** `.ccanvil/guide/decision-guide.md` flowcharts replace `/clear` with `/compact` in checkpoint flows; a separate `/clear` node exists only for "completely unrelated new task"
- [ ] **AC-4:** `.ccanvil/guide/command-reference.md` updates the `/catchup` description to say "after `/compact`" and updates the `/clear` entry to note it's for full resets only
- [ ] **AC-5:** `.ccanvil/guide/core-workflow.md` DONE step recommends `/compact` instead of `/clear`
- [ ] **AC-6:** `README.md` updates all workflow examples and command references to prefer `/compact`
- [ ] **AC-7:** `hub/meta/HOW_TO_USE.md` updates all workflow examples, dialogues, and command references to prefer `/compact`
- [ ] **AC-8:** `hub/meta/SYSTEM_PROMPT.md` updates the `/catchup` description line
- [ ] **AC-9:** `.ccanvil/guide/foundations.md` is NOT modified (protected research source material — references to `/clear` there are descriptive of external practitioners, not prescriptive)
- [ ] **AC-10:** Error/edge: the word "clear" in non-command contexts (e.g., "clear next action", "clear context") is not accidentally replaced
- [ ] **AC-11:** Every file that previously recommended `checkpoint → /clear → /catchup` now recommends `checkpoint → /compact → /catchup` (or just `checkpoint → /compact` where catchup is unnecessary due to retained context)
- [ ] **AC-12:** No test files are broken by the changes (full `bats hub/tests/` suite passes)

## Affected Files

| File | Change |
|------|--------|
| `.claude/rules/workflow.md` | Modified — 4 references |
| `.ccanvil/guide/session-management.md` | Modified — flowchart + table + section heading |
| `.ccanvil/guide/decision-guide.md` | Modified — 2 flowcharts |
| `.ccanvil/guide/command-reference.md` | Modified — 2 table entries |
| `.ccanvil/guide/core-workflow.md` | Modified — 1 flowchart node |
| `README.md` | Modified — ~7 references |
| `hub/meta/HOW_TO_USE.md` | Modified — ~8 references |
| `hub/meta/SYSTEM_PROMPT.md` | Modified — 1 reference |

## Dependencies

- **Requires:** None — purely documentation/configuration changes
- **Blocked by:** Nothing

## Out of Scope

- Modifying `.ccanvil/guide/foundations.md` (research source, descriptive not prescriptive)
- Creating new scripts or hooks (no code changes needed)
- Changing the `/catchup` or checkpoint skill implementations (they already work with both `/compact` and `/clear`)
- Modifying `docs/ideas.md` (idea #5817 is already promoted)

## Implementation Notes

- This is a text-replacement feature with nuance: not a blind find-replace. Each reference needs contextual judgment about whether `/compact` or `/clear` is appropriate.
- Pattern: most `checkpoint → /clear → /catchup` flows become `checkpoint → /compact`. The `/catchup` step may be unnecessary after `/compact` since context is retained.
- Mermaid flowcharts need node ID updates (e.g., `CLEAR` → `COMPACT`) and style changes (red → blue for less alarming visual).
- The "aggressive clearing" philosophy in session-management.md should shift to "aggressive compaction" — same principle (don't let context degrade) but preserving more state.
