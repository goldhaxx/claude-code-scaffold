# Dark Code → ccanvil mapping

> Research lap for Dark Code / Three-Layer Solution theme.
> Phase: 1 (research, no implementation).
> Source video: https://www.youtube.com/watch?v=E1idsrv79tI ("I Looked At Amazon After They Fired 16,000 Engineers. Their AI Broke Everything.") — Nate B Jones.
> Convergent written sources used (transcript not directly fetchable):
> - SOCFortress, *Driving into the Void: Amazon's $100M Autopsy of the "Dark Code" Crisis* (Medium, Apr 2026) — direct summary of the video's thesis and three-layer solution.
> - Addy Osmani, *Comprehension Debt: The Hidden Cost of AI-Generated Code* (O'Reilly Radar / addyosmani.com, Mar 2026) — counter-evidence on the limits of specifications.
> - Nate B Jones, *5-level framework / dark factory* (natesnewsletter.substack, paywalled — only the public excerpt was usable).

## 1. Thesis

**Dark code** is "code that was never understood by anyone at any point because it was made by AI" — code that ships, passes tests, and runs in production while no human on the payroll understands what it does. The decoupling of **authorship** from **comprehension** is the core failure mode. Manual coding forced cognitive processing of logic; AI-native workflows skip the labor and skip the understanding.

Amazon's outage class (high-blast-radius, gen-AI-assisted changes; mandatory code-signoff for senior engineers post-incident) is the load-bearing example. The autopsy framing: *"Do you have mechanisms in place to make your code legible, or are you driving into the dark with your headlights off?"*

**Counter-evidence (Osmani):** specifications alone don't fix this. *"A spec detailed enough to fully describe a program is more or less the program."* Requirements emerge through building; specs miss implicit edge cases and tradeoffs. Tests are necessary but insufficient — "tests passed" ≠ "I understand what this does and why." The methodology matters more than the artifact: passive delegation scores <40% on comprehension tests; conceptual inquiry scores >65%.

**Synthesis for ccanvil:** the three-layer framing is right *as a structural target*, but Layer 1 is not done by specs alone, Layer 2 manifests must be lightweight enough not to drift, and Layer 3 must ask architecture-shaped questions, not file-shaped ones.

## 2. The three layers

| Layer | Question answered | Artifact | Where in workflow |
|------|------|------|------|
| **1 — Spec-Driven Development** | What is supposed to exist, before generation? | Acceptance criteria, requirements, "spec becomes the eval" | Pre-implementation |
| **2 — Self-Describing Systems** | What does this module do, depend on, and break under? | Module manifests with structural / semantic / behavioral context | Co-located with code |
| **3 — Comprehension Gate** | Is this architecturally sound? | Architecture-level review (not line-level) | Pre-merge |

Layer 2 is the load-bearing layer. It is itself decomposed into three sub-contexts (the autopsy article uses "three layers of context" inside Layer 2):

- **Structural (Where):** module manifest — purpose, dependencies, downstream dependents.
- **Semantic (What):** interfaces, performance expectations, failure modes, retry semantics, behavioral contracts.
- **Comprehension Gates (sub-layer):** architectural-legibility filter — *not* the same as Layer 3 above; this is where the manifest answers the architectural questions Layer 3 asks.

This structural ambiguity (Layer 3 is also a sub-layer of Layer 2) is in the source material itself. ccanvil should treat them as one continuous gate: manifests carry the answers; the review reads them.

## 3. Current-state assessment

### Layer 1 — Spec-Driven Development

**Coverage: ~80% — strongest layer.**

ccanvil already enforces:
- `/spec` skill writes `docs/specs/<feature_id>.md` with acceptance criteria (binary pass/fail) before any code.
- `> Subject:` metadata field auto-populates from H1 (BTS-236).
- `> Work:` metadata anchors specs to provider IDs (Linear / local).
- `docs-check.sh activate` enforces spec-exists-before-branch-creation.
- `/plan` decomposes acceptance criteria into TDD-sized steps with hash-binding to spec.
- `evidence-required-for-captures` rule (BTS-201) refuses bug-shape captures without `Command:/Output:/Exit:/Reproduce:` anchors — extends spec discipline upstream into capture.
- `live-API validation gate` (BTS-171) prevents stub-only verification of contract risks — extends spec discipline downstream into impl.

**Where it leaks:**
1. **Specs may go un-read.** Operator routinely "approves" a Claude-drafted spec without close review — if the spec is wrong, downstream TDD will be wrong-in-the-same-direction. Comprehension is bypassed even when the artifact exists.
2. **Spec→plan handoff is Claude-internal.** No second pair of eyes between "here are the ACs" and "here are the test files I will write." The plan can drift from the spec's intent without anyone noticing.
3. **`/spec`'s own template is loose.** ACs are required but the structural shape (Given/When/Then, error/edge case coverage, file references) is enforced only by template prose, not by a structural validator.
4. **The Osmani counter-evidence applies.** ccanvil specs are deliberately ≤100 lines; this is correct policy but means ACs cannot fully describe non-trivial behavior. That gap is what Layer 2 must fill.

**Implication:** Layer 1 doesn't need a major reshape. It needs (a) a comprehension-forcing checkpoint between spec and plan, and (b) Layer 2 manifests to fill the implicit-decisions gap that 100-line specs leave open. Most leaks here close once Layer 2 lands.

### Layer 2 — Self-Describing Systems

**Coverage: 100% — fully shipped 2026-04-29 (BTS-239 → BTS-256).**

Original assessment (~10% coverage) is preserved below for historical reference. The 11-session rollout (`docs/manifest-rollout.md`) shipped the substrate (BTS-239), markdown frontmatter parser (BTS-240), file-level shell fallback (BTS-251), SIGPIPE-resistant body grep (BTS-252), and 184 manifests across every operator-callable substrate primitive. Bidirectional drift-guard (caller / depends-on / failure-mode / side-effect markers) catches regressions structurally on every `/recall` and `/review`.

**What follows is the original assessment — kept verbatim for context.**

**Coverage: ~10% — biggest gap.** *(Historical — superseded by the 100% shipment above.)*

ccanvil substrate is dense (~51 `cmd_*` primitives in `docs-check.sh` alone) and currently *describes itself only through prose in scripts, skill markdown, and rules files*. Any of these:

- A future-Claude reading `cmd_artifact_write` cold has no canonical "what does this do, what are its failure modes, who calls it, what does it depend on" — must reverse-engineer from code.
- A future-Claude editing `cmd_ship_finalize` has no manifest of "callers depend on the post-merge AUTO-CLOSE marker emitted on stdout"; that contract lives only in `/land`'s skill prose.
- A future-Claude composing a new resolver in `operations.sh` has no machine-readable schema for the resolver envelope; the shape lives in `case` branches and ad-hoc test fixtures.

**Examples of contracts that are currently implicit:**

| Primitive | Implicit contract that should be a manifest field |
|------|------|
| `cmd_artifact_write` | Routes by `integrations.routing.<kind>`; on Linear path, retries once on concurrent-edit; falls back to pending log; CREATE skips updatedAt cache (BTS-237). |
| `cmd_ship_finalize` | Emits `AUTO-CLOSE: {json}` on stdout for caller to parse; exits 0 even on Linear-side failure; pending-log fallback. |
| `cmd_idea_pending_replay` | Drains both `ideas-pending.log` and `dual-capture-emergency.log` (BTS-233); emits `{synced, failed, pending, emergency_pending}`; idempotent on Linear creates (caveat: Linear doesn't dedup, so replay may double-capture). |

Each of these has been hard-won — multiple sessions spent uncovering them via dogfood. They are **load-bearing tribal knowledge** that future-Claude (or a new operator) can only acquire by walking through the same incidents.

**The substrate maturity that drove the Stabilization theme** (session 9: 9 ships in one turn at near-zero defect surface) is the strongest possible evidence that Layer 2 is the right next investment. The substrate IS coherent now; what's missing is its self-description.

### Layer 3 — Comprehension Gate

**Coverage: ~55% — Layer 3 prose ramp landed in BTS-257 (2026-04-29). Original ~40% assessment preserved below for context.**

The BTS-257 ramp augmented the `code-reviewer` agent + `/review` skill with manifest-aware drift checks: every PR review runs `module-manifest.sh validate` as a pre-flight and Claude flags four classes of architecture-shaped change (new caller / new dep / new failure-mode / new side-effect not declared in the touched manifest). This is a prose-layer ramp — the Comprehension Gate now reads manifests as the canonical contract for review.

**Phase 2 (to ramp Layer 3 from ~55% to fully structural):** convert the prose nudge to a deterministic check primitive (e.g., `module-manifest.sh diff-vs-manifest --diff <git-diff>`) so drift findings ride as machine-readable JSON rather than agent prose. Tracked as a future ticket; not blocking.

**Original assessment follows verbatim.**

**Coverage: ~40% — partial.** *(Historical — superseded by the ramp above.)*

ccanvil already has:
- `code-reviewer` agent (`/review` skill, also gated by `pr_review` config in `.claude/ccanvil.json`) — runs file-level checks for correctness/security/conventions.
- `security-audit.sh` — deterministic secret/PII scan.
- `bats-report.sh` — single-invocation test verification.
- `permissions-audit.sh` — DANGER classification with `accept_danger` rationale tracking.
- Hub guards: `protect-main.sh`, `guard-force-push.sh`, `guard-destructive.sh` — refuse-by-default for blast-radius operations. (BTS-602 retired `guard-workspace.sh`, the path-locality fence, when the cost-benefit on its false-positive carve-out tail inverted.)

**Where it leaks:**
1. **All gates are file-shaped.** None ask "what new architectural risks does this PR introduce?" or "are we creating new monolithic coupling?" The reviewer agent is good at "this function lacks error handling" — not at "this function couples X to Y in a way the system has been deliberately avoiding."
2. **No manifest-aware review.** Without Layer 2, even an architecturally-aware reviewer has no canonical reference to compare against ("does this PR's claimed contract match the manifest's stated contract?").
3. **The dogfood pattern partially substitutes.** Live-AC gates (BTS-237 fix proven on BTS-207, BTS-236 fix proven on every subsequent ship) catch architectural-failure-modes cheaply. This is *empirical comprehension gate* — the next ship validates the prior ship's contract by actually using it. It's working, but it's reactive (catches errors after merge), not preventative.

**Implication:** Layer 3 should ramp *after* Layer 2 lands. Architecture-level review without manifest-as-reference is just a reviewer asking better questions, which doesn't scale. Manifest-as-reference makes the review structural and deterministic.

## 4. First-ship scope (recommendation)

**Ship: module-manifest format + parser + manifests for 3 seed primitives.**

**Open question to resolve in spec:** where do manifests live?

| Option | Pro | Con | Verdict |
|------|------|------|------|
| **A. In-source structured comment block** above each `cmd_*` function | Lives next to code; one file to update; easy to grep | Mixes human prose with machine schema; harder to validate by schema | **Lean toward A.** Drift risk lowest when source-and-manifest are visually adjacent. |
| **B. Sibling `.ccanvil/manifests/<verb>.yaml`** | Clean schema; easily templated; CI-validatable | Drift risk highest — manifest and source diverge silently as code evolves | Reject for v1. |
| **C. Centralized `.ccanvil/substrate-manifest.json`** keyed by verb | Single queryable index; great for `/recall` cold-starts | Maximum drift; far from source; one merge conflict per simultaneous edit | Reject for v1. |

**Format sketch (A):**

```bash
# @manifest
# purpose: Provider-aware write of feature artifact (spec/plan/stasis).
# routes-by: integrations.routing.<kind> (local | linear)
# callers: cmd_stamp_spec, cmd_complete, /spec skill, /stasis skill
# depends-on: linear-query.sh, _doc_cache_get/set, cmd_lookup_ticket_by_feature
# side-effects:
#   - local path: writes docs/(spec|plan|stasis).md or docs/specs/<id>.md
#   - linear path: upserts Linear Document via save-document mutation
#   - emits structured failure to .ccanvil/state/artifact-write-failures.log
# failure-modes:
#   - concurrent-edit (Linear): one auto-retry; ALLOW_CONCURRENT_EDIT_OVERRIDE=1 envelope
#   - missing LINEAR_API_KEY: exits 3 with stderr message
#   - cache-staleness: CREATE path skips _doc_cache_set_updated_at (BTS-237)
# contract:
#   - input: stdin (artifact body)
#   - flags: --kind, --feature, --stasis-kind, --project-dir
#   - exit-codes: 0 ok / 2 validation / 3 dispatch / 4 retry-exhausted
# anchors: BTS-204 (origin), BTS-237 (CREATE-cache fix)
cmd_artifact_write() {
  ...
}
```

**Substrate verbs to ship alongside:**
- `docs-check.sh manifest-extract <verb>` — parse comment block, emit JSON.
- `docs-check.sh manifest-coverage` — scan all `cmd_*`, report which lack `# @manifest`. Drift-guard test asserts coverage ≥ N% for a stable allowlist.
- `docs-check.sh manifest-validate` — assert each manifest's `callers` and `depends-on` actually match grep-of-source. Bidirectional drift detection.

**Three seed primitives** (per stasis Next Steps):
1. `cmd_artifact_write` — exercises the most contracts (provider routing, concurrent-edit guard, fallback chain).
2. `cmd_ship_finalize` — exercises stdout-marker contract + cross-skill dependency (`/land` parses output).
3. `cmd_idea_pending_replay` — exercises the multi-log drainage contract + idempotency caveat.

**Self-application (dogfood-as-validation):** the manifest format ships with its own manifest demonstrating the layer. The `manifest-extract` and `manifest-coverage` primitives ship with manifests describing themselves. If the format can't describe its own substrate, it isn't load-bearing enough.

## 5. Phase plan (refined)

1. **Spec the first ship.** `BTS-XXX: module-manifest format + parser + 3 seed primitives.` Acceptance criteria include: manifest format documented in `.ccanvil/templates/manifest.md`; parser primitive shipped with bats coverage; 3 seed primitives carry manifests; drift-guard test enforces format-of-record.
2. **Implement.** TDD per usual. Live-AC gate: the first ship's PR title rendering should itself reference the manifest field added to `cmd_stamp_spec` (dogfood).
3. **Iterate.** Each subsequent ship adds manifests to existing primitives. Track coverage in `/stasis` ("`manifest-coverage`: 12 / 51 covered").
4. **Layer 3 ramp** (later, after coverage > 50%). Augment `code-reviewer` agent with manifest-aware checks: "this PR adds a callsite to `cmd_X` not listed in its manifest's callers" — CI-level, not just suggestion.

**Capture rule under this theme** (from roadmap): bug captures unchanged (evidence-required); speculative/optimization captures allowed in Triage; new substrate primitives in scope when they advance Layer 1/2/3; WIP-limit one active spec at a time. **Live-throughput guard: >2 captures/week = re-stabilize signal, pause Dark Code.**

## 6. Decisions deferred to spec

- Exact comment-block format (YAML-ish vs JSON-ish vs custom delimiters).
- Drift-guard threshold (warn-only vs hard-fail-CI).
- Whether to emit a global JSON index from per-source manifests (a derived artifact, regenerated on demand — has cache-staleness risk but enables fast queries from `/recall`).
- Ordering of seed primitives if all 3 don't fit in one ship.

## 7. Anchors

- Theme rollover: end of session 9 (2026-04-27); `docs/roadmap.md` Active Theme block.
- Source video: https://www.youtube.com/watch?v=E1idsrv79tI.
- Companion sources: SOCFortress Medium piece (Apr 2026); Osmani comprehension-debt counter-evidence (Mar 2026).
- Substrate maturity proof: session 9 stasis (`docs/sessions/1777345200-session-2026-04-27-stabilization-drained-darkcode-rollover.md`) — 9 ships in one turn validates the Layer 2 substrate-as-coherent-target premise.
- Existing partial coverage: Layer 1 (`/spec`, `/plan`, `evidence-required-for-captures`, `live-API gate`); Layer 3 (`code-reviewer` agent, `pr_review` config, hub guards).
