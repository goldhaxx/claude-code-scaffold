# Stasis

> Feature: session-2026-04-29-manifest-rollout-complete
> Kind: session
> Last updated: 1777498200
> Session: 16
> Boundary: 2026-04-29T09:16:03-07:00
> Session objective: Finish the manifest rollout in one heads-down day. Ship Sessions 8 → 11 (BTS-251 / 252 / 256 / 257). Close out `docs/manifest-rollout.md` as a historical record. Land Layer 2 at 100% coverage and Layer 3 prose ramp.

## Accomplished

* **Four sessions shipped in one heads-down day.** BTS-251 / BTS-252 / BTS-256 / BTS-257 squash-merged via `/ship`. Each followed full lifecycle: capture → /spec → /activate → batched manifests → per-batch validate-fix-commit → /pr → /ship.
* **BTS-251 (PR #146) — file-level shell + hooks.** 17 file-level manifests (5 single-purpose scripts + 12 hooks). Substrate fix shipped alongside: `_function_body_grep` file-level fallback (whole-file grep when no `${fn_id}()` decl). Allowlist 134 → 151. Drift 0.
* **BTS-252 (PR #147) — markdown skills + rules.** 14 YAML-frontmatter manifests (8 skills + 6 rules). **Substrate fix shipped alongside (BTS-252):** SIGPIPE-resistant `_target_body_grep` — original `awk | grep -qE` pipeline tripped under `set -o pipefail` when grep -q matched early; fix captures awk output to a var first, then greps. Caught while authoring `idea` skill manifest (305-line body, multiple early matches). Regression test landed under `hub/tests/module-manifest-markdown-validate.bats`. Allowlist 151 → 165.
* **BTS-256 (PR #148) — markdown agents + commands.** 19 YAML-frontmatter manifests (4 agents + 15 commands). Allowlist 165 → 184. Drift 0. **Manifest coverage hit 100% (184/184).**
* **BTS-257 (PR #149) — Layer 3 ramp + close-out.** Augmented `code-reviewer` agent + `/review` skill with manifest-aware drift checks (4 classes: new caller / new dep / new exit path / new side-effect not declared). Closed `docs/manifest-rollout.md` with `Status: COMPLETE` + per-session ledger. Updated `docs/research/dark-code-mapping.md` Layer 2 `~10%` → `100%` and Layer 3 `~40%` → `~55%`. Updated `docs/roadmap.md` Dark Code Phase 1 → SHIPPED with Phase 2 candidates enumerated.
* **One-week verification routine scheduled.** `trig_01V3eu7T8WurLRzg1iSPSA3j` fires once at 2026-05-06T16:00Z (Wed 9am PT) — audits how the BTS-257 Layer 3 prose ramp performed on real PRs, opens a Linear ticket with findings + recommendation (deterministic Phase 2 / leave-as-is / tune-prose).

## Current State

* **Branch:** `main`, fast-forwarded to origin (`6973a12`). Working tree clean.
* **Tests:** **1926 / 1926 passing.** Net delta this session: 1923 → 1926 (+2 BTS-251 file-level fallback regression tests, +1 BTS-252 SIGPIPE-resistance regression test).
* **Uncommitted changes:** none.
* **Build status:** clean.
* **Manifest coverage: 184 / 184 (100%), drift 0.** Every operator-callable substrate primitive is self-describing.
* **Backlog: 0 / Triage: 1** (BTS-247 — context-budget.sh model registry investigation, carried over) **/ Icebox: 2** (BTS-22, BTS-21).

## Blocked On

Nothing.

## Next Steps

**Open questions + decisions to take into next session (operator-flagged at session boundary):**

1. **Phase 2 candidates from `roadmap.md` are NOT on a path to completion.** They live as prose in `docs/roadmap.md`, not as Linear tickets — they will evaporate at the next theme rotation. Operator asked: "is this in our path that ensures we will keep it in focus and complete the work?" **Answer: no.** Recommended action: capture each as a Linear idea (Triage state) at the start of next session so they show up in `/recall`, `/radar`, `/idea triage`. Five tickets to capture:
   - **(L3-A) Deterministic Layer 3 ramp** — `module-manifest.sh diff-vs-manifest --diff <git-diff>` primitive that emits structured `{path, id, drift_type, value}` JSON. Reviewer agent + `/pr` substrate consume deterministically. Closes the ~55% prose-only gap.
   - **(L3-B) Cross-substrate cohesion graph** — graph view of caller/depends-on edges across all 184 manifests. Surfaces architecture-shaped change ("this PR adds an edge that crosses two clusters that have been kept disjoint"). Closes the file-shaped-vs-architecture-shaped gap.
   - **(L3-C) Manifest query helpers** — `module-manifest.sh query --by-side-effect writes-to-disk` etc. Powers `/recall` cold-starts and `/radar` strategic briefings.
   - **(L1-A) `docs-check.sh validate-spec --feature <id>` primitive** — gates AC count, Given/When/Then coverage, error-criterion presence, file-reference resolution. Closes Layer 1's L1-C (loose template) gap.
   - **(L1-B) `/spec --review` critic-mode hand-off** — spawn `spec-writer` agent in critic mode after operator approval; agent reads spec and returns one BLOCKING finding when it spots ambiguity. Closes Layer 1's L1-A (specs-go-unread) and L1-B (Claude-internal handoff) gaps.

2. **Layer 1 → 100% path** (operator question: "how do we get layers 1 and 3 to 100%?"). Layer 1 currently ~80% with four named gaps in `docs/research/dark-code-mapping.md` §3. L1-A + L1-B + L1-C close via the two Layer 1 tickets above. L1-D (specs ≤100 lines can't fully describe non-trivial behavior) is by-design and now load-bearing for Layer 2 — already shipped at 100%, so L1-D is structurally closed.

3. **Layer 3 → 100% path.** Layer 3 currently ~55% (post-BTS-257 prose ramp). The three Layer 3 tickets above (L3-A deterministic, L3-B cohesion graph, L3-C query helpers) close it. **L3-A is the highest-leverage** — converts the prose nudge to machine-readable JSON, scales without false-positive accumulation. The 1-week verification routine (trig_01V3eu7T8WurLRzg1iSPSA3j) will produce evidence about whether to commit Phase 2 immediately or stage it.

4. **Triage BTS-247** — context-budget.sh model registry decision (delete vs wire vs JSON config) carried over from S14 stasis. Cleanest fork is delete; recommendation in the BTS-247 body.

5. **Phase 2 commit-or-rotate decision** (after the 5 tickets above are captured + 1-week verification report lands). Options: (a) commit Phase 2 — drive Layer 1 + 3 to 100% in 3-5 sessions; (b) rotate to next theme ("Simplicity through leverage" — modular personality packs per `roadmap.md`) and let Layer 3 fully ramp organically over time; (c) hybrid — capture Phase 2 work in the backlog but rotate now and pick up when manifest-aware review starts producing real false-positives. Operator decides at next session start.

## Context Notes

* **Compounding velocity at substrate maturity (sustained).** Four sessions in one heads-down day, on top of four sessions in one conversation the prior day. Eight total ships in two consecutive heads-down days. Substrate maturity compounds quality discipline AND velocity — confirmed across 11 consecutive sessions of the manifest rollout.
* **Two substrate fixes mid-rollout — both caught by dogfood.** BTS-251 file-level fallback was caught while writing the spec (read of `_function_body_grep` revealed file-level shell would always drift). BTS-252 SIGPIPE-resistant body grep was caught while authoring the `idea` skill manifest (large body, depends-on grep returned non-zero despite obvious match). Both are textbook examples of `feedback_dogfood_probe_as_thesis_test` — operator dogfood probes and authoring-time validation catch what stubs miss.
* **The `caller:` field is conditional, not required.** Recurring drift this session: I declared callers (`skill:/ccanvil-init`, `skill:/ccanvil-push`, `.claude/rules/workflow.md` for ship) that didn't actually grep-resolve, then had to remove. Lesson: if a primitive is operator-invoked-only (no programmatic caller), OMIT the `caller:` field entirely. Don't aspirationally declare callers that don't yet exist; let drift-guard's "caller-not-found" be the source of truth on what actually invokes what.
* **Bash tool background-output flakiness during long bats runs.** Several `bats-report.sh --parallel` invocations completed but produced empty output files (UI showed "completed exit 0" but file was 0 bytes). Root cause unknown — likely a race between the harness's output capture and the long-running process. Workaround: redirect to a known-path log file in CWD, then `cat` it back. Tracked as a determinism candidate below.
* **Eight "open shells" in the harness UI.** Operator-flagged at session-end: these are background `Bash` tool invocations from the bats-debugging detour whose UI placeholders haven't cleared. Most are completed-but-not-cleaned-up. One zombie `module-manifest.sh validate` ran to completion just before stasis. Harmless; they'll clear at session reset. If this becomes a recurring pattern across sessions, we should investigate whether it's a Claude Code Bash-tool lifecycle bug worth filing upstream.
* **The 1-week verification routine is gated on real PR throughput between 2026-04-30 and 2026-05-06.** If 0 PRs land that touch manifested code in that window, the audit will be inconclusive. The routine prompt anticipates this and recommends a 2-week re-run if so. Operator should expect possibly-inconclusive verification on first fire.
* **Manifest rollout doc is now historical.** `docs/manifest-rollout.md` carries `Status: COMPLETE` + per-session ledger; future Layer 2 maintenance is per-substrate (manifest co-located with code in same PR). The doc is preserved as evidence of the 11-session program, not as a live planning surface.

## Determinism Review

* operations_reviewed: ~190 (4 sessions × 3-5 batches × ~10 manifest-edit ops + per-batch validate-fix-commit cycles + 1 substrate-fix cycle)
* candidates_found: 2

* **bats-report-parallel-output-flakiness**: Several `bash .ccanvil/scripts/bats-report.sh --parallel` background invocations during the BTS-252 / BTS-256 verify cycles produced empty output files despite reporting `completed exit 0`. Root cause unknown — likely a race between the harness's output-capture lifecycle and the multi-minute parallel-bats run, possibly related to pipefail signal-handling in the wrapper. Should be a deterministic improvement: either (a) `bats-report.sh` writes to a hardened tempfile before emitting to stdout (resilient to caller redirect timing), or (b) the wrapper detects empty stdout and re-runs once before returning. Impact: medium — the empty-file path made me reach for foreground retries 3× before getting a full pass-fail count, costing ~5min wall-time per occurrence.
* **manifest-author-caller-conservativism-rule**: I declared callers in 4-5 manifests this session (`skill:/ccanvil-init`, `skill:/ccanvil-push`, `.claude/rules/workflow.md`, etc.) that didn't grep-resolve. Drift-guard caught them all and I removed each. The pattern is recurring across the rollout: manifest authors aspirationally declare callers that "should exist" rather than ones that grep-prove. Should be a deterministic improvement: an authoring-time hint (or a `module-manifest.sh suggest-callers <fn>` primitive) that pre-greps `cmd_X` and the verb form `X-form` against `.claude/{skills,commands,rules,agents}/` and `global-commands/` and surfaces the actual callers BEFORE drift-guard has to reject them. Impact: medium — would have shaved ~2min per manifest across 50 manifests this session, plus removes a recurring class of self-correction.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

184 / 184 (allowlist), drift incidents: 0

## Cross-Session Patterns

* **CONFIRMED RECURRING (Sessions 8-11 of Dark Code era): drift-guard-as-quality-substrate.** The substrate caught two latent substrate bugs this session that would never have surfaced without the manifest authoring forcing real exercise (file-level fallback + SIGPIPE-resistance). This is the strongest pattern in the rollout — manifest authoring is itself a dogfood probe. 13th consecutive session-class with this pattern.
* **CONFIRMED RECURRING: substrate-on-substrate compounds across phases.** BTS-239 enabled BTS-240; BTS-240 enabled BTS-241/242/243/244/245/246; BTS-251 enabled BTS-252; BTS-252 enabled BTS-256; BTS-256 enabled BTS-257. Each session's manifest substrate fix unblocked the next session's manifest authoring at scale. Self-describing systems describing their own substrate, NOW AT 100% coverage.
* **NEW (this conversation): two-substrate-fix-mid-rollout via authoring dogfood.** BTS-251 + BTS-252 substrate fixes both surfaced from authoring-time validation, NOT from prior planning. Lesson: manifest authoring at scale IS the integration test for the manifest substrate. Future Layer 2 rollouts (e.g., into downstream nodes) should expect 1-2 substrate fixes per ~50-100 manifests authored.
* **No legacy-refs surfaces.** `legacy-refs-scan` returned `[]`.
* **Manifest coverage growth: 134 → 151 → 165 → 184 over four shipments in one day.** Final state: 184/184 (100%). The rollout closed by reaching the upper-bound number set in BTS-239's original 184-unit inventory.

## Security Review

* **All ship work was inline manifest declarations + the BTS-251 + BTS-252 substrate fixes** — no new auth surfaces, no new secrets paths.
* `module-manifest.sh` extension: file-level fallback in `_function_body_grep` (no behavior change for existing manifests; only adds whole-file fallback when no `fn_id()` decl). SIGPIPE-resistant `_target_body_grep`: pure pipe-handling refactor, no behavior change for the matching path.
* `code-reviewer` agent + `/review` skill: prose additions only — no new permissions, no new tool calls beyond the existing `module-manifest.sh validate` invocation (which is read-only).
* No secrets introduced. No new API surfaces. Production security-audit pre-existing findings unchanged.
* **Verdict: PASS.**

## Memory Candidates

* **NEW MEMORY CANDIDATE:** `feedback_omit_aspirational_callers_in_manifests` — When authoring a manifest's `caller:` field, only declare callers that grep-resolve via `_caller_actually_calls_primitive`. Don't declare aspirational callers ("this skill should call this primitive"). If a primitive is operator-invoked-only (no programmatic caller), OMIT the `caller:` field entirely (it's conditional, not required). Drift-guard catches violations but the round-trip costs ~2min per manifest. Worth saving as feedback to short-circuit the recurring self-correction pattern.
* **NEW MEMORY CANDIDATE:** `feedback_manifest_authoring_is_substrate_dogfood` — Authoring manifests at scale (~50/session) IS the integration test for the manifest substrate. Two latent bugs (file-level fallback gap, SIGPIPE-resistance) surfaced this conversation that pre-rollout test fixtures missed. Future Layer 2 rollouts (e.g., into downstream nodes) should expect 1-2 substrate fixes per ~50-100 manifests authored. Useful for sizing future rollout-program estimates.
* **NEW PROJECT MEMORY:** `project_layer_2_complete` — Manifest rollout complete 2026-04-29; Layer 2 at 100% coverage (184/184); Layer 3 prose ramp landed via BTS-257; Phase 2 candidates enumerated in roadmap.md but NOT yet captured as Linear tickets (operator decision next session). The 1-week verification routine `trig_01V3eu7T8WurLRzg1iSPSA3j` audits ramp performance on 2026-05-06.
* **REINFORCE:** `feedback_drift_guard_compounds_quality_across_sessions` — confirmed across 4 more sessions in this conversation. This is now the most frequently-confirmed pattern in the project memory.
* **No new external references** this session.
