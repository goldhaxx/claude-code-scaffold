# Feature: provider-heal-preflight substrate (Phase 2 of provider-heal)

> Feature: bts-320-provider-heal-preflight
> Work: linear:BTS-320
> Created: 1778132456
> Subject: provider-heal-preflight substrate (Phase 2 of provider-heal)
> Status: In Progress

## Summary

Add `docs-check.sh provider-heal-preflight` — a single-verb substrate primitive that runs `ccanvil-sync.sh pull-plan` against the configured hub, parses action counts (`auto-update` / `new` / `section-merge` / `conflict`), and exits non-zero if any non-zero count remains. Phase 2 of the provider-heal umbrella (BTS-319 shipped Phase 1 — ID resolution; BTS-321 will ship Phase 3 — auth preflight). The primitive is read-only — it does NOT run pull-auto or pull-apply, only reports drift status. Empirical anchor: unifi-toolbox 2026-05-06 had 20 verbs (vs hub's 52) and was missing `linear-query.sh` entirely; even with correct ID config, dispatches failed until `/ccanvil-pull` completed. The heal flow MUST verify substrate is hub-current before exercising new verbs that operations.sh resolvers reference.

## Job To Be Done

**When** I'm running the heal flow on a partially-configured downstream node,
**I want to** know in one read-only command whether the node's substrate is current with the hub before I exercise any new verbs (e.g., `provider-resolve-ids`, `linear-query.sh`),
**So that** dispatch failures from substrate-drift are caught at preflight rather than mid-heal as confusing "command not found" or "null invocation" errors.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `bash .ccanvil/scripts/docs-check.sh provider-heal-preflight --project-dir <path>` exits 0 with stdout `PREFLIGHT-OK: substrate aligned with hub` (newline-terminated) when `ccanvil-sync.sh pull-plan` returns an empty plan or all action counts are 0.
- [ ] **AC-2:** When pull-plan returns non-zero action counts, the command exits non-zero with structured stderr listing each non-zero action + its count + a concrete remediation recipe (`Run /ccanvil-pull or 'bash .ccanvil/scripts/ccanvil-sync.sh pull-auto <hub_path>' to align`).
- [ ] **AC-3:** Hub path is resolved from `<path>/.ccanvil/ccanvil.lock`'s `.hub_source` field (with `~` tilde expansion). When the lock is missing, exits non-zero with `ERROR: <path>/.ccanvil/ccanvil.lock missing — node not initialized as ccanvil project. Run /ccanvil-init first.`
- [ ] **AC-4:** Output is structured JSON when `--json` flag is passed: `{status: "ok"|"drift"|"uninitialized", action_counts: {auto_update: N, new: N, section_merge: N, conflict: N}, hub_path: "<resolved>"}`. Default text output for human reading; JSON for skill composition.
- [ ] **AC-5:** No side-effects: the substrate must NOT execute `pull-auto`, `pull-apply`, or any state-mutating verb. It only reads the plan. (Verified by stub test: ensure pull-plan is invoked but pull-auto/pull-apply are NOT.)
- [ ] **AC-6:** Error: when ccanvil-sync.sh pull-plan exits non-zero (e.g., hub missing on disk, malformed lock), surface the wrapper's stderr verbatim under a `WRAPPER ERROR:` prefix and exit non-zero.
- [ ] **AC-7:** Bats coverage at `hub/tests/provider-heal-preflight.bats` using a stubbed `ccanvil-sync.sh` (mirror the LINEAR_QUERY_OVERRIDE pattern; introduce `CCANVIL_SYNC_OVERRIDE` for this purpose). Test ACs 1, 2, 3, 4, 5, 6 with deterministic stubs.
- [ ] **AC-8:** Manifest declared per Layer 2: `cmd_provider_heal_preflight` includes `# @manifest` block declaring purpose/input/output/depends-on/side-effect/failure-mode/contract. Registered in `.ccanvil/manifest-allowlist.txt`. Drift-guard validates 100%.
- [ ] **AC-9:** Full bats suite passes — 2000/2000 baseline maintained or improved.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_provider_heal_preflight` function + `provider-heal-preflight` subcommand dispatch + `PROJECT_TREE_SUBCOMMANDS` registration (BTS-212 invariant) |
| `hub/tests/provider-heal-preflight.bats` | New: bats coverage for AC-1 through AC-6 using `CCANVIL_SYNC_OVERRIDE` stub |
| `.ccanvil/manifest-allowlist.txt` | Modified: register `cmd_provider_heal_preflight` |

## Dependencies

- **Requires:** existing `ccanvil-sync.sh pull-plan` subcommand (already shipped).
- **Requires:** `.ccanvil/ccanvil.lock` schema with `hub_source` field (already canonical on all initialized nodes).
- **Blocked by:** none.

## Out of Scope

- **Auto-running pull-auto** when drift is detected. Operator runs `/ccanvil-pull` separately. The preflight is a read-only gate, not an auto-healer.
- **Composing into a `provider-heal` umbrella verb.** That's a follow-up that orchestrates Phase 1 (BTS-319) + Phase 2 (this spec) + Phase 3 (BTS-321 auth) into one command.
- **Network-level checks** (hub reachable, GitHub auth). Pull-plan handles its own connectivity errors.
- **Section-merge auto-resolution.** The `section-merge` action count is reported but not resolved.

## Implementation Notes

- Mirror `cmd_provider_resolve_ids` shape for arg parsing (`--project-dir`, future `--json`).
- Hub-path resolution: `jq -r '.hub_source' <path>/.ccanvil/ccanvil.lock` with `${HOME}` substitution for `~`.
- pull-plan returns a JSON array of `{file, action, ...}` objects. Group by `.action` and tabulate counts via `jq`.
- Test fixture pattern: write a stub script that branches on `pull-plan` and returns a deterministic JSON array. Use `CCANVIL_SYNC_OVERRIDE` env var to inject. Mirror `LINEAR_QUERY_OVERRIDE` pattern (BTS-203).
- Anchor file references for AC-7 (per BTS-265 file-ref validator): `.ccanvil/scripts/ccanvil-sync.sh`, `.claude/rules/deterministic-first.md`.
- This primitive is purely read-only deterministic substrate per the deterministic-first rule — no Claude reasoning involved. It's the idiomatic shape for a preflight gate.
