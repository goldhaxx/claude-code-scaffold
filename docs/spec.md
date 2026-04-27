# Feature: /spec dispatches via artifact-write on Linear-routed nodes

> Feature: bts-213-spec-skill-linear-routing
> Work: linear:BTS-213
> Created: 1777268075
> Status: In Progress

## Summary

Close the silent inconsistency on Linear-routed nodes: today `/spec` writes
only `docs/specs/<id>.md`. After `/spec` + `activate`, `lifecycle-state`
queries Linear (because `routing.spec=linear`) and finds no Document, so it
reports `state: no-active-spec` even though a spec was just authored. This
ship makes `/spec` and `activate` route-aware so the Linear Document is the
canonical content source on Linear-routed nodes, while pure-local nodes are
byte-identical to today.

## Job To Be Done

**When** I'm working on a Linear-routed node (`integrations.routing.spec=linear`),
**I want to** run `/spec BTS-N` and have lifecycle state reflect the spec post-activate,
**So that** `/recall`, `/plan`, `/pr`, and friends find the spec without manual recovery.

## Acceptance Criteria

- [ ] **AC-1:** When `_lifecycle_route spec` resolves to `linear`, `/spec`
      dispatches the composed spec content through
      `docs-check.sh artifact-write --kind spec --feature <BTS-N>` AFTER
      writing the local archive `docs/specs/<feature_id>.md`. The dispatch
      uses caller-supplied UUID (already implemented) for idempotent
      first-write, and surfaces non-zero exit with the linear-query
      diagnostic on stderr.
- [ ] **AC-2:** When `_lifecycle_route spec` resolves to `local` (default),
      `/spec` writes ONLY `docs/specs/<feature_id>.md` — no Linear network
      query is fired (verified via stub fixture asserting curl is never
      invoked).
- [ ] **AC-3:** `cmd_activate` becomes route-aware: after flipping
      `docs/specs/<id>.md` status to `In Progress` and committing the branch,
      when `_lifecycle_route spec == linear`, dispatch
      `cmd_artifact_write --kind spec --feature <id>` with the
      In-Progress-stamped content. This keeps the Linear Document content in
      sync with the local archive's status field.
- [ ] **AC-4:** Post-`/spec` + `activate` on a Linear-routed fixture node,
      `cmd_lifecycle_state --project-dir .` returns `state: spec-activated`
      (not `no-active-spec`). Drift-guard hits the existing
      `_artifact_present_linear` path through a stubbed
      `linear-query.sh document-updated-at`.
- [ ] **AC-5:** Post-`/spec` + `activate` on a pure-local node (no `routing.spec`
      or `routing.spec=local`), `cmd_lifecycle_state` returns the existing
      filesystem-derived state. No regression: the AC-2 "curl never invoked"
      assertion holds.
- [ ] **AC-6 (error):** When `routing.spec=linear` but `LINEAR_API_KEY` is
      missing or the API rejects the dispatch, `/spec` exits non-zero from
      the dispatch step AFTER the local archive has been written. The local
      archive remains on disk so the operator can retry the dispatch
      without re-composing the spec body. The skill prose surfaces the
      retry path: `bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature <id> < docs/specs/<id>.md`.
- [ ] **AC-7 (idempotency):** Running `/spec BTS-N` twice for the same
      feature is safe: the second dispatch resolves the same deterministic
      Document UUID; `cmd_artifact_write` takes the update path (no
      duplicate Documents created in Linear). Verified via stub fixture
      asserting first call → `documentCreate`, second call → `documentUpdate`.

## Affected Files

| File | Change |
|------|--------|
| `.claude/commands/spec.md` | Step 8: add Linear-route dispatch after local archive write |
| `.claude/skills/spec/SKILL.md` | Mirror of step 8 (the canonical skill location) |
| `.ccanvil/scripts/docs-check.sh` | `cmd_activate`: append Linear-route dispatch post-status-flip |
| `hub/tests/ssot-linear.bats` | New drift-guards: AC-1/2/4/5/6/7 fixtures |
| `.ccanvil/guide/command-reference.md` | Note `/spec` dual-write contract |

## Dependencies

- **Requires:** BTS-204 substrate (`_lifecycle_route`, `cmd_artifact_write`,
  `_artifact_present_linear`, `_active_feature_id`) — already shipped.

## Out of Scope

- Migrating existing local-archive specs into Linear (use `ssot-migrate`).
- Eliminating the local archive entirely on Linear-routed nodes — the
  archive remains the metadata-bearing record (`Status:`, `Type:`,
  `Feature:`) and survives `/complete` as durable git history.
- Atomic dual-write transactions (local + Linear). Failure modes documented
  in AC-6; manual retry is the recovery path.
- `/plan` and `/stasis` parallel migrations — already shipped under BTS-204.

## Implementation Notes

- Same dispatch shape as the BTS-204 stasis migration in `.claude/skills/stasis/SKILL.md`:
  compose content → `printf '%s' "$content" | bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature <id>`.
- `/spec`'s current step 8 already runs `stamp-spec` after the write — keep
  that ordering: stamp first (writes epoch into the local archive), then
  dispatch (so the Linear Document carries the stamped content too).
- `cmd_activate` modification: detect `_lifecycle_route spec == linear`
  AFTER the existing `update_metadata_status` + `cp` + `git commit` path,
  then `cat "$docs_dir/spec.md" | cmd_artifact_write --kind spec --feature "$feature_id"`.
  This keeps the existing local-route path untouched (zero-risk regression).
- Test pattern: lift `_setup_stub` from existing ssot-linear.bats; mock
  `linear-query.sh` calls via curl-arg capture; route by JSON variant.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
