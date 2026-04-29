# Feature: ccanvil-sync.sh stack + registry cluster manifests

> Feature: bts-244-ccanvil-sync-stack-registry-manifests
> Work: linear:BTS-244
> Created: 1777421063
> Subject: ccanvil-sync.sh stack + registry cluster manifests
> Status: In Progress

## Summary

Manifest rollout Session 5 per `docs/manifest-rollout.md`. Add `# @manifest` blocks (BTS-239 substrate, 10-key shape) for the remaining 21 cmd_* in `.ccanvil/scripts/ccanvil-sync.sh` — lockfile primitives, scan/migrate/register/relocate, stasis-migration + registry/events, broadcast + globals, stacks + drift-watchdog. Coverage-only ship; no body changes. Allowlist 81 → 102. After this ship, `ccanvil-sync.sh` is 100% manifest-covered (43/43 cmd_*).

## Job To Be Done

**When** I extend Layer 2 coverage to the remaining sync substrate primitives,
**I want to** declare 21 inline manifests + markers across `ccanvil-sync.sh` and grow the allowlist to 102,
**So that** every sync verb (lockfile / scan / migrate / register / broadcast / stack-apply / drift-watchdog) carries machine-readable contract semantics, drift-guard catches future regressions structurally, and `/recall` reports `102 / 102, drift: 0`.

## Acceptance Criteria

- [ ] **AC-1:** All 21 cmd_* in scope declare a complete `# @manifest` block. Required keys present: `purpose`, `input`, `output`, `side-effect`, `failure-mode`, `contract`, `anchor`. Conditional keys (`caller`, `depends-on`, `routes-by`) declared where applicable.
- [ ] **AC-2:** Every declared `failure-mode` line has a matching `# @failure-mode: <id>` source marker at the failing return/exit line.
- [ ] **AC-3:** Every declared `side-effect` line has a matching `# @side-effect: <id>` source marker at the mutating line.
- [ ] **AC-4:** `.ccanvil/manifest-allowlist.txt` appended with 21 entries grouped under `# BTS-244 — Session 5: ccanvil-sync.sh stack + registry cluster.` plus per-batch sub-headers.
- [ ] **AC-5:** `bash .ccanvil/scripts/module-manifest.sh validate --json` reports `coverage: 102/102` and `(drift | length) == 0`.
- [ ] **AC-6:** Bats suite passes — no regression. No new tests this ship.
- [ ] **AC-7:** PR squash-merge title = `feat(bts-244-ccanvil-sync-stack-registry-manifests): ccanvil-sync.sh stack + registry cluster manifests`.
- [ ] **AC-8:** Live-AC — next `/recall` after merge surfaces `Manifest coverage: 102 / 102 (allowlist), drift: 0`. `ccanvil-sync.sh` is 100% covered (43/43 cmd_*).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — 21 `# @manifest` blocks + inline markers added |
| `.ccanvil/manifest-allowlist.txt` | Modified — +21 entries with section headers |

## Dependencies

- **Requires:** BTS-239 (substrate origin), BTS-243 (Part 1 — sync core, pattern reference).
- **Blocked by:** none.

## Out of Scope

- Function-body changes. Coverage-only ship.
- New tests.
- Other mega-scripts (linear-query, manifest-check, etc.) — Sessions 6–7.

## Implementation Notes

- **In-scope cmd_* (21):** Batch 1 lockfile — cmd_lock_get, cmd_lock_update, cmd_lock_add, cmd_lock_remove, cmd_lock_set_version. Batch 2 scan/migrate — cmd_scan, cmd_migrate, cmd_register, cmd_relocate. Batch 3 stasis-migration + registry/events — cmd_migrate_stasis_artifact, cmd_registry, cmd_events. Batch 4 broadcast + globals — cmd_broadcast, cmd_broadcast_resolve_auto, cmd_pull_globals. Batch 5 stacks + drift-watchdog — cmd_stack_list, cmd_stack_apply, cmd_drift_watchdog_list, cmd_drift_watchdog_preflight, cmd_drift_watchdog_launchd_install, cmd_drift_watchdog_launchd_print.
- **Format/quality gate:** Same as BTS-243. Per-batch validate-fix-commit loop. Drift-guard structural enforcement.
- **Caller resolution gotchas:** Some primitives have no external callers (only dispatch table) — omit `caller:` field rather than declaring phantom callers.
- **AC-29 grep guard awareness:** Reword any `purpose:` line that accidentally contains retired vocab.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
