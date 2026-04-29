---
manifest:
  id: workflow
  purpose: Codify the canonical feature lifecycle (Spec → Activate → Plan → Implement → Complete → Merge → Land), session discipline (one objective per session; end-of-session ritual /stasis → /compact), strategic-awareness primitives (/radar, /idea, docs/roadmap.md), context-preservation rules (stasis before compact; /recall after reset), hub-sync classification, and error-recovery protocol (after 2 failed attempts, STOP and capture state).
  input:
    - "read-only: rule consumed across the full lifecycle (spec, activate, plan, implement, complete, ship, land, stasis, recall)"
  output:
    - "behavior-shape: forces session-discipline rituals; halts long unsubmitted work; routes recovery through stasis"
  caller:
    - skill:/recall
    - skill:/stasis
  side-effect:
    - "shapes-session-flow (no file mutation; behavioral influence on operator and agent)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=lifecycle-drift-or-context-loss-on-compact | mitigation=run-/recall-and-resume-from-stasis"
  contract:
    - one-objective-per-session
    - stasis-before-compact
    - main-is-protected
    - halt-and-stasis-after-2-failed-attempts
  anchor:
    - BTS-252 (manifest seed)
---

# Workflow and Context Management Rules

## Feature Lifecycle

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
- After 2 failed attempts, STOP. Checkpoint and suggest alternatives.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
