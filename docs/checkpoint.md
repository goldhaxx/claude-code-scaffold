# Checkpoint

> Feature: between-features
> Last updated: 1775884151
> Session objective: Discuss BTS-67, build /spec skill, capture ideas from field testing

## Accomplished

- Built `/spec` skill (`preset/.claude/skills/spec/SKILL.md`) — proper user-facing entry point for spec writing
- Fixed spec-writer agent misfire: removed "when the user says 'spec this'" trigger from agent description that caused `Skill(spec-writer)` instead of `Agent(spec-writer)`
- Updated command reference and core workflow diagrams to reference `/spec`
- Committed registry update for luxlook
- Captured 9 untriaged ideas from field testing (init bugs, idea system improvements, lifecycle maturation, checkpoint evaluation)

## Current State

- **Branch:** main
- **Tests:** 406/406 passing
- **Uncommitted changes:** no (docs/checkpoint.md will be committed with this)
- **Build status:** clean

## Blocked On

- Nothing blocking

## Next Steps

1. Run `/radar` for full project briefing — connect 9 untriaged ideas + BTS-67 discussion + backlog into a coherent priority view
2. Run `/idea triage` to classify the 9 new ideas (some are bugs that should be promoted, some should merge with BTS-67)
3. Decide next feature to spec/implement — BTS-67 (flatten hub) is the structural enabler, but init bugs may be more urgent for downstream adoption

## Context Notes

- BTS-67 (flatten hub architecture) was pulled from Linear and discussed. Key open questions: CLAUDE.md merge strategy, .claude/ directory merge, test path updates, distribution scoping after removing preset/. No decision made yet.
- Field testing on taxes project surfaced two init bugs: (1) init-apply expects bare JSON array but init-preflight outputs wrapped object, (2) init doesn't create .gitignore or register with hub
- User is evaluating whether checkpoint mechanism is still needed given /compact + /catchup + auto-memory. Captured as idea for triage.
- The idea system itself needs improvement: UIDs, epoch timestamps, update-in-place instead of addendums. Multiple ideas captured about this.

## Determinism Review

- **operations_reviewed:** 8
- **candidates_found:** 1
- **idea-add called 9 times individually**: Each `/idea` invocation ran one `idea-add` call, which is correct (skill delegates to script). However, the addendum pattern (ideas #4 and #7) required new entries instead of updating existing ones — this is a known gap captured as idea #5 (UIDs + update-in-place). Impact: medium.
- The rest of the session was discussion, skill creation, and agent description edits — all judgment work. No candidates this session.
