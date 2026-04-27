# Feature: BTS-217 Flip Linear routing on hub for spec/plan/stasis

> Feature: bts-217-flip-linear-routing
> Work: linear:BTS-217
> Created: 1777304185
> Status: In Progress

## Summary

Flip the hub's lifecycle-doc routing for `spec`, `plan`, and `stasis` to Linear so the SSOT-Linear substrate (BTS-204 → BTS-213 → BTS-214 → BTS-216) is exercised on the hub's own future ships. Substrate is proven end-to-end against the live API as of 2026-04-27; this ship is operator-decision-only configuration, not new code. The deliverable is a single edit to `.claude/ccanvil.local.json` plus an in-session dogfood validation that confirms `cmd_artifact_write` writes to a Linear Document, `cmd_artifact_read` retrieves it, and `_complete_archive_linear` archives + trashes correctly at `/pr` time.

## Job To Be Done

**When** I finish a feature on the hub itself,
**I want to** have its spec/plan/stasis live as Linear Documents parented to the linked Linear ticket — not as untracked branch-local files,
**So that** every cross-session lookup, retrospective, and parent-ticket review goes to one source of truth instead of git-archive-spelunking for branch-deleted lifecycle docs.

## Acceptance Criteria

- [ ] **AC-1: Routing keys present.** `.claude/ccanvil.local.json` contains `integrations.routing.spec="linear"`, `routing.plan="linear"`, `routing.stasis="linear"` after the flip. `bash .ccanvil/scripts/docs-check.sh route-of spec --project-dir .` returns `linear`.

- [ ] **AC-2: Live artifact-write round-trip.** `printf '# smoketest\n' | bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature BTS-217 --project-dir .` exits 0 and emits a Linear Document URL on stdout. The Document is parented to the BTS-217 issue (verifiable via `linear-query.sh list-documents --issue BTS-217`).

- [ ] **AC-3: Live artifact-read symmetry.** `bash .ccanvil/scripts/docs-check.sh artifact-read --kind spec --feature BTS-217 --project-dir .` returns the body of the Document written in AC-2 (NOT the contents of `docs/specs/bts-217-flip-linear-routing.md`).

- [ ] **AC-4: /pr embed reads from Linear.** When `/pr` is run on this feature branch, the resulting PR body's spec embed contains the Linear-routed content. Verify by inspecting the PR body via `gh pr view --json body` before squash-merge.

- [ ] **AC-5: /complete archives + trashes.** `cmd_complete bts-217-flip-linear-routing` (called by `pr-cleanup`) archives the spec/plan/stasis Documents into `docs/sessions/<epoch>-bts-217-flip-linear-routing-{spec,plan,stasis}.md` and the originals no longer surface via `linear-query.sh list-documents --issue BTS-217` (default excludes trashed).

- [ ] **AC-6: Edge — downstream nodes unaffected.** `.claude/ccanvil.json` (hub-tracked) is NOT modified — the routing flip lives only in `.claude/ccanvil.local.json` (gitignored). Reading any registered downstream node's `.claude/ccanvil.local.json` shows `spec/plan/stasis` still default to local (or absent, which means local).

- [ ] **AC-7: Error — graceful degradation on Linear API failure.** If `LINEAR_API_KEY` is unset OR the live API is unreachable, lifecycle commands (`activate`, `/spec`, `/plan`, `pr-cleanup`) emit a `WARN:` line on stderr with a retry recipe, the local archive at `docs/specs/<feature_id>.md` (or equivalent) is preserved as the durable state, and the command does not abort.

## Affected Files

| File | Change |
|------|--------|
| `.claude/ccanvil.local.json` | Modified — add 3 routing keys (`spec`, `plan`, `stasis` → `"linear"`) |
| `docs/specs/bts-217-flip-linear-routing.md` | New — this spec |

No code changes. No tests. No `.ccanvil/scripts/` mutations.

## Dependencies

- **Requires:** BTS-204 (substrate), BTS-213 (`/spec` dispatch), BTS-214 (archive batch-read), BTS-216 (RFC 4122 v4 UUID fix). All shipped 2026-04-25 → 2026-04-27.
- **Blocked by:** None.

## Out of Scope

- Any code changes to `.ccanvil/scripts/`, `.claude/skills/`, hooks, or guard scripts.
- Propagating the flip to downstream nodes via `/ccanvil-pull` or `broadcast`. Migration is opt-in per node.
- Multi-machine sync of `.claude/ccanvil.local.json` (gitignored by design).
- Changing the namespace UUID used for deterministic Document IDs.
- Correcting the project_id discrepancy in the BTS-217 ticket body itself — that is a follow-up Linear comment, not part of this spec.

## Implementation Notes

- **Project_id discrepancy.** The BTS-217 ticket body cites Linear `project_id` `0c5fec47-fa1c-4e2c-9e0a-4b4dc0fc05d6`, but `.claude/ccanvil.local.json` already carries `project_id: 305b7cbe-cd8d-4fce-bcff-bbfee74b2e44` and that ID has driven every successful BTS-128/166/167 dispatch since the http resolver shipped. **Local config is canonical.** Do NOT "fix" it to match the ticket body. The ticket body's value is incorrect (likely a copy-paste artifact from prior session prose). Post a Linear comment on BTS-217 after the flip lands to correct the ticket body for future readers.

- **The flip is a 3-key edit.** Add `"spec": "linear"`, `"plan": "linear"`, `"stasis": "linear"` peers to the existing `"idea": "linear"` under `integrations.routing` in `.claude/ccanvil.local.json`. `project_id`, `team_id`, and the state/label maps are already present.

- **Dogfood validation IS the test.** This spec ships no bats tests because there is nothing to unit-test — the substrate is proven, this is configuration. The acceptance criteria are end-to-end validations against the live Linear API. `/review` should focus on whether the live round-trips actually executed against `api.linear.app`, not stub coverage.

- **Pattern reference.** The existing `routing.idea = "linear"` line in the same file is the precedent shape. Add three peer keys; preserve formatting (2-space indent).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
