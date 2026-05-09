# Feature Lifecycle Reference

> Tier 2 reference (BTS-385). Excluded from Claude Code auto-load; read on-demand by agent or operator following the workflow rule's `anchors.evidence` pointer.

This content was extracted verbatim from `.claude/rules/workflow.md` during the BTS-385 rule atomization ramp. The atom file retains the directive layer; this reference holds the operational detail.

## Feature Lifecycle Table

| Step | What happens | Command |
|------|-------------|---------|
| **Spec** | Acceptance criteria in `docs/specs/<id>.md` | `/spec` |
| **Activate** | Branch + draft PR + copy spec to `docs/spec.md` | `docs-check.sh activate <id>` |
| **Plan** | Implementation plan in `docs/plan.md` | `/plan` |
| **Implement** | TDD: red → green → refactor → commit | Manual |
| **Complete** | Mark Complete, remove lifecycle docs, PR ready | `docs-check.sh complete <id>` |
| **Merge** | Squash merge to main | `gh pr merge --squash` |
| **Land** | Switch to main, sync, delete branch | `docs-check.sh land` |

Main is protected — PreToolUse hook blocks direct commits to main/master.

## Strategic Awareness

- `/radar` — project briefing at session start or between features
- `/idea <text>` — quick capture; triage via `/idea triage`
- `docs/roadmap.md` — strategic source of truth; update when direction changes

## Session Discipline

- One objective per session. State it at the start.
- End with: one-line summary → explicit next action → `/stasis` → `/compact`.
- After ~30 min of complex work, suggest running `/stasis`.

## Context Preservation

- Run `/stasis` before `/compact`. Writes `docs/stasis.md` using `.ccanvil/templates/stasis.md` — Feature ID, epoch, plan hash.
- Plan before `/stasis` if no plan exists.
- Determinism review mandatory in every stasis — follow `self-review.md`.
- Resume after reset: run `/recall`.

## Hub Sync

- Classify new preset files at creation: "project-specific or hub-tracked?"
- When preset structure changes, update relevant `.ccanvil/guide/` file.

## Error Recovery

- After 2 failed attempts, STOP. Run `/stasis` and suggest alternatives.
