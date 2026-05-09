# Self-Review Detail

> Tier 2 reference (BTS-385). Excluded from Claude Code auto-load; read on-demand by agent or operator following the self-review rule's `anchors.evidence` pointer.

This content was extracted verbatim from `.claude/rules/self-review.md` during the BTS-385 rule atomization ramp. The atom file retains the directive layer (mandatory section, flag criteria, write format); this reference holds the dual-capture mechanics, exclusion list, and supporting tooling pointers.

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
