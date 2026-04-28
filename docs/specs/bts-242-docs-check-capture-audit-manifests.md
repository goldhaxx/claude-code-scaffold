# Feature: docs-check.sh capture+audit cluster manifests

> Feature: bts-242-docs-check-capture-audit-manifests
> Work: linear:BTS-242
> Created: 1777409844
> Subject: docs-check.sh capture+audit cluster manifests
> Status: In Progress

<!-- Subject: docs-check.sh capture+audit cluster manifests (24 primitives, completes file coverage) -->

## Summary

Session 3 of the manifest rollout (`docs/manifest-rollout.md`). Add full `# @manifest` blocks + inline source markers to the remaining 24 `cmd_*` primitives in `.ccanvil/scripts/docs-check.sh` — the capture/triage/artifact/audit/route cluster. After this ship, `docs-check.sh` is 100% manifest-covered (51/51 cmd_*). Allowlist grows 35 → 59. No substrate changes.

## Job To Be Done

**When** future-Claude / future-operators read or modify the idea-capture, route-of, artifact-read, evidence-scan, stasis-archive, or radar-gather primitives,
**I want to** see machine-readable contracts inline at every primitive declaring its purpose, inputs, outputs, callers, dependencies, side effects, failure modes, and design anchors,
**So that** docs-check.sh — the central substrate file — is fully self-describing, drift-guard catches every behavior change, and `cmd_query` enables substrate-discovery across the whole file.

## Acceptance Criteria

- [ ] **AC-1:** Each of the 24 capture+audit primitives carries a `# @manifest` block immediately above its function definition. All 7 required keys non-empty.
- [ ] **AC-2:** Each declared `failure-mode: <id>` has a matching inline `# @failure-mode: <id>` marker; each `side-effect: <id>` has a matching `# @side-effect: <id>` marker.
- [ ] **AC-3:** Each declared `caller:` resolves via `_caller_actually_calls_primitive`. No phantom callers.
- [ ] **AC-4:** Each declared `depends-on:` value appears (word-boundary) in the primitive body. No phantom dependencies.
- [ ] **AC-5:** Allowlist grows 35 → 59 with 24 new entries under `# Session 3 — capture + audit cluster.`
- [ ] **AC-6:** `module-manifest.sh validate --json` reports `coverage: 59/59, drift: []`.
- [ ] **AC-7:** Existing 1923-baseline bats suite passes — no regression.
- [ ] **AC-8:** `docs/manifest-rollout.md` Inventory `Done` for `docs-check.sh` row updates from 27 → 51 (51 cmd_* total in docs-check.sh; full coverage of that file).
- [ ] **AC-9:** Live-AC — next session's `/recall` step 11 surfaces `Manifest coverage: 59 / 184, drift: 0`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — 24 `# @manifest` blocks + inline markers |
| `.ccanvil/manifest-allowlist.txt` | Modified — 24 new entries under Session-3 header |
| `docs/manifest-rollout.md` | Modified — Inventory `Done` updated |

## Dependencies

- **Requires:** BTS-239 + BTS-240 + BTS-241 (all landed). 
- **Blocked by:** none.

## Out of Scope

- Other mega-scripts (`ccanvil-sync.sh`, `linear-query.sh`, etc.) — Sessions 4-7.
- Markdown bulk rollout — Sessions 9-10.
- Layer 3 ramp — Session 11.

## Implementation Notes

- Same per-primitive workflow as Session 2: read body, enumerate inputs/outputs/side-effects/failure-modes/depends-on/caller, compose manifest, add markers, batch-commit, validate.
- Lessons from S2 (memorize for resolver-friendliness):
  - **Caller resolver greps for both function name AND verb form.** A "real" caller must contain `\bcmd_X\b` OR `\bx-with-dashes\b` as word-boundary match. Files containing `specific` etc. don't match `\bspec\b`.
  - **`skill:/<name>` callers must be in `.claude/skills/<name>/SKILL.md` OR `.claude/commands/<name>.md`** with the verb word-boundary present.
  - **Don't declare phantom convenience callers.** Drift-guard catches every one.
  - **`depends-on` must be in the function body word-boundary.** External tools (`jq`, `git`, `gh`) commonly are; helper functions must actually be called.
- Batch into 4 groups of 6 like S2; validate after each batch.
- Bash 3.2 compat preserved (no substrate changes).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
