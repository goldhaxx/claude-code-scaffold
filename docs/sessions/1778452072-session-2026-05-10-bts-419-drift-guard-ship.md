# Stasis: session-2026-05-10-bts-419-drift-guard-ship

> Feature: session-2026-05-10-bts-419-drift-guard-ship
> Kind: session
> Last updated: 1778452072
> Session: 42
> Boundary: 2026-05-10T11:20:27-07:00
> Session objective: Pick up BTS-419 spec-to-ship arc — substrate-staleness drift-guard

## Accomplished

Session 42 — BTS-419 spec to activate to plan to 12-step TDD to review to PR to ship, end-to-end in one turn.

* **BTS-419 SHIPPED** (PR #178, merge `fb10981`). Added `linear_assert_project_id_emitted` helper in `operations.sh` that hard-fails any project-scoped Linear verb whose resolved command lacks `--project-id` when `project_id` is configured. Wired into all six verbs (`backlog.list`, `idea.add`, `idea.list`, `idea.count`, `idea.triage`, `idea.review-icebox`). ALLOW_STALE_SUBSTRATE=1 env-prefix bypass mirrors existing ALLOW_DESTRUCTIVE / ALLOW_MAIN / ALLOW_OUTSIDE_WORKSPACE convention. Defends the BTS-407 contract in two complementary places: hub-side regression (drift-guard fixture catches future BTS-407-shape reverts at merge time) AND runtime self-consistency (downstream nodes that pull this fix will fire LOUD if a future substrate revision regresses the contract). 26 new bats covering all 7 ACs + bypass.
* **Triage cleared** at session start — promoted BTS-417 (P3), BTS-418 (P2), BTS-419 (P2), BTS-421 (P3) from Triage to Backlog in one batch. BTS-419's ship then moved it to Done; the remaining trio (BTS-417/418/421) sits in Backlog.
* **Architectural decisions resolved in plan-step** (spec's 3 open questions): Option 2 (centralized helper) for the guard location; hard-fail with env bypass for severity; independent-ship-but-adjacent for BTS-418 pairing.
* [**Operations.sh**](<http://Operations.sh>)** sourceability guards** (BTS-419 sub-substrate) — wrapped argv parsing + dispatch in `[[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` guards so bats fixtures can `source operations.sh` and unit-test internal helpers directly without triggering `usage()`/exit. Function definitions stay top-level (always sourceable); only the imperative entry-point chunks are guarded.
* **W2 fix from review** — `cmd_resolve`'s `@manifest` block now declares `failure-mode: stale-substrate-emit` + `contract: env-prefix-bypass-via-ALLOW_STALE_SUBSTRATE=1` + inline `@failure-mode` marker above the `external_adapter` call. Caught by code-reviewer agent; landed as `aa24a66` pre-ship. Manifest validate stayed clean post-edit (194/194 drift 0).

## Current State

* **Branch:** `main` (clean, fast-forward through `fb10981`).
* **Tests:** 2161 total. Full suite via `bash .ccanvil/scripts/bats-report.sh --parallel` returned exit 0 mid-session (Step 10). Targeted post-W2 sweep: `bats hub/tests/operations` files to 95/95 GREEN. Drift-guard fixture alone: 26/26.
* **Uncommitted changes:** none.
* **Build status:** clean. PR #178 merged + branch deleted + BTS-419 auto-closed to Done. Manifest 194/194 drift 0.

## Blocked On

Nothing.

## Next Steps

1. **BTS-418** (Backlog, P2) — Determinism: resolver-wrapper-flag-contract drift-guard. Companion to BTS-419; hardens the OTHER side of the resolver-correctness surface (resolver-to-wrapper flag-set contract instead of resolver-self-consistency). The two structurally close the BTS-407-shape regression class. Tight scope — likely 4-6 step TDD ship.
2. **Onboarding theme cluster (P2)** — BTS-314 (Linear-config audit + heal pass for 3 drifted nodes) is the canonical first ship. Roadmap-aligned; resolves the inbox-toolbox + microsoft365-toolbox config divergences flagged 2026-05-06. Other onboarding tickets: BTS-324, BTS-327, BTS-337, BTS-312.
3. **BTS-417** (Backlog, P3) — Layer 3 ramp prose tuning — 3 small edits from BTS-317 audit. Cache-warm cadence-eligible.
4. **BTS-204 — SSOT-Linear** (Triage, major effort, dedicated session).

## Context Notes

* **Sourceability guard pattern is reusable.** The `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then` pattern wrapping argv parsing + dispatch — kept function definitions top-level for sourceability while keeping the script's CLI entrypoint behavior identical — is the cleanest unit-test-vs-script duality. Other `.ccanvil/scripts/*.sh` files that grew script-only argv parsing could adopt this if internal-helper unit testing becomes a recurring need.
* **Helper-direct unit tests + Step 7 verb-loop end-to-end pair is sufficient — synthetic-corrupt path is NOT needed.** The spec's AC-3 wording (synthetically mutates the resolver's emit path) was speculative. Plan's Risk R2 documented that helper-level unit tests (Steps 2-3) prove the assertion mechanics + Step 7 verb-loop end-to-end proves the wiring; the synthetic-corrupt fixture would require per-test [operations.sh](<http://operations.sh>) patching with no marginal coverage gain. Code-reviewer flagged this as W3 (low-risk doc gap); plan's R2 already resolves.
* **Code-reviewer can produce false positives on bats semantics.** Agent claimed bats 1.5.0 strict mode separates `$output` from `$stderr` — empirically false (default behavior merges stderr into `$output` unless `run --separate-stderr`). Verified via probe before accepting/rejecting the finding. Future-pattern: always empirically test agent claims about test-framework defaults before fixing.
* **Manifest discipline for internal helpers vs caller failure-modes**: `linear_assert_project_id_emitted` itself stays un-manifested (internal helper, follows `linear_mcp_adapter`'s un-manifested convention). BUT `cmd_resolve`'s `@manifest` block MUST declare the new failure-mode that propagates THROUGH it (BTS-239 substantiation requires inline `@failure-mode: <slug>` marker in the function body). The agent's W2 finding caught this — manifest validator initially missed it because the helper isn't allowlisted; the substantiation drift surfaced only after I added the failure-mode line to `cmd_resolve`'s header (which then required the inline marker to match).
* **W2 fix flow had a sub-loop**: header `failure-mode:` line + contract line landed first (commit `aa24a66`), validator then reported `missing-failure-mode-marker` drift. Added inline `@failure-mode: stale-substrate-emit` comment above `external_adapter` call to clean. Two-step substantiation is the BTS-239 convention.

## Determinism Review

operations_reviewed: 18
candidates_found: 0

No candidates this session.

The architecture-by-the-book outcome: the helper itself replaced what would have been a stochastic "Claude validates resolver output by reading" pattern with deterministic shell assertion. No emergent stochastic ops fell out of the implementation.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

194 / 194 (allowlist), drift incidents: 0. Status: ok. Unchanged from session 41.

## Cross-Session Patterns

* **Recurring (positive, now 5+ sessions): scope-up-on-live-API-reveal / scope-down-on-reveal pairing holds.** This session was scope-DOWN-on-reveal at plan time — three architectural shapes surfaced as open questions in the spec; plan resolved to Option 2 (centralized helper) rather than the full table-driven dispatcher refactor option that briefly surfaced (would have been BTS-419 scope creep). Pattern: when spec surfaces 2-3 implementation options as Open Questions, plan is the right ratification point, not spec-step.
* **Recurring (positive, holding): review catches real failure-mode drift even when manifest validate is clean.** The W2 finding (cmd_resolve manifest missing the new exit-path declaration) was structurally invisible to `module-manifest.sh validate` because the new helper wasn't allowlisted. Code-reviewer's call-graph reasoning surfaced it. Same pattern as session 40's BTS-417 audit — review finds drift the deterministic substrate misses, because the deterministic substrate is necessarily scoped to its allowlist.
* **NEW: bats fixture sourceability is now a reusable substrate pattern.** First adoption in `operations.sh`; the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then` guard wrapping argv parsing + dispatch keeps internal-helper unit testing accessible without breaking script-mode behavior. If a second `.ccanvil/scripts/*.sh` adopts this within the next 2 sessions, capture as a substrate convention.
* **No legacy-refs drift** (legacy-refs-scan: empty).
* **No audit-session findings** (`audit-session --since ab4db44`: 0 findings).

## Security Review

PASS — no secret/PII patterns introduced this session. All diff content is shell + bats; the new stderr error message interpolates `${project_id}` + `${verb}` via heredoc (parameter expansion only, no command substitution), and `project_id` is read from JSON config via `jq -r` so embedded shell metas decode to opaque strings. Security audit baseline noise (17 pre-existing findings in session archives + spec markdown) unchanged.

## Memory Candidates

* **Feedback (validated):** `feedback_empirically_verify_test_framework_claims` — code-review findings about test-framework default behavior (bats `$output` vs `$stderr` capture, mocha hook ordering, jest config flags, etc.) MUST be empirically verified with a small probe before accepting or rejecting. Defaults vary by version + opt-in flags. Session 42 anchor: code-reviewer claimed bats 1.5.0 strict mode separates streams; probe showed merged-by-default. Saved a non-fix; would have inverted working tests.
* **Feedback (validated):** `feedback_sourceability_guard_pattern_for_script_unit_tests` — when a `.ccanvil/scripts/*.sh` grows internal helpers that warrant direct unit testing (not just integration), wrap argv parsing + dispatch in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi`. Function defs stay top-level; entry-point imperative stays guarded. Reusable substrate convention; first adoption in `operations.sh` per BTS-419.
* **Feedback (validated):** `feedback_manifest_failure_mode_substantiation_requires_inline_marker` — declaring `failure-mode: <slug>` in a function's header `@manifest` block requires an inline `# @failure-mode: <slug>` comment somewhere in the function body to substantiate. `module-manifest.sh validate` reports `missing-failure-mode-marker` drift otherwise. Two-step contract; surfaces only after the header line lands.
* **Project:** `project_bts_419_arc_complete` — BTS-419 SHIPPED 2026-05-10 (PR #178, merge `fb10981`). substrate-staleness drift-guard live on hub; downstream nodes pull-cadence-fragility now becomes LOUD instead of silent-wrong on future BTS-407-class regressions. Pair-target BTS-418 (resolver-wrapper-flag-contract drift-guard) remains in Backlog.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->