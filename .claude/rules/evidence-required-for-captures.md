# Evidence Required for Bug Captures

## The Rule

Bug-shape captures (via `/idea` mid-session and via `/stasis` at session boundaries) MUST be backed by reproducible evidence before they can be logged as fix-shaped tickets. Hypothesis-backed captures (no evidence) MUST use `DIAGNOSE: <symptom>` titling instead of `FIX: <cause>` — and the first ship for those tickets is the diagnostic capture, not the fix.

## Why

Without this rule, future-self reads a "Likely root cause" capture from a prior session and treats it as actionable work. Verifying turns into "I cannot reproduce this" — wasted context, almost-shipped fictions.

Anchored on **BTS-198** (origin incident, 2026-04-26): a `guard-destructive jq dict-literal false-positive` follow-up was captured during the prior session based on agent narrative ("I worked around with Python"). The capture body literally said *"Likely root cause"* and proposed a fix to a regex in `guard-destructive.sh` that did not exist. The ticket slipped through stasis review and was promoted to Backlog at P3 the next session before pre-flight discovered the phantom rule. We almost shipped a regex carve-out for nothing.

This rule (**BTS-201**) closes that failure mode at capture time.

## What Counts as Evidence

A bug-shape capture qualifies as evidence-backed when its body contains all four of these line-leading anchors (case-sensitive):

- `Command:` — the **exact command** that exhibited the bug, copy-pasteable.
- `Output:` — the **exact error output** (or hook BLOCKED message, or stack trace) — verbatim, not summarized.
- `Exit:` — the **exit code** of the failing command.
- `Reproduce:` — a one-line **reproducer recipe** that future-self can run cold to verify the bug still exists.

If any of the four are missing, the capture is hypothesis-backed and must use `DIAGNOSE:` titling.

## DIAGNOSE: vs FIX: titling

- `FIX: <cause>` — used only when the cause is verified and evidence-backed. The first ship is the actual fix.
- `DIAGNOSE: <symptom>` — used when the symptom is observed but the cause is hypothesized. The first ship is a diagnostic capture (instrumentation, log capture, repro harness) — not the fix. Once the diagnostic surfaces actual evidence, a follow-up `FIX:` ticket is opened with the four anchors populated.

This mirrors the "DIAGNOSE before treat" discipline from clinical medicine: you don't prescribe based on a guess.

## Bug-Shape Heuristic

The `/idea` skill detects bug-shape language with this regex (case-insensitive):

```
fail|false[- ]positive|broken|errored?|blocked by|doesn'?t work|crashes?|hang(s|ing)?
```

When matched on a capture body and no evidence block is present, the skill MUST refuse fix-shaped capture and offer `DIAGNOSE:` titling as the only forward path. The operator can override by providing the four anchors or accepting the `DIAGNOSE:` retitle.

## How to Apply

- **At `/idea` time:** the skill's Step 0.5 evidence gate runs the heuristic. Refuses fix-shape capture without anchors. Surfaces the rule reference in the refusal message.
- **At `/stasis` time:** the `evidence-scan-session` substrate scans the session's captures and surfaces an `## Evidence Gaps` section in `docs/stasis.md`. Empty state emits the literal `No evidence gaps this session.` so the section is always parseable.
- **At `/recall` time:** the cold-start briefing reads the prior stasis's `## Evidence Gaps` section and surfaces non-empty entries under `**Evidence Gaps from prior session:**`. Silent when empty (no noise).

## Out of Scope

- Backfilling evidence for historical bug captures. Forward-only rule.
- Server-side enforcement (Linear webhooks, GitHub PR checks). Local-at-capture-time only.
- Heuristic refinement. False-positives on the heuristic are acceptable; the operator can always title `DIAGNOSE:` to bypass when a body is technical narrative rather than a bug report.
