---
tier: 0
scope: universal
stack: any
anchors:
  evidence:
    - docs/research/background-task-incident.md
---

# Background Task Discipline

Background tasks (long-running tests, validators, builds) are an expensive resource. Treat them with budget discipline:

1. **No `until <ps-grep>; do sleep N; done` wait-loops.** Use the harness's task-completion notification instead.
2. **No multiple parallel runs of the same long command.** One test invocation, one validator run — never stack them.
3. **Buffered output is not a hung process.** Many test runners and validators fully buffer stdout — the file shows 0 bytes for the full duration, then dumps everything at completion. Do not assume hang and start another invocation.

For the rationale (premature-wait-loop-firing, output-buffering-misread-as-hang, wait-loops-are-themselves-background-tasks), the anti-pattern catalog, and the BTS-383 origin incident: see evidence anchor `docs/research/background-task-incident.md`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
