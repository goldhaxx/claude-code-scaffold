# Feature: Layer 3 ramp + manifest rollout close-out

> Feature: bts-257-layer-3-ramp-rollout-closeout
> Work: linear:BTS-257
> Created: 1777494242
> Subject: Layer 3 ramp + manifest rollout close-out
> Status: Complete

## Summary

Per `docs/manifest-rollout.md` Session 11 (final session) — augment the `code-reviewer` agent + `/review` skill body with manifest-aware checks (Layer 3 ramp), and close out the rollout by updating `docs/manifest-rollout.md`, `docs/research/dark-code-mapping.md` (Layer 2 status `~10%` → `100%`), and `docs/roadmap.md` (Dark Code Phase 1 complete). After this ship, **Layer 2 (Self-Describing Systems) is fully shipped at 100% coverage** and the rollout doc becomes a one-time historical record. No new manifests added; no new substrate primitives; no behavior changes outside the agent + skill + docs prose.

## Job To Be Done

**When** I'm reviewing a PR that touches manifested substrate,
**I want to** the code-reviewer agent + /review skill to surface manifest drift (new caller of cmd_X not in declared `caller:` list, new dep not in `depends-on:`, new exit path not enumerated in `failure-mode:`) as `manifest-drift / architecture-shaped change` findings,
**So that** Layer 3 (Comprehension Gate) ramps from `~40%` to functional structural review — every PR reads the manifest as the canonical contract and flags drift before merge.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `code-reviewer` agent body has a new "Manifest-aware review" checklist section that prescribes: (1) run `bash .ccanvil/scripts/module-manifest.sh validate --json` as a pre-check; (2) for each diff that adds a new caller of any cmd_* on the allowlist, verify the manifest's `caller:` list includes the new call site; (3) for new `depends-on` introductions, same check; (4) for new exit paths, check `failure-mode:` enumerates them.
- [ ] **AC-2:** `/review` skill body has a new pre-flight step that runs `module-manifest.sh validate` BEFORE spawning the code-reviewer agent. Drift surfaces in the briefing under `## Manifest drift`.
- [ ] **AC-3:** `docs/manifest-rollout.md` carries a closing `## Status: COMPLETE` section noting all 11 sessions shipped, final allowlist size 184/184, drift 0, and the doc becomes a historical record.
- [ ] **AC-4:** `docs/research/dark-code-mapping.md` Layer 2 status flips from `~10%` to `100%` with a brief note on what shipped (substrate + 184 manifests across 11 sessions). Layer 3 status updated to reflect the partial ramp landed in this session.
- [ ] **AC-5:** `docs/roadmap.md` Dark Code Phase 1 section reflects "Phase 1 shipped — Layer 2 100% covered; Layer 3 partial ramp" and proposes whether to continue with Phase 2 (Layer 3 full integration) or rotate themes.
- [ ] **AC-6:** `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0 with `coverage.covered == 184`, `coverage.total == 184`, `drift == []` (unchanged from Session 10 — Layer 3 ramp adds no new manifests).
- [ ] **AC-7:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel` reports 1926+ / 0 / total). No new tests required — this is documentation + agent-prose ship.

## Affected Files

| File | Change |
|------|--------|
| `.claude/agents/code-reviewer.md` | Modified — append manifest-aware checklist section |
| `.claude/commands/review.md` | Modified — add pre-flight validate step |
| `docs/manifest-rollout.md` | Modified — append `## Status: COMPLETE` close-out |
| `docs/research/dark-code-mapping.md` | Modified — Layer 2 `~10%` → `100%`; Layer 3 partial-ramp note |
| `docs/roadmap.md` | Modified — Dark Code Phase 1 marked shipped; next-step proposal |

## Dependencies

- **Requires:** BTS-239, BTS-240, BTS-241, BTS-242, BTS-243, BTS-244, BTS-245, BTS-246, BTS-251, BTS-252, BTS-256 (the entire 11-session rollout)
- **Blocked by:** none

## Out of Scope

- Implementing the manifest-aware checks as deterministic scripts — Phase 2 work; this session just lands the prose nudge so the agent + skill act on it via Claude reasoning. Future Phase 2 ticket can convert to a deterministic check.
- New manifests or substrate changes — coverage stays at 184/184.
- Refactoring `module-manifest.sh` — no behavior changes.

## Implementation Notes

- **Agent prose shape:** add a numbered Step ("Manifest-aware review") with three sub-checks: pre-flight validate, new-caller-not-declared, new-dep-not-declared. Each sub-check explicitly says "flag as `manifest-drift` finding under CONCERNS or BLOCKING per severity."
- **Skill prose shape:** add Step 0 (pre-flight) before spawning the code-reviewer agent. Surface drift count + list of drifted entries before the review proceeds. If drift > 0, the briefing surfaces it as a separate section so the operator decides whether to clear drift first or proceed with review.
- **Close-out tone:** the rollout doc's status section should be celebratory but factual — list each session's allowlist delta, total manifests, and the substrate fixes shipped (BTS-251 file-level fallback, BTS-252 SIGPIPE-resistant body grep). Note this doc is now a one-time historical record; future Layer 2 maintenance is per-substrate (manifest co-located with code).
- **No new manifests.** Layer 3 substrate (a deterministic manifest-aware check primitive) is deferred to a future Phase 2 ticket. This session ramps the prose layer only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
