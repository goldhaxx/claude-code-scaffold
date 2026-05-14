# Stasis: session-2026-05-13-ci-fire-drill-bts-482-488-ship

> Feature: session-2026-05-13-ci-fire-drill-bts-482-488-ship
> Kind: session
> Last updated: 1778744300
> Session: 52
> Boundary: 2026-05-13T10:56:34-07:00
> Session objective: Stop the CI failure email firehose across all downstream nodes (operator-reported P1 fire drill) and ship the self-healing substrate to prevent recurrence.

## Accomplished

Session 52 — two-ship CI fire drill. Discovered mid-pivot that BTS-482's "fix" landed on hub but never reached nodes; spec'd + shipped BTS-488 as Phase A.5 to actually close the operational gap.

* **BTS-482 shipped (PR #184, `1c0cab8`).** Phase A. Hub's `ci.yml` `lifecycle-docs` job gained `if: ... && draft == false` guard; `pull_request` trigger declared `types: [opened, synchronize, reopened, ready_for_review]` (closes the draft→ready bypass). Shipped canonical example-data SSOT at `.ccanvil/fixtures/canonical-example-data.json` — RFC 2606 reserved-namespace addresses that `security-audit.sh`'s existing email regex already auto-allowlists. `.ccanvil/guide/configuration.md` gained "Canonical example-data SSOT" section documenting the keep-alerts-loud / declare-known-safe-shapes pattern. /review caught one BLOCKING bug in-PR (`ready_for_review` activity-type gap) — fixed before merge.
* **BTS-488 shipped (PR #185, `d7bee6e`).** Phase A.5 — the actual fire-drill kill. Discovered post-merge that BTS-482's workflow fix never reached downstream nodes because `.github/workflows/ci.yml` is not registered in any production node's `.ccanvil/ccanvil.lock` (BTS-489 captured as root-cause follow-up). Split hub-managed checks into new `ccanvil-checks.yml` (fully hub-owned: lifecycle-docs + security); hub's `ci.yml` reduced to test-only placeholder. New `cmd_heal_ci_workflows` substrate verb iterates registry, copies file, registers lockfile entry, strips lifecycle-docs+security from each node's existing ci.yml, commits. Idempotent, per-node-failure-isolated, retries orphaned writes from prior failed commits. /review caught 2 BLOCKING + 4 CONCERN findings, all addressed in-PR.
* **Fleet heal executed.** Ran `ccanvil-sync.sh heal-ci-workflows` from hub — 15/15 production nodes healed (file written, lockfile registered, ci.yml stripped, local commit landed), 0 errors. Then 8 GitHub-routed nodes pushed to origin (`fucina`, `whoop-toolbox`, `fieldnation-toolbox`, `inbox-toolbox`, `tour-scheduler`, `caffeine-calculator`, `zaw-portfolio`, `docint`). Email firehose structurally resolved.
* **3 follow-up tickets captured to Backlog.** BTS-483 P2 (Phase B — false-alert hardening + ci-pull meta-loop), BTS-484 P3 (registry tmp.* artifact cleanup — 16 stale entries surfaced by heal), BTS-489 P2 (init-time lockfile registration bug — the upstream root cause Phase A.5 worked around), BTS-490 P3 (hub-level credential-file `.gitignore` defaults — surfaced by whoop-toolbox OAuth near-miss).
* **whoop-toolbox cleanup.** Operator-side: deleted leaked `client_secret_663663533173-*.apps.googleusercontent.com.json`, committed `.env.example` with placeholder OAuth env vars, added `client_secret_*.json` + `*.apps.googleusercontent.com.json` to node's `.gitignore`.

## Current State

* **Branch:** `main` (clean, fast-forwarded through `d7bee6e`)
* **Tests:** 2314 / 2314 (parallel via the BTS-460 dispatcher) — last invocation pre-merge of BTS-488.
* **Uncommitted changes:** none.
* **Build status:** clean. Manifest 196/196, drift 0.
* **Fleet state:** 15 production nodes healed; 8 pushed to GitHub origin; 7 local-only (no remote — terminal state per BTS-72).

## Blocked On

Nothing.

## Next Steps

**Operator's call — five live threads:**

1. **Triage drain.** 5 items in Triage that landed mid-session: BTS-486, BTS-487, BTS-491, BTS-492, BTS-493 (mid-session captures not yet promoted). Plus the 5 from prior stasis still untouched (BTS-466, BTS-467, BTS-468, BTS-471, BTS-472). Quick pass before next ship.
2. **Phase B work — BTS-483 (P2).** False-alert hardening + ci-pull meta-loop. Unify false-positive suppression across guards (BTS-466 + BTS-461 + existing surfaces); ship `validate-fixtures` drift-guard for fixture hygiene; build `ci-pull` substrate that polls registered nodes for CI failures and opens Linear tickets with reproducible context. This is the strategic ask Zach originally raised; Phase A only stopped the bleeding.
3. **BTS-489 (P2) — init-time lockfile bug.** Root cause this session worked around. `cmd_init` copies github-template files but apparently never adds them to the lockfile, so broadcast never delivers updates. Audit init-apply path; close the gap; bats coverage in fresh-tmpdir fixture.
4. **BTS-484 (P3) — registry tmp.* cleanup.** 16 stale `tmp.*` entries surfaced cleanly by heal output. Mechanical fix.
5. **BTS-490 (P3) — credential .gitignore defaults.** Hub-level patterns for `client_secret_*.json`, `*.apps.googleusercontent.com.json`, `serviceAccountKey.json`, etc.

Roadmap freshness — "Onboarding & Hub/Spoke Separation" theme is empirically converged across BTS-327 + BTS-460 + BTS-482 + BTS-488; worth marking `Shipped:` and re-anchoring active theme.

## Context Notes

* **The BTS-482 → BTS-488 chain was a substrate-discovery cascade.** BTS-482's spec described the email firehose, my fix addressed the workflow shape, but the operational goal (stop emails) didn't actually land until BTS-488 closed the distribution gap. Lesson: when a "fire drill" ticket ships, verify the operational signal (real CI on real nodes) before declaring victory. The /review gate caught logic bugs but didn't catch the distribution-architecture gap because that lives outside the diff.
* **The hub `ci.yml` mixed-concerns trap.** Before BTS-488, the single `ci.yml` template tried to be both hub-managed (lifecycle-docs + security) AND node-customizable (test job). That made conflict-free hub updates impossible. The split (`ccanvil-checks.yml` for hub gates, `ci.yml` for node test runner) is a clean separation that survives per-node customization. Pattern generalizes: any hub template that needs both hub-controlled + node-customizable content should split files, not section-merge yaml.
* **Concurrent test-suite invocations are a real anti-pattern.** Mid-session I stacked 4 concurrent `test-suite-run --parallel` invocations when output appeared buffered. Per `background-task-discipline.md` this is forbidden. The rule held in spirit (I caught it via process listing) but my discipline lapsed. Confirmed the rule's necessity empirically — 4 concurrent runs polluted bats-run-* tmpdirs and caused one phantom failure (later attributed to contention).
* **`git -C` subshell loops are env-fragile in zsh.** When iterating multiple nodes with `git -C $path push` inside a `while read` loop, the subshell's PATH gets mangled and basic utilities (`head`, `sed`, `basename`) go missing. Workaround: run each push as a separate Bash invocation (works fine). Substrate fix (BTS-491-shape candidate): bake the fleet-push iteration into `ccanvil-sync.sh push-all`.
* **`strict-mode bats` discipline reaffirmed.** `[[ -n "$x" ]] && rm -rf "$x"` fails under `set -e` when `$x` is empty (first part returns 1 → bats fails test). Use `if [[ ]]; then; fi` blocks. Tripped during BTS-488 fixture authoring; same shape as `feedback_set_e_kills_rc_capture`.

## Determinism Review

operations_reviewed: 47
candidates_found: 1

* **fleet-post-heal-push**: Claude ran `git -C <path> push origin main` × 8 manually after heal-ci-workflows completed (one Bash invocation per node because subshell loops fragmented PATH). Should be a `ccanvil-sync.sh push-all` (or `cmd_heal_ci_workflows --push` flag) substrate verb that iterates the registry, filters to github-routed nodes (`origin` configured), pushes each, summarizes synced/failed/skipped. Same iteration pattern as `cmd_broadcast`/`cmd_heal_ci_workflows`. Impact: high — every fleet-mutation session needs this. Mitigates the empty-PATH-subshell brittleness and avoids retry-on-rc=128 noise from local-only nodes.

## Evidence Gaps

* BTS-466 — Determinism: workspace guard heredoc false-positives — missing-evidence-anchors
* BTS-461 — guard-workspace.sh slash-prefix false-positives in doc-body URLs — missing-evidence-anchors

(Both carry over from prior stasis — Phase B work will absorb them.)

## Manifest Coverage

196 / 196 (allowlist), drift incidents: 0

## Cross-Session Patterns

Session 51 (1 ship, BTS-460, 3 triage promotes) → Session 52 (2 ships BTS-482+BTS-488, 4 triage promotes, 1 fleet heal across 15 nodes). Pattern shift: fire-drill cadence supersedes theme-adjacent ramp. Mid-session pivot to operational ASAP work proven viable when substrate is mature.

Recurring patterns from prior stasis:

* **Substrate-by-use validates during ship.** Session 50 dogfooded BTS-235 (/ship); Session 51 dogfooded BTS-460 (test-provider dispatcher); Session 52 dogfooded BTS-488 (heal-ci-workflows) by running it on the 15-node fleet immediately post-merge. The pattern holds: ship a substrate primitive, exercise it on real production state, surface gaps cheaply.
* **/review consistently catches logic bugs I miss.** Session 51's BLOCKING was the `--slow-top` strict-mode-bashism; Session 52's BLOCKINGs were the `ready_for_review` activity-type gap (BTS-482) and the orphan-retry gap (BTS-488). Confirms `feedback_review_surfaces_real_blocker_in_own_code` again.
* **Fire-drill spec discovery > pre-planned spec accuracy.** Both BTS-482 and BTS-488 specs landed with ACs that proved incomplete mid-ship; the actual fixes (ready_for_review trigger, orphan-retry detection) emerged through implementation + review, not spec drafting. Lesson for time-critical work: ship the smallest viable substrate primitive and let /review surface gaps.

`legacy-refs-scan`: clean (0 matches). `audit-session`: 34 findings since `ca6be8c` — 28 `git-C` patterns (fleet-iteration ops; partly substrate-driven via heal-ci-workflows + broadcast, partly ad-hoc per-node pushes which is the determinism candidate above), 5 `jq`, 1 `shasum` (heal verb's hash compute — substrate-driven). No pathological patterns.

## Security Review

PASS. /review's security-audit ran on the working tree of BTS-488 pre-commit; 17 findings, ALL pre-existing on archived `docs/sessions/`, `docs/specs/bts-72-...`, `docs/specs/bts-395-...`, `hub/meta/operations.md`. ZERO findings on the 7 BTS-488-touched files. No secrets/tokens/PII introduced. Same posture as BTS-482's pre-merge audit. Operator-side cleanup of whoop-toolbox's leaked `client_secret_*.json` happened in that node's repo (not hub), confirmed deleted + gitignored before push.

## Memory Candidates

* **`feedback_concurrent_test_suite_invocations_anti_pattern`** — Stacked 4 concurrent `test-suite-run --parallel` invocations mid-session when output appeared buffered. Per `background-task-discipline.md`, this is forbidden. Resulted in 1 phantom test failure attributable to bats-run-* tmpdir contention. Confirmed: the rule is correct; my discipline lapsed. Operator-side reminder: trust the buffer; never re-invoke a test suite that's already mid-run.
* **`feedback_git_dash_c_subshell_env_fragile_in_zsh`** — `git -C $path` inside `while read; do ... done` zsh subshells loses PATH for child utilities (`head`, `sed`, `basename` become "not found"). Workaround: run each per-node operation as a separate Bash invocation. Substrate fix: bake the iteration into a `ccanvil-sync.sh` verb. Determinism candidate captured above.
* **`reference_local_only_downstream_nodes`** — 7 of 15 production nodes have no `origin` remote: unifi-toolbox, taxes, microsoft365-toolbox, open-brain, strengthOS, luxlook, web-browser-toolbox. Local-only per BTS-72 — heal commits on local main are terminal state; CI/push N/A. The other 8 are github-routed.
* **`project_ci_fire_drill_phase_a_complete`** — BTS-482 (PR #184, `1c0cab8`) + BTS-488 (PR #185, `d7bee6e`) shipped 2026-05-14. Email firehose structurally resolved across 8 GitHub-routed nodes; 7 local-only nodes have heal commits ready for future remote-add. Phase B (BTS-483) captures the meta-loop substrate. Theme: "Onboarding & Hub/Spoke Separation" empirically converged across 4 ships (BTS-327, BTS-460, BTS-482, BTS-488).
* **`feedback_substrate_discovery_via_operational_check`** — When a fire-drill ticket ships, verify the operational signal (real CI on real nodes) before declaring victory. BTS-482 looked complete on hub but BTS-488 was needed to actually close the operational gap. /review catches diff-local bugs but not distribution-architecture gaps. Add a "post-ship operational check" step to fire-drill specs.

## Permissions Review Pending

(none — both promote-review.counts.total and check.danger are 0)
