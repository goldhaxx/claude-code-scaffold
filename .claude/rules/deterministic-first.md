---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/deterministic-first-foundations.md
manifest:
  id: deterministic-first
  purpose: Codify the deterministic-first principle — when an operation is computable (same input → same output, every time), it MUST be implemented as deterministic machinery (scripts, hooks, tooling), not as Claude reasoning. Every token spent on deterministic ops is stolen from judgment calls that actually need a transformer. The rule defines a 4-tier hierarchy (hook / script / slash command with script calls / pure Claude reasoning) and cataloged anti-patterns.
  input:
    - "read-only: rule consumed during /plan, implementation, /ccanvil-audit"
  output:
    - "behavior-shape: forces deterministic substrate over Claude orchestration; halts stochastic costume around computable ops"
  side-effect:
    - "shapes-implementation-decisions (no file mutation; behavioral influence)"
  failure-mode:
    - "rule-ignored | exit=n/a | visible=stochastic-orchestration-of-computable-ops | mitigation=/ccanvil-audit-flags-or-stasis-determinism-review"
  contract:
    - hierarchy-hook-then-script-then-slash-then-reasoning
    - never-claude-orchestrating-cp-diff-jq-shasum-git
    - inline-shell-in-settings-json-is-anti-pattern
  anchor:
    - BTS-252 (manifest seed)
    - BTS-385 (atomized for tier-0)
---

# Deterministic-First

When an operation is computable (same input → same output), it MUST be deterministic machinery — **hook → script → slash-command-with-script-calls → reasoning**, in that order of preference. Every token spent on deterministic ops is stolen from judgment calls that actually need a transformer.

**When adding automation, ask:**
- Can this step produce a wrong answer? If no → script/hook, not Claude.
- Does this step require code semantics? If no → script/hook, not Claude.
- Would a shell script do this identically every time? If yes → it should BE a shell script.

For the rationale (zero-sum attention argument), expanded hierarchy with examples, and anti-pattern catalog: see the evidence anchor `docs/research/deterministic-first-foundations.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
