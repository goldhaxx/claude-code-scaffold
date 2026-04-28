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

**Dark Code / Three-Layer Solution** — addressing the operator/code-intuition disconnect that surfaces when autonomous-shipping reaches substrate maturity. Adapted from Nate B Jones' framework: (1) Spec-Driven Development (force comprehension before generation — ccanvil already does this, assess where it needs strengthening), (2) Self-Describing Systems (module manifests with structural + semantic context, failure modes, behavioral contracts readable by humans and AI — biggest gap today), (3) Comprehension Gate (review step where senior engineers + AI pose critical questions about design and dependencies).

*Started: 2026-04-27 (session 9, end-of-conversation rollover).* Reason: Stabilization & Maturation theme exit criteria met (backlog/triage = 0, 9 fixes shipped in one turn validating substrate maturity). The remaining theme-rollover-blocker — code-intuition disconnect — is precisely what Dark Code addresses. The two themes connect: stabilization proved the substrate works autonomously; Dark Code keeps the operator connected to that substrate as it evolves.

**Source material:** https://www.youtube.com/watch?v=E1idsrv79tI. Transcript review pending — first ship is research, not implementation.

**Phase plan:**

1. **Research lap.** Read the Nate B Jones video transcript end-to-end. Map each of the three layers to ccanvil's current shape:
   - Layer 1 (Spec-Driven): is the existing /spec → /plan → impl flow strong enough? Where does it leak?
   - Layer 2 (Self-Describing): does any ccanvil substrate carry behavioral-contract metadata? What would a module manifest look like for a substrate primitive (cmd_artifact_write, ship-finalize, etc.)?
   - Layer 3 (Comprehension Gate): how does this interact with /review and code-reviewer agent? Is the gate before-spec, before-merge, or both?
2. **Spec the actionable layer(s).** Likely Layer 2 first — biggest current gap, highest leverage for the operator-disconnect concern. Spec a manifest format + a substrate primitive to enforce/parse it.
3. **First ship.** Self-describing by construction: the manifest format ships with its own manifest demonstrating the layer it implements. Dogfood-as-validation.
4. **Iterate.** Each subsequent ship adds manifests to existing substrate primitives, with incremental coverage tracked in /stasis.

**Capture rules** — relaxed from stabilization, but still disciplined:

- Bug captures: same evidence-required protocol (BTS-201).
- Speculative/optimization captures: now allowed in Triage (not auto-Iced).
- New substrate primitives: in scope when they advance Layer 1/2/3.
- WIP-limit: still one active spec at a time. No parallel theme work.

**Live signal — stabilization holding:**

If new captures land at >2/week cadence during this theme, that's the signal stabilization didn't actually converge. Pause Dark Code work and re-stabilize. The 14-day-soak guardrail from the prior theme is replaced by this live throughput check.

**Stabilization & Maturation theme — completed 2026-04-27.** 9 ships in one turn (BTS-215, 238, 237, 207, 211, 236, 209, 208, 183). Tests 1826 → 1839 (+13 net after dead-code sweep). Backlog 13 → 0. Drift-watchdog cluster (BTS-191–197) canceled. http-canonical rule codified in `.claude/rules/provider-integration.md`. `/ship` substrate (BTS-235) and `> Subject:` metadata (BTS-236) made the autonomous lifecycle reliably end-to-end.

## Maturity Signal (theme-agnostic)

A separate, durable measure of system maturity: **opening the project shows triage = 0, backlog = 0, icebox = 0 — and stays there.** New bugs, determinism candidates, and self-improvement requests stop arriving at a steady cadence because the substrate has converged. Today: 0 triage, 0 backlog, 2 icebox. Within reach.

## Up Next — Dark Code Phase 1

1. **Research lap** — read the Nate B Jones video transcript end-to-end. Map the three layers to ccanvil's current shape (questions in the Active Theme block above). Output: a research note in `docs/research/dark-code-mapping.md` (or similar) with one section per layer, current-state assessment, and proposed first-ship scope.

2. **Spec the first ship** — likely Layer 2 (Self-Describing Systems / module manifests). Open question: does the manifest live in-source as a comment block, in a sibling `.manifest.yaml`, in the ccanvil substrate metadata, or somewhere else? Research lap should answer.

3. **Implement the first ship** — manifest format + parser/validator + manifests for ~3 substrate primitives as the seed examples (likely cmd_artifact_write, cmd_ship_finalize, cmd_idea_pending_replay — the three that exercise the most contracts).

4. **Soak observation** — track new-capture cadence as Dark Code ships land. If captures stay <2/week, stabilization held and Dark Code's substrate growth is offset by its disconnection-prevention value. If captures spike, pause and re-stabilize.

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
