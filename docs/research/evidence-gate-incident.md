# Evidence Gate Incident Reference

> Tier 2 reference (BTS-387). Excluded from Claude Code auto-load; read on-demand by agent or operator following the evidence-required-for-captures rule's `anchors.evidence` pointer.

This content was extracted verbatim from `.claude/rules/evidence-required-for-captures.md` during the BTS-387 atomization audit. The atom file retains the four-anchor list, bug-shape heuristic regex, and DIAGNOSE: titling convention; this reference holds the BTS-198 origin incident, Why-it-matters rationale, and operational application detail across the lifecycle.

## Why

Without this rule, future-self reads a "Likely root cause" capture from a prior session and treats it as actionable work. Verifying turns into "I cannot reproduce this" — wasted context, almost-shipped fictions.

Anchored on **BTS-198** (origin incident, 2026-04-26): a `guard-destructive jq dict-literal false-positive` follow-up was captured during the prior session based on agent narrative ("I worked around with Python"). The capture body literally said *"Likely root cause"* and proposed a fix to a regex in `guard-destructive.sh` that did not exist. The ticket slipped through stasis review and was promoted to Backlog at P3 the next session before pre-flight discovered the phantom rule. We almost shipped a regex carve-out for nothing.

This rule (**BTS-201**) closes that failure mode at capture time.

## DIAGNOSE: vs FIX: titling — full rationale

- `FIX: <cause>` — used only when the cause is verified and evidence-backed. The first ship is the actual fix.
- `DIAGNOSE: <symptom>` — used when the symptom is observed but the cause is hypothesized. The first ship is a diagnostic capture (instrumentation, log capture, repro harness) — not the fix. Once the diagnostic surfaces actual evidence, a follow-up `FIX:` ticket is opened with the four anchors populated.

This mirrors the "DIAGNOSE before treat" discipline from clinical medicine: you don't prescribe based on a guess.

## How to Apply (across the lifecycle)

- **At `/idea` time:** the skill's Step 0.5 evidence gate runs the heuristic. Refuses fix-shape capture without anchors. Surfaces the rule reference in the refusal message.
- **At `/stasis` time:** the `evidence-scan-session` substrate scans the session's captures and surfaces an `## Evidence Gaps` section in `docs/stasis.md`. Empty state emits the literal `No evidence gaps this session.` so the section is always parseable.
- **At `/recall` time:** the cold-start briefing reads the prior stasis's `## Evidence Gaps` section and surfaces non-empty entries under `**Evidence Gaps from prior session:**`. Silent when empty (no noise).

## Out of Scope

- Backfilling evidence for historical bug captures. Forward-only rule.
- Server-side enforcement (Linear webhooks, GitHub PR checks). Local-at-capture-time only.
- Heuristic refinement. False-positives on the heuristic are acceptable; the operator can always title `DIAGNOSE:` to bypass when a body is technical narrative rather than a bug report.
