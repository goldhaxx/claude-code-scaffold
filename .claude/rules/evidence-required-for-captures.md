---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/evidence-gate-incident.md
manifest:
  id: evidence-required-for-captures
  purpose: Codify the BTS-201 evidence gate — bug-shape captures (via /idea mid-session and /stasis at session boundaries) MUST be backed by reproducible evidence (Command / Output / Exit / Reproduce anchors) before being logged as fix-shaped tickets. Hypothesis-backed captures use `DIAGNOSE:` titling and the first ship is the diagnostic capture, not the fix. Closes the BTS-198 failure mode where a "Likely root cause" capture nearly shipped a regex carve-out for a phantom rule.
  input:
    - "read-only: rule consumed at /idea capture-time, /stasis evidence-scan, /recall briefing"
  output:
    - "behavior-shape: refuses fix-shape captures missing the four anchors; offers DIAGNOSE retitle as forward path"
  caller:
    - skill:/idea
    - skill:/stasis
    - skill:/recall
  side-effect:
    - "shapes-capture-flow (no file mutation; behavioral influence at capture-time)"
  failure-mode:
    - "rule-bypassed | exit=n/a | visible=phantom-fix-tickets-in-backlog | mitigation=stasis-Evidence-Gaps-section-surfaces-violations-each-session"
  contract:
    - four-anchors-required-for-fix-shape
    - diagnose-titling-bypasses-anchor-requirement
    - empty-state-literal-No-evidence-gaps-this-session
  anchor:
    - BTS-198 (origin incident)
    - BTS-201 (rule + evidence-scan substrate)
    - BTS-252 (manifest seed)
    - BTS-387 (atomized for tier-0)
---

# Evidence Required for Bug Captures

Bug-shape captures (via `/idea` mid-session and `/stasis` at session boundaries) MUST be backed by reproducible evidence before being logged as fix-shaped tickets. Hypothesis-backed captures use `DIAGNOSE: <symptom>` titling — the first ship is the diagnostic capture, not the fix.

**The four anchors (case-sensitive, line-leading) — required for `FIX:` shape:**

- `Command:` — exact command that exhibited the bug, copy-pasteable.
- `Output:` — exact error output (or hook BLOCKED message, or stack trace) — verbatim, not summarized.
- `Exit:` — exit code of the failing command.
- `Reproduce:` — one-line reproducer recipe.

If any are missing, the capture must use `DIAGNOSE:` titling (bypasses the anchor requirement; first ship = diagnostic).

**Bug-shape heuristic** (case-insensitive regex used by the `/idea` skill's Step 0.5 evidence gate):

```
fail|false[- ]positive|broken|errored?|blocked by|doesn'?t work|crashes?|hang(s|ing)?
```

When matched and no anchors are present, the skill refuses fix-shape capture and offers `DIAGNOSE:` retitle as the only forward path.

For the BTS-198 origin incident, the DIAGNOSE-vs-FIX rationale, lifecycle application detail (`/idea`/`/stasis`/`/recall` integration), and out-of-scope clarifications: see evidence anchor `docs/research/evidence-gate-incident.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
