---
tier: 0
scope: universal
stack: any
anchors: {}
---

# Leak Outside Anchor

This rule body mentions `bats-report.sh` directly in the universal section,
which violates the abstraction discipline.

## Anchored on (ccanvil hub)

Hub-specific tokens here are exempt.
