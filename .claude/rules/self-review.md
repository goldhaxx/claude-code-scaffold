---
manifest:
  id: self-review
  purpose: Codify the mandatory `## Determinism Review` section in every stasis (per the .ccanvil/templates/stasis.md template) and the judgment criteria for what counts as a flaggable candidate. Defines the BTS-115 dual-capture flow (each candidate auto-promoted to a Linear idea on Linear-routed projects) and its dedup-by-title rule. Provides the audit-session safety net for warm-context misses.
  input:
    - "read-only: rule consumed during /stasis Determinism Review composition and /ccanvil-audit"
  output:
    - "behavior-shape: forces every stasis to enumerate operations_reviewed/candidates_found and dual-capture each candidate as Determinism: <slug> idea on Linear-routed projects"
  caller:
    - skill:/stasis
  depends-on:
    - audit-session
  side-effect:
    - "shapes-stasis-composition (no file mutation; behavioral influence)"
    - "dispatches-determinism-candidates-to-linear-via-/stasis"
  failure-mode:
    - "section-omitted-from-stasis | exit=n/a | visible=validate-flags-missing-determinism-review | mitigation=add-section-with-counts-or-No-candidates-this-session"
  contract:
    - mandatory-in-every-stasis
    - dual-capture-via-/stasis-on-Linear-routed
    - dedup-by-exact-title-match
    - audit-session-as-warm-context-safety-net
  anchor:
    - BTS-115 (dual-capture)
    - BTS-252 (manifest seed)
---

# Self-Review: Continuous Determinism Improvement

## The Rule

The `## Determinism Review` section in `docs/stasis.md` is **mandatory** at every stasis. The stasis template (`.ccanvil/templates/stasis.md`) defines the format. This rule provides the judgment criteria for what to flag.

## When to Flag

Flag an operation if ALL of these are true:
1. Claude performed it during the current session
2. The operation is computable (same input → same output)
3. A script command, hook, or improved output format could replace it
4. It consumed meaningful context (more than a trivial one-liner)

Also flag (BTS-171): a plan-flagged live-API contract risk where the implementer skipped live-validation before commit. This is a rule/skill candidate, not a script-replacement candidate — the fix lives in `.claude/rules/tdd.md` and the `/plan` skill prose, not in a new shell command.

## What to Write

Fill the `## Determinism Review` section in `docs/stasis.md` with:
- `operations_reviewed: [count]` — how many operations you assessed
- `candidates_found: [count]` — how many should become deterministic
- For each candidate: `**[operation]**: Claude [what happened]. Should be [deterministic replacement]. Impact: [high/medium/low].`
- If no candidates: "No candidates this session."

## Dual-capture to Linear (BTS-115)

When `candidates_found > 0` AND the project is Linear-routed, `/stasis` automatically captures each candidate as a Linear idea (title `Determinism: <slug>`) so the candidate is visible in `/idea triage`, `/radar`, and the cross-session backlog. Dedup is by exact title match against the existing idea list. You don't need to manually `/idea` flagged candidates — `/stasis` handles it.

On local-routed projects, the dual-capture step is a no-op — candidates still land in `docs/stasis.md` (existing behavior preserved).

## When NOT to Flag

- Merge conflict resolution (requires semantic understanding)
- Change classification (generalizable vs specific)
- Spec writing, planning, code review
- One-time exploratory operations that won't recur
- Operations that are already minimally stochastic (single command + read output)

## Safety Net

The `docs-check.sh audit-session` script provides a post-hoc safety net — it scans git diffs for stochastic patterns that the warm-context review may have missed. `/recall` runs it automatically.

## Full Audit

For a comprehensive analysis, run `/ccanvil-audit`. This rule is the lightweight, always-on version.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
