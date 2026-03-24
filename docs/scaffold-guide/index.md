# Claude Code Scaffold — Guide

A visual, browsable guide to the scaffold system: how it works, when to use each feature, and the reasoning behind every design decision.

> **Why this scaffold exists:** Transformer attention is zero-sum. Every token in Claude's ~200K context window competes for attention weight. Performance degrades as context fills — starting at just 3,000 tokens. This scaffold manages that constraint through specification-driven development, test-driven verification, and hierarchical context management. Every feature described below traces back to this architectural reality.

---

## Sections

| Section | File | When to read |
|---------|------|-------------|
| System Overview | [system-overview.md](system-overview.md) | Understanding the scaffold's layered architecture |
| Getting Started | [getting-started.md](getting-started.md) | First-time machine setup or starting a new project |
| Core Workflow | [core-workflow.md](core-workflow.md) | The spec/plan/build/review cycle and TDD details |
| Session Management | [session-management.md](session-management.md) | Checkpoint, catchup, clear — managing context across sessions |
| Scaffold Sync | [scaffold-sync.md](scaffold-sync.md) | Hub/node architecture, pull/push flows, delimiters, guards |
| Command Reference | [command-reference.md](command-reference.md) | Looking up any slash command or script |
| Configuration Layers | [configuration.md](configuration.md) | What goes where: hooks vs rules vs skills |
| Hooks System | [hooks.md](hooks.md) | How hooks work, adding new hooks, deterministic-first principle |
| Decision Guide | [decision-guide.md](decision-guide.md) | When to use which command, when to checkpoint vs clear |
| Parallel Sessions | [parallel-sessions.md](parallel-sessions.md) | Running multiple agents via git worktrees |
| Research Foundation | [scaffold-framework.md](scaffold-framework.md) | Foundational research — transformer attention, TDD evidence, context management (read-only) |

---

**For the research basis behind every practice, see [scaffold-framework.md](scaffold-framework.md).**

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
