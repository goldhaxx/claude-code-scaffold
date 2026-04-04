# Self-Review: Continuous Determinism Improvement

## The Rule

The `## Determinism Review` section in `docs/checkpoint.md` is **mandatory** at every checkpoint. The workflow rule in `workflow.md` specifies the exact checkpoint flow and checklist. This rule provides the judgment criteria for what to flag.

## When to Flag

Flag an operation if ALL of these are true:
1. Claude performed it during the current session
2. The operation is computable (same input → same output)
3. A script command, hook, or improved output format could replace it
4. It consumed meaningful context (more than a trivial one-liner)

## What to Write

Fill the `## Determinism Review` section in `docs/checkpoint.md` with:
- `operations_reviewed: [count]` — how many operations you assessed
- `candidates_found: [count]` — how many should become deterministic
- For each candidate: `**[operation]**: Claude [what happened]. Should be [deterministic replacement]. Impact: [high/medium/low].`
- If no candidates: "No candidates this session."

## When NOT to Flag

- Merge conflict resolution (requires semantic understanding)
- Change classification (generalizable vs specific)
- Spec writing, planning, code review
- One-time exploratory operations that won't recur
- Operations that are already minimally stochastic (single command + read output)

## Safety Net

The `docs-check.sh audit-session` script provides a post-hoc safety net — it scans git diffs for stochastic patterns that the warm-context review may have missed. `/catchup` runs it automatically.

## Full Audit

For a comprehensive analysis, run `/scaffold-audit`. This rule is the lightweight, always-on version.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
