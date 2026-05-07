# Feature: provider-heal umbrella verb

> Feature: bts-326-provider-heal-umbrella
> Work: linear:BTS-326
> Created: 1778175238
> Subject: provider-heal umbrella verb
> Status: In Progress

## Summary

Add `docs-check.sh provider-heal` — the operator-facing capstone that composes the three Phase primitives (BTS-321 auth, BTS-320 substrate-drift gate, BTS-319 ID resolution) into one fail-fast verb. Run order is auth → drift → resolve-ids; first non-zero exit halts and surfaces that phase's remediation. `--json` flag emits a structured envelope with each phase's status. Read-only EXCEPT for Phase 1's deterministic ID write — matches the read-only-where-possible posture of the components. Empirical anchor: the manual unifi-toolbox heal walkthrough 2026-05-06 was \~12 substrate operations dispatched through 4 different scripts; even after the three primitives shipped individually, the operator still has to chain them in correct order. The umbrella collapses that to one command.

## Job To Be Done

**When** I want to bring a partially-configured downstream node to a healed Linear-routed state,
**I want to** run one substrate command that verifies auth, checks for substrate drift, and writes the full provider IDs in correct order with fail-fast halt-and-remediate behavior on each phase,
**So that** the heal is a single operator action rather than a 3-command chain that must be sequenced and remediated manually.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh provider-heal --provider linear --team <name> --project <name> --project-dir <path>` runs all three phases sequentially when each succeeds, and exits 0 with stdout `PROVIDER-HEAL-OK: auth=<viewer-id> drift=clean ids=resolved` (newline-terminated).
- [ ] **AC-2:** Phase 3 (auth) runs FIRST. When auth halts (missing-key or invalid-key), the umbrella exits non-zero, forwards Phase 3's stderr verbatim, and does NOT run Phase 2 or Phase 1.
- [ ] **AC-3:** Phase 2 (drift) runs SECOND when Phase 3 succeeded. When drift halts (action counts > 0), the umbrella exits non-zero, forwards Phase 2's stderr (drift counts + remediation), and does NOT run Phase 1.
- [ ] **AC-4:** Phase 1 (resolve-ids) runs LAST when Phases 3 + 2 succeeded. Failures (missing team, missing project) halt with that phase's stderr.
- [ ] **AC-5:** `--json` flag emits `{status: "ok"|"auth-failed"|"drift-detected"|"resolve-failed", phases: {auth: {...}, drift: {...}|null, resolve_ids: {...}|null}, error: <string>|null}`. Phase objects mirror the per-primitive JSON envelopes. Phases that did not run are `null`.
- [ ] **AC-6:** Does NOT auto-run pull-auto on drift detection. Operator's responsibility: run `/ccanvil-pull` separately, then re-invoke `provider-heal`. Verified by stub call-log: pull-auto must NEVER be invoked from inside the umbrella.
- [ ] **AC-7:** Bats coverage at `hub/tests/provider-heal-umbrella.bats` using both `LINEAR_QUERY_OVERRIDE` and `CCANVIL_SYNC_OVERRIDE` stubs simultaneously. Tests AC-1 (happy path), AC-2 (auth halt), AC-3 (drift halt), AC-4 (resolve-ids halt), AC-5 (--json shape on each path), AC-6 (no pull-auto invocation).
- [ ] **AC-8:** Manifest declared per Layer 2: `cmd_provider_heal` includes `# @manifest` block declaring purpose/input/output/depends-on (jq + the three Phase primitives)/side-effect=writes-ccanvil-local-json-on-success-only/failure-mode/contract. Registered in `.ccanvil/manifest-allowlist.txt`. Drift-guard validates 100%.
- [ ] **AC-9:** Full bats suite passes — 2016/2016 baseline maintained or improved.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_provider_heal` function + `provider-heal` subcommand dispatch + `PROJECT_TREE_SUBCOMMANDS` registration (BTS-212 invariant) |
| `hub/tests/provider-heal-umbrella.bats` | New: bats coverage for AC-1 through AC-6 using both stubs |
| `.ccanvil/manifest-allowlist.txt` | Modified: register `cmd_provider_heal` |

## Dependencies

* **Requires:** `cmd_provider_heal_auth` (BTS-321 — shipped today).
* **Requires:** `cmd_provider_heal_preflight` (BTS-320 — shipped today).
* **Requires:** `cmd_provider_resolve_ids` (BTS-319 — shipped today).
* **Blocked by:** none.

## Out of Scope

* **Auto-running pull-auto** when drift is detected. AC-6 explicitly forbids this. The umbrella reports + halts; operator drives the remediation.
* **Auto-creating** `.env` when the auth phase fails. Phase 3 surfaces the missing-key error verbatim; operator handles.
* **Wider provider scope.** Only `--provider linear` for now. Other providers are future scope.
* **Idempotency on partial state.** Re-running after a partial failure restarts from Phase 3 — no resume-from-checkpoint logic. The phases are already idempotent individually (write-the-same-result-on-rerun), so this composes cleanly.

## Implementation Notes

* Compose by direct calls to `cmd_provider_heal_auth`, `cmd_provider_heal_preflight`, `cmd_provider_resolve_ids` (sibling functions in the same [docs-check.sh](<http://docs-check.sh>); in-process, no subprocess overhead).
* For the JSON envelope path, capture each phase's `--json` output via `cmd_<name> --json --project-dir <path>` invoked through bash with stdout capture; merge into the umbrella envelope.
* For text path, just forward each phase's normal stdout/stderr, then emit the `PROVIDER-HEAL-OK` summary on success.
* Stub composition pattern for tests: write_combined_stub() that handles BOTH `linear-query.sh` and `ccanvil-sync.sh` subcommands by branching on `$0` basename or by separate stubs (the umbrella uses both LINEAR_QUERY_OVERRIDE and CCANVIL_SYNC_OVERRIDE).
* Anchor file references for AC-7 (per BTS-265 file-ref validator): `.ccanvil/scripts/docs-check.sh`, `.claude/rules/provider-integration.md`.
* Pure deterministic substrate per `.claude/rules/deterministic-first.md` — composition logic is mechanical; no Claude reasoning.
