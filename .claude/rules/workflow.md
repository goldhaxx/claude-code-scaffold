---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/feature-lifecycle.md
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
    - BTS-385 (atomized for tier-0)
---

# Workflow

**Feature lifecycle:** Spec → Activate → Plan → Implement → Complete → Merge → Land. Main is protected (PreToolUse hook blocks direct commits).

**Session discipline:** one objective per session. End with summary → next-action → `/stasis` → `/compact`. Resume after reset via `/recall`.

**Error recovery:** after 2 failed attempts, STOP. Run `/stasis` and surface alternatives instead of looping.

For the full lifecycle table, per-phase commands, strategic-awareness primitives, context-preservation detail, hub-sync classification, and reasoning behind each rule: see the evidence anchor `docs/research/feature-lifecycle.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
