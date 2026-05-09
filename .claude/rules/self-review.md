---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/self-review-detail.md
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
    - BTS-385 (atomized for tier-0)
---

# Self-Review: Determinism

The `## Determinism Review` section in `docs/stasis.md` is **mandatory** in every stasis. Format: `.ccanvil/templates/stasis.md`.

**Flag an operation when all four hold:**
1. Claude performed it this session
2. The operation is computable (same input → same output)
3. A script, hook, or improved output format could replace it
4. It consumed meaningful context (not a trivial one-liner)

Also flag a plan-flagged live-API risk where the implementer skipped live-validation before commit (BTS-171).

**Write each candidate as:** `**[operation]**: Claude [what happened]. Should be [deterministic replacement]. Impact: [high|medium|low].` If none: `No candidates this session.`

For dual-capture mechanics (BTS-115), when-NOT-to-flag list, `audit-session` safety net, and `/ccanvil-audit` full-audit pointer: see evidence anchor `docs/research/self-review-detail.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
