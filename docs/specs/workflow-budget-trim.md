---
feature_id: workflow-budget-trim
status: Ready
created: 1776364800
type: chore
---

# workflow.md Budget Trim

## Problem

`workflow.md` is 102 lines and 1673 tokens — 20.9% of the 8000-token context budget. The rule-file max is 40 lines. It is the single largest always-loaded file, consuming attention budget on every turn.

## Analysis

Sections and their line counts:

| Section | Lines | Redundancy |
|---------|-------|------------|
| Feature Lifecycle (table + notes) | 24 | Notes partially repeat table |
| Strategic Awareness | 6 | Pointers to commands |
| Session Discipline | 5 | Unique, keep |
| Before Writing Code | 6 | Redundant with standard Claude behavior |
| Context Preservation | 25 | Checklist duplicated in self-review.md; format defined in templates/checkpoint.md |
| Commit Practices | 6 | Redundant with global CLAUDE.md |
| Delegation | 5 | Redundant with global CLAUDE.md |
| Hub Sync | 7 | Some items are operational, not rule-like |
| Error Recovery | 6 | Unique, keep |

## Approach

Compress in-place. Do NOT split into multiple rule files (splitting doesn't reduce total tokens since all rules are always loaded).

1. **Remove sections redundant with CLAUDE.md**: Before Writing Code, Commit Practices, Delegation
2. **Compress Context Preservation**: Remove determinism checklist (already in self-review.md), reference the template instead of repeating format
3. **Compress Feature Lifecycle**: Trim post-table notes to essentials
4. **Compress Hub Sync**: Keep only the actionable rules
5. **Compress Strategic Awareness**: One-line per command

## Acceptance Criteria

- AC-1: workflow.md is 40 lines or fewer (excluding the NODE-SPECIFIC delimiter block)
- AC-2: workflow.md is under 700 tokens (< 9% of budget)
- AC-3: "Before Writing Code", "Commit Practices", and "Delegation" sections are removed
- AC-4: Determinism checklist is NOT in workflow.md (self-review.md owns it)
- AC-5: Feature lifecycle table is preserved (the table itself, not the post-table notes)
- AC-6: Context preservation references `templates/checkpoint.md` instead of repeating the format
- AC-7: All existing tests pass (no behavioral changes — this is a content trim, not a code change)
- AC-8: self-review.md is updated if needed to be self-sufficient (no broken cross-references)
- AC-9: No information is lost — anything removed must be either (a) covered by another always-loaded file or (b) derivable from standard Claude behavior
- AC-10: context-budget.sh check shows workflow.md below 9% of budget
