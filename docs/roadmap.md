# Roadmap

<!-- This is your project's strategic source of truth.
     Update it when direction changes, not every session.
     The /radar command reads this to contextualize tactical work. -->

## Vision

ccanvil makes AI-assisted development fast, reliable, and consistent across projects — by turning Claude Code from a capable but undirected tool into a disciplined development partner with guardrails, workflows, and shared practices that sync automatically. It is an operational layer: Claude Code is the compiler, ccanvil is the build system.

## Goals

1. **Near-zero approval overhead** — Claude works autonomously on routine operations; you only intervene on genuinely consequential actions
2. **Frictionless sync** — changes in the hub propagate to downstream projects with minimal manual effort
3. **Reliable bootstrap** — `/init` works flawlessly on new projects, every time
4. **Self-improving system** — the determinism review loop keeps pushing stochastic operations into scripts

## Active Theme

Autonomy & Friction Reduction — remove the friction between intent and execution so that working with ccanvil feels effortless, not ceremonial.

## Up Next

1. **Tech stack distribution** — distribute tech stack profiles (hooks, rules, CLAUDE.md sections) from hub to nodes. Init-time provisioning + patch-time application. First profile: FastAPI/SQLite with protect-db.sh and API-first rules. Spec written, ready to activate.
2. **Checkpoint evolution** — evaluate whether checkpoint is still needed given `/compact`, `/catchup`, and auto-memory; may evolve into decision log or be retired

## Horizon

- **Dark code / Three-Layer Solution** — evaluate Nate B Jones' framework for ccanvil integration. Three layers: (1) Spec-Driven Development (force comprehension before generation — ccanvil already does this but may need strengthening); (2) Self-Describing Systems (module manifests: structural + semantic context, failure modes, behavioral contracts readable by humans and AI — biggest gap); (3) Comprehension Gate (review step where senior engineers + AI pose critical questions about design and dependencies). Source: https://www.youtube.com/watch?v=E1idsrv79tI. Full transcript review pending. (Medium, needs-research)
- **BTS-22: Docs directory strategy** — multi-file specs/plans/checkpoints to reduce write friction and enable parallel features (Medium, needs-research)
- **BTS-20: Workflow engine** — deterministic state machine for lifecycle transitions; depends on lifecycle primitives stabilizing (Low, needs-research)
- **BTS-21: GitHub Agentic Workflows** — evaluate gh-aw integration once it reaches GA (Low, needs-research)
- **Lifecycle timing** — branch creation before or after spec; the full chain may be idea → branch → spec → plan → implement → complete → merge → land
- **Open-source packaging** — documentation, onboarding UX, multi-tool support; deferred until tool stabilizes for personal use

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
