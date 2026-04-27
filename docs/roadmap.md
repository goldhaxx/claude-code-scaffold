# Roadmap

<!-- This is your project's strategic source of truth.
     Update it when direction changes, not every session.
     The /radar command reads this to contextualize tactical work. -->

## Vision

ccanvil makes AI-assisted development fast, reliable, and consistent across projects — by turning Claude Code from a capable but undirected tool into a disciplined development partner with guardrails, workflows, and shared practices that sync automatically. It is an operational layer: Claude Code is the compiler, ccanvil is the build system.

## Goals

1. **Near-zero approval overhead** — Claude works autonomously on routine operations; the operator only intervenes on genuinely consequential actions
2. **Frictionless sync** — hub changes propagate to downstream nodes with minimal manual effort; drift is detected automatically (drift-watchdog active)
3. **Reliable bootstrap** — `/init` works flawlessly on new and mature projects, every time
4. **Self-stabilizing system** — the determinism review loop, evidence-required-for-captures protocol, and dual-capture of candidates to Linear keep pushing stochastic operations and quality gaps into deterministic substrate

## Active Theme

**Autonomy & Friction Reduction** — remove the friction between intent and execution so that working with ccanvil feels effortless, not ceremonial.

*Status: active and ongoing.* The substrate-maturity arc (operations resolver, http substrate, lifecycle-state primitive, evidence protocol, drift-watchdog, permissions infrastructure) has materially closed several friction surfaces. **SSOT-Linear shipped end-to-end on 2026-04-27** (BTS-204 → BTS-213 → BTS-214 → BTS-216): the substrate routes specs/plans/stasis to Linear ticket bodies, deterministic v4 UUIDs round-trip through the live API, the route-aware `/spec` and `cmd_activate` paths dispatch correctly, and `_complete_archive_linear` runs in 5 calls instead of 6. The closing step is BTS-217 — flip routing on the hub to dogfood the flow on its own ships. **Theme-rollover criteria are not yet defined** — a separate effort will codify what "this theme is done" means before any rollover is declared.

## Maturity Signal (theme-agnostic)

A separate, durable measure of system maturity: **opening the project shows triage = 0, backlog = 0, icebox = 0 — and stays there.** New bugs, determinism candidates, and self-improvement requests stop arriving at a steady cadence because the substrate has converged. Today: 2 triage, 17 backlog, 2 icebox. Not there yet.

## Up Next

1. **BTS-217 — SSOT-Linear routing-flip dogfood** (in Triage). Operator-decision-only ship: flip `routing.{spec,plan,stasis}=linear` in the hub's `.claude/ccanvil.local.json` and dogfood the SSOT-Linear flow on its own next-feature lifecycle. Closes the BTS-204 arc loop — substrate is proven end-to-end against the live API, this is the demand-side validation step. ~30 minutes if no surprises. (P2)
2. **Determinism + skill-substrate gap cluster** — small ships closing self-stabilization gaps surfaced by recent dogfood: **BTS-202** (guard-destructive false-positive), **BTS-203** (evidence-scan-session description-fetch), **BTS-205** (silent dual-capture failure), **BTS-218** (radar-gather chokes on `--project-dir` flag), **BTS-211** (operations.sh exec doesn't dispatch http), **BTS-212** (subcommand fall-through on unknown flags). Each <2hr; co-shippable where touch-points overlap; together they form a release-shaped cluster (worth flagging when BTS-163 drainage check fires 2026-05-11). (P3 ×6)
3. **Dark Code / Three-Layer Solution** — evaluate Nate B Jones' framework for ccanvil integration. Three layers: (1) Spec-Driven Development (force comprehension before generation — ccanvil already does this; assess where it needs strengthening); (2) Self-Describing Systems (module manifests with structural + semantic context, failure modes, behavioral contracts readable by humans and AI — biggest gap today); (3) Comprehension Gate (review step where senior engineers + AI pose critical questions about design and dependencies). Source: https://www.youtube.com/watch?v=E1idsrv79tI. Full transcript review pending. Open as research first, then spec the actionable layer(s). (Needs-research → spec)

## Next Theme — Direction (not yet committed)

**Working idea: "Simplicity through leverage" — Raptor v1 → v3.** The visual: maximal efficiency, fewer parts, cleaner lines, an order-of-magnitude upgrade arrived at by removing the wrong things, not adding more.

Mechanism under exploration: **modular personality packs.** ccanvil supports pluggable frameworks — Musk, Bezos, Jobs, Lin-Manuel Miranda, etc. — each curated to encode an operator's worldview into ccanvil's behavior. A pack measurably affects:

- **Performance** — how aggressively the system optimizes for throughput vs. caution
- **Functionality** — which skills, hooks, and rules are active
- **Cadence** — pacing of work, batch size, ship rhythm
- **Decision-making** — defaults for tradeoffs (speed vs. correctness, scope vs. simplicity, etc.)
- **Operations** — gating, review thresholds, what gets challenged vs. accepted

Packs are **configurable at the node level**: the hub runs one personality, each downstream node selects its own. The first pack to curate: **Elon Musk** — distilled from *The Book of Elon* (essence, system, leverage, worldview).

Open questions for the future spec session:

- What's the canonical pack format? File layout, manifest, override mechanics?
- How do packs compose with the existing rules / skills / settings layers?
- Does a pack ship as a `.ccanvil/packs/<name>/` directory, or as a switchable bundle in `hub/packs/`?
- How is pack effect measured — does ccanvil track behavioral deltas before/after activation?
- What does "default ccanvil" become when no pack is active — neutral, or implicitly the operator's own pack?

Decide formally at theme rollover. Until then, this is direction, not commitment.

## Horizon

- **BTS-22: Docs directory strategy** — multi-file specs/plans/stasis to reduce write friction and enable parallel features. Likely subsumed or reshaped by SSOT-Linear; revisit after BTS-204. (Medium, needs-research)
- **Open-source packaging** — documentation, onboarding UX, multi-tool support. Conditions ("until tool stabilizes for personal use") approaching met; defer formal decision until next theme is named.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
