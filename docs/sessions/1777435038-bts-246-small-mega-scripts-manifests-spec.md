# Feature: Small mega-scripts batch manifests

> Feature: bts-246-small-mega-scripts-manifests
> Work: linear:BTS-246
> Created: 1777431919
> Subject: Small mega-scripts batch manifests
> Status: In Progress

## Summary

Manifest rollout Session 7 per `docs/manifest-rollout.md`. Add `# @manifest` blocks for the 16 cmd\_\* across the four remaining small mega-scripts: [permissions-audit.sh](<http://permissions-audit.sh>) (6), [manifest-check.sh](<http://manifest-check.sh>) (7), [operations.sh](<http://operations.sh>) (2), [context-budget.sh](<http://context-budget.sh>) (1). Coverage-only. Allowlist 118 → 134. After this ship, the rollout reaches the natural pause point — all shell scripts manifest-covered.

## Job To Be Done

**When** I extend Layer 2 coverage to the remaining shell substrate primitives,
**I want to** declare 16 inline manifests + markers across 4 small mega-scripts and grow the allowlist to 134,
**So that** every shell-resident cmd\_\* in `.ccanvil/scripts/` carries machine-readable contract semantics, drift-guard catches future regressions structurally, and `/recall` reports `134 / 134, drift: 0`.

## Acceptance Criteria

- [ ] **AC-1:** All 16 cmd\_\* declare a complete `# @manifest` block. Required keys present.
- [ ] **AC-2:** Every declared `failure-mode` line has a matching `# @failure-mode: <id>` source marker.
- [ ] **AC-3:** Every declared `side-effect` line has a matching `# @side-effect: <id>` source marker.
- [ ] **AC-4:** `.ccanvil/manifest-allowlist.txt` appended with 16 entries grouped under `# BTS-246 — Session 7: small mega-scripts batch.` plus per-script sub-headers.
- [ ] **AC-5:** `bash .ccanvil/scripts/module-manifest.sh validate --json` reports `coverage: 134/134` and `(drift | length) == 0`.
- [ ] **AC-6:** Bats suite passes.
- [ ] **AC-7:** PR squash-merge title = `feat(bts-246-small-mega-scripts-manifests): small mega-scripts batch manifests`.
- [ ] **AC-8:** Live-AC — next `/recall` after merge surfaces `Manifest coverage: 134 / 134 (allowlist), drift: 0`.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/permissions-audit.sh` | Modified — 6 manifest blocks |
| `.ccanvil/scripts/manifest-check.sh` | Modified — 7 manifest blocks |
| `.ccanvil/scripts/operations.sh` | Modified — 2 manifest blocks |
| `.ccanvil/scripts/context-budget.sh` | Modified — 1 manifest block |
| `.ccanvil/manifest-allowlist.txt` | Modified — +16 entries |

## Dependencies

* **Requires:** BTS-239 (substrate origin), BTS-243/244/245 (rollout pattern reference).

## Out of Scope

* Function-body changes. Coverage-only.
* New tests.
* File-level shell + hooks (Session 8) and markdown (Sessions 9–10).

## Implementation Notes

* *In-scope cmd\_* (16):\* Batch 1 permissions-audit (6), Batch 2 manifest-check (7), Batch 3 operations + context-budget (3).
* **Format/quality gate:** Same as BTS-244/245. Per-batch validate-fix-commit. Drift-guard catches phantoms.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
