# Stasis: session-2026-05-11-bts-324-routing-key-rename-heal-ship

> Feature: session-2026-05-11-bts-324-routing-key-rename-heal-ship
> Kind: session
> Last updated: 1778545744
> Session: 48
> Boundary: 2026-05-11T10:24:29-07:00
> Session objective: Open Onboarding & Hub/Spoke Separation P2 cluster with the smallest cache-warm-eligible ticket (BTS-324 routing-key rename heal) AND build the substrate operator wants to use next session to heal all downstream nodes.

## Accomplished

Session 48 — BTS-324 specced, critic-reviewed, planned, implemented, reviewed, shipped end-to-end in one turn. Second P2 ship in the Onboarding & Hub/Spoke Separation theme.

* **BTS-324 SHIPPED** (PR #181, merge `e354253`). Added `cmd_provider_heal_routing_rename` — detects legacy `integrations.routing.ticket` keys in `.claude/ccanvil.local.json` (stochastic-init divergence from the `ccanvil-init` skill) and renames to canonical `routing.idea` (default) or operator-named target set via `--routes`. After rename, drains `.ccanvil/ideas-pending.log` via `cmd_idea_pending_replay` so stuck Linear transitions land. Two modes: `--check` (read-only probe, byte-identical idempotent) and `--apply` (atomic temp+mv mutation + drain). 18 new substrate tests covering all 7 ACs. Full bats sweep 2244/2244, manifest 194/194 drift 0.
* **Drift-watchdog triage cleared.** All 11 auto-generated drift-watchdog tickets (BTS-432 through BTS-442) from this morning's Monday 9:13 launchd run promoted from Triage to Backlog at P3. Triage queue 11 → 0, Backlog 26 → 37. Each ticket carries a unique drift_key + per-node "N commits behind, M paths changed" body — they're the per-node action-required signals that feed into BTS-330 (`fleet-heal-orchestration`).
* `/spec --review` (critic mode) caught a real coverage ambiguity (4th consecutive). AC-6 originally said "refuse rename when ANY canonical key is set" but interacted ambiguously with AC-3's `--routes <list>` flag. Critic-mode flagged the load-bearing case: `--routes spec,plan` against a node with pre-existing `routing.stasis` — should block (full canonical key space) or proceed (only target set matters)? Fixed pre-activate by scoping the conflict check to the intersection of `existing canonical keys` and `target routes`. Critic-mode is now **4-for-4** on non-trivial specs (BTS-419, BTS-418, BTS-315, BTS-324).
* **Code-reviewer caught 3 real CONCERNS pre-commit (4th consecutive).** Finding 1: `cmd_idea_pending_replay` manifest needed `caller: cmd_provider_heal_routing_rename` annotation (Layer 3 drift). Finding 2: `--check` returned `status: "legacy-detected"` even on already-canonical configs (`legacy_key_present: false`) — misleading for fleet-script use (BTS-330 prep). Finding 3: no `--check` test for already-canonical path (test gap masking Finding 2). All three fixed in one pass per the `feedback_code_reviewer_warn_couples_with_test_gap` pattern: split status into `legacy-detected` vs `already-canonical`, added bats test, updated manifest. **Refines the pattern further** — Finding 2 surfaced a fleet-script consideration (BTS-330) that the operator-only test fixture would NEVER have caught.
* **BTS-212 reverse-coverage drift trapped + fixed mid-impl.** Initial Step 9 manifest validate passed, but the full bats sweep returned 1 failure (out of 2244): `hub/tests/docs-check-flags.bats` flagged `cmd_provider_heal_routing_rename` as a new `--project-dir`-parsing subcommand NOT registered in `PROJECT_TREE_SUBCOMMANDS`. Fixed by adding to the array. This is BTS-212's drift-guard working exactly as designed — caught new substrate that would silently break the family contract.
* **The BTS-235 ship-finalize substrate handled merge + branch-delete + land + Linear auto-close cleanly.** One `/ship 181` invocation: `{pr_merged: true, branch_deleted: true, title_result: skipped (already correct), ticket_closed: true, errors: []}`. PR title flowed through from `> Subject:` metadata; assert-pr-title was a no-op confirming the BTS-236 substrate continues to hold.

## Current State

* **Branch:** `main` (clean, fast-forward through `e354253`).
* **Tests:** 2244 / 2244 (full parallel sweep GREEN; the previously-flaky `module-manifest-query-helpers.bats:46` passed both sweep runs this session).
* **Uncommitted changes:** none.
* **Build status:** clean. PR #181 merged, branch deleted, BTS-324 auto-closed to Done. Manifest 194/194 drift 0.

## Blocked On

Nothing.

## Next Steps

**Operator-stated objective for session 49: "put BTS-324 substrate to work and heal all nodes."** Concrete plan:

1. **Sweep all registered downstream nodes** via `~/.ccanvil/registry.json` (or `bash .ccanvil/scripts/ccanvil-sync.sh registry-list`). For each node, run `bash .ccanvil/scripts/docs-check.sh provider-heal-routing-rename --check --project-dir <node>` and collect the envelopes.
2. **Classify by status:**
   * `already-canonical` → silent skip
   * `no-routing-config` → silent skip (local-only nodes by design)
   * `legacy-detected` → candidates for `--apply` (default `routing.idea`)
   * `conflict` → operator-decision (which value wins per the colliding canonical key)
3. **Heal candidates** with `--apply`. For inbox-toolbox (BTS-324 anchor case, 3 stuck transitions in pending log), expect `drained.synced > 0` confirming the substrate did its full job.
4. **Verify post-heal** by re-running `--check` on each healed node: should now emit `already-canonical`.
5. **Fleet-heal lite pattern**: this session 49 work IS the validation cycle for the future BTS-330 (`fleet-heal-orchestration`) substrate. Decisions made manually here become the spec for BTS-330's automation. Capture friction points as captures during the walk-through using `/idea --source-skill ccanvil-heal --context "session-49 fleet heal walk-through"`.

Other open lanes in the Onboarding & Hub/Spoke Separation cluster (post-heal):

* **BTS-316 (P2 umbrella)** — Modular provider connectivity / forklift-heal. Major-effort dedicated spec session.
* **BTS-327 (P2)** — Fresh-mode CLAUDE.md inherits hub's actual content (no clean template wedge).
* **BTS-314 (P2)** — Onboarding repair: Linear-config audit + heal pass for remaining drifted nodes.
* **BTS-312 (P2)** — Test-runner indirection (generic per-spoke test verb).
* **BTS-204 (Triage, major effort)** — SSOT-Linear ambient strategic work.

## Context Notes

* **One-turn spec-to-ship cadence holds at 4 consecutive sessions** (BTS-419, BTS-418, BTS-315, BTS-324). Each ship reused prior session's test patterns (`provider-activate.bats` fixture this time, `pull-globals.bats` last time). The leverage from prior substrate keeps making one-turn cadence feasible even as theme content shifts.
* **Classifier-blocked bulk Linear mutation.** When triaging the 11 drift-watchdog tickets, the AskUserQuestion approval ("Promote all 11 to backlog (P3)") did NOT propagate to the auto-mode classifier — the bulk `linear-query.sh save-issue` loop was blocked citing "Mass-modifying 11 Linear tickets the agent did not create this session without explicit user authorization." Required a second explicit "I approve this" message from the operator. **This is friction** — the AskUserQuestion subsystem and the auto-mode classifier should be aligned on what counts as authorization. Captured as memory candidate below.
* **zsh-no-word-split bit me again.** First triage promote loop ran once with `$id` holding all 11 IDs concatenated because `for id in $IDS;` doesn't word-split unquoted vars in zsh. Already covered by BTS-374 on backlog as P3 — but the pattern keeps firing during ad-hoc shell work. Worth bumping priority OR codifying a rule like "all skill snippets must use array form instead of bare for-in-unquoted-var."
* `tail -15` lost the failure list. First full bats sweep ran piped through tail and showed `PASS: 2243 / FAIL: 1 / TOTAL: 2244` but the failure name was truncated. Lost 5 minutes re-running with `--json` to identify it. Per BTS-118 single-invocation rule + BTS-383 progress mode, the canonical recipe is `--parallel --json` and parse `.failures[]` directly. Recurring pattern: human-friendly tails clip the actionable signal at the exact moment you need it.
* **AC-3 test step turned out to be test-only.** Plan Step 6 (AC-3 `--routes` validation) had originally been expected to require new implementation — but Step 2 had already wired the route parsing + validation. Test step ran red→green on the first iteration with no impl change. Healthy sign that the substrate shape was correct on first pass; worth noting that plan steps should be allowed to "collapse to verification" rather than always being R-G-R.
* **Lifecycle gate did NOT fire** this session — no spec edits post-plan-write, so no plan-spec hash drift. Confirms the gate is appropriately silent in the happy path.
* **Sweep took \~10 minutes both times.** Both `--parallel --json` runs took noticeably longer than session 47's \~4-5 min. May be a one-time wall-time blip OR may signal the parallel-sweep is slower than reported under certain load. Worth a future profile (BTS-294 parallel-fan-out work could surface relevant tooling).

## Determinism Review

operations_reviewed: 22
candidates_found: 0

No candidates this session.

The two stochastic-replacement opportunities that surfaced were caught and converted (or already substrate) within-session:

1. `/spec --review` critic-mode replaced "agent eyeballs the spec for coverage gaps" — already substrate (BTS-266), used correctly. Caught the AC-3/AC-6 interaction.
2. Code-reviewer's WARN-level findings replaced "implementer's gut check on correctness" — already substrate, used correctly. Caught the manifest-drift + misleading-status + test-gap triple.

The zsh-no-word-split footgun is already captured (BTS-374); the classifier-vs-AskUserQuestion friction is captured below as a memory candidate; the `tail -15` truncation pattern is also worth a memory.

## Evidence Gaps

No evidence gaps this session.

## Manifest Coverage

194 / 194 (allowlist), drift incidents: 0. Status: ok. Unchanged from session 47. The BTS-324 substrate added one new function (`cmd_provider_heal_routing_rename`) with a full manifest block; `cmd_idea_pending_replay` gained a `caller: cmd_provider_heal_routing_rename` annotation (Layer 3 drift fix from code review).

## Cross-Session Patterns

* **Recurring (positive, 4 sessions): one-turn spec-to-ship at substrate maturity.** BTS-419 → BTS-418 → BTS-315 → BTS-324. Each ship reused prior session's test patterns + substrate primitives. Cadence holds when the ticket is structurally adjacent to recent ships OR sits cleanly on top of existing substrate. BTS-324 used the `provider-activate.bats` fixture pattern + `cmd_idea_pending_replay` substrate directly.
* **Recurring (positive, 4-for-4):** `/spec --review` critic-mode catches real coverage ambiguity. Four consecutive non-trivial specs. Validate-spec is the structural floor; critic-mode is the semantic ceiling. Adopt as standard pre-activate gate for ≥3 ACs.
* **Recurring (positive, 4-for-4): code-reviewer catches real WARN findings + test gaps.** Different shape each time but consistent value. BTS-324 surfaced a fleet-script consideration (Finding 2 fleet-clarity) that an operator-only test fixture would never have caught — pattern is broader than just "test gap masks bug."
* **NEW (this session): BTS-212 reverse-coverage drift fired correctly.** New `--project-dir`-parsing subcommand caught structurally pre-merge. First time observing this guard fire in a multi-session record; confirms the guard substrate is doing its job.
* **NEW (this session): classifier blocked AskUserQuestion-approved bulk Linear mutation.** Substrate friction; worth aligning the two authorization subsystems.
* **NEW (this session): zsh-no-word-split footgun bit ad-hoc shell work.** BTS-374 already captures the pattern; consider bumping priority.
* **No legacy-refs drift** (legacy-refs-scan: empty array).
* **No audit-session anomalies** (patterns were all standard substrate work: `cp`, `jq` in bats fixtures — expected).

## Security Review

PASS — no NEW secret/PII patterns introduced this session. Diff content: bash substrate (`cmd_provider_heal_routing_rename` + `PROJECT_TREE_SUBCOMMANDS` registration + manifest annotations) + bats fixture file. No env-var reads beyond the existing pattern (`$HOME` via `cmd_idea_pending_replay`'s replay path). The 17 baseline findings (`docs/sessions/`, `hub/meta/operations.md`) are pre-existing and unchanged.

## Memory Candidates

* **Feedback (validated):** `feedback_critic_mode_four_consecutive_real_finds` — `/spec --review` critic-mode has now caught real coverage ambiguity on FOUR consecutive non-trivial specs (BTS-419, BTS-418, BTS-315, BTS-324). The track record is solid enough to elevate from "recommended" to "default-on" for specs with ≥3 ACs OR any `Implementation Notes` choice points OR cross-AC interactions. Refines `feedback_critic_mode_three_consecutive_real_finds`.
* **Feedback (validated):** `feedback_code_reviewer_finds_fleet_concerns_beyond_operator_only` — Code-reviewer's WARN-level findings sometimes surface FLEET-script concerns (e.g., BTS-324 Finding 2: misleading `--check` status for BTS-330's future fleet-heal-orchestration use). Operator-only test fixtures can't see these. Pattern: when shipping substrate that's specifically designed for future fleet automation, ask the reviewer to verify the JSON envelope shape is fleet-script-friendly (not just operator-readable).
* **Feedback (validated):** `feedback_classifier_blocks_askuserquestion_bulk_mutations` — Auto-mode classifier does NOT accept AskUserQuestion answers as authorization for bulk external-system mutations (observed: 11 Linear ticket transitions during `/idea triage` required a second explicit "I approve this" message after the AskUserQuestion was answered). Plan for the friction in agentic workflows: when looping a mutation across multiple records, expect to need an explicit second authorization OR pre-approval permission rule.
* **Feedback (validated):** `feedback_no_pipe_tail_on_bats_sweep_for_failure_diagnosis` — Never pipe full bats sweep output through `tail` for verification — the failure list is mid-output and gets truncated, costing a re-run. Canonical recipe: `bash .ccanvil/scripts/bats-report.sh --parallel --json` plus `jq '.failures[]'`. Reinforces BTS-118 single-invocation discipline.
* **Project:** `project_drift_watchdog_triage_pattern_established` — Drift-watchdog launchd job (Monday 9:13) auto-generates per-node Triage tickets each week. Triage outcome decision: promote all to Backlog at P3 (operator decision 2026-05-11), keeping them as visible action items until BTS-330 (fleet-heal-orchestration) ships. Future Monday runs will produce 11 new triage tickets unless the watchdog cadence changes OR auto-promotion is implemented.
* **Project:** `project_onboarding_theme_session_49_objective` — Session 49 objective stated by operator 2026-05-11: "put BTS-324 substrate to work and heal all nodes." Sweep all registered downstream nodes via `provider-heal-routing-rename --check`, classify, heal candidates. This walk-through IS the validation cycle for the future BTS-330 fleet-heal-orchestration substrate — capture friction points during the walk.