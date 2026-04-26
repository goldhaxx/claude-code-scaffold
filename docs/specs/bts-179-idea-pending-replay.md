# Feature: idea-pending-replay substrate primitive

> Feature: bts-179-idea-pending-replay
> Work: linear:BTS-179
> Created: 1777215402
> Status: Complete

## Summary

Add `docs-check.sh idea-pending-replay`: a deterministic substrate primitive that iterates `.ccanvil/ideas-pending.log`, dispatches each entry by `op` via the http substrate (resolves `idea.add` or `ticket.transition`, eval's the resolved command), and ack's on success. The `/idea sync` skill prose collapses from a ~30-line per-skill shell loop to a single `resolve` + `eval` call. Eliminates the echo-then-jq round-trip class of bug surfaced 2026-04-26 when JSON-escaped `\n` in entry bodies corrupted the dispatch under shells where `echo` interprets backslashes.

## Job To Be Done

**When** `.ccanvil/ideas-pending.log` has unsynced entries from a prior Linear failure,
**I want to** run `/idea sync` and have every entry replayed deterministically by substrate (not by skill-prose shell logic),
**So that** dispatch correctness doesn't depend on which shell or `echo` variant the implementer is running, and the skill prose stays trivial.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh idea-pending-replay` exists. When the log is empty, it prints `{"synced":0,"failed":0,"pending":0,"entries":[]}` and exits 0.
- [ ] **AC-2:** Replay of an `add` entry dispatches via `operations.sh resolve idea.add` + `eval "$cmd --input-json -"` with `{title, description}` piped via stdin-JSON. When `args.parent_id` is present, `--parent-id` is appended via `jq -Rr @sh`.
- [ ] **AC-3:** Replay of a `promote` entry dispatches via `operations.sh resolve ticket.transition <id> backlog` + `eval "$cmd --priority <N>"`.
- [ ] **AC-4:** Replay of a `defer` / `dismiss` / `merge` / `ticket.transition` entry dispatches via the matching `ticket.transition` resolution, with `--duplicate-of` appended for `merge`.
- [ ] **AC-5:** On per-entry success, the entry is ack'd via `idea-sync --ack <ts>` (removed from the log). On per-entry failure (non-zero exit from eval), the entry is preserved and replay continues to the next entry.
- [ ] **AC-6:** Final output is JSON: `{"synced":N,"failed":M,"pending":K,"entries":[{ts,op,result,error?}]}`. Exit code is 0 when `failed == 0`, non-zero otherwise.
- [ ] **AC-7 (regression):** A body containing literal `\n` JSON escape sequences (e.g. `"## What\n\nfirst paragraph"`) round-trips through replay without corruption — the description posted to Linear contains real newlines (not the literal characters `\n`), and no `jq: parse error` surfaces.
- [ ] **AC-8 (resolver wiring):** `operations.sh resolve idea.sync` returns `.invocation.command` pointing to `docs-check.sh idea-pending-replay` (not `idea-sync` — which remains the enumerate-only primitive for backwards compat).
- [ ] **AC-9 (skill prose collapse):** `/idea sync` skill section reduces to: resolve `idea.sync`, eval the resolved command, render the JSON summary. The per-op dispatch table stays as documentation but is no longer the executable contract.
- [ ] **AC-10 (drift-guard):** A bats test asserts the `/idea sync` skill section in `.claude/skills/idea/SKILL.md` contains a single `eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"` form and does NOT contain a per-op `case "$op" in` block.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_idea_pending_replay` + dispatch case |
| `.ccanvil/scripts/operations.sh` | `idea.sync` resolver returns `idea-pending-replay` |
| `.claude/skills/idea/SKILL.md` | Sync section collapsed to single resolve+eval |
| `hub/tests/idea-pending-replay.bats` | New: AC-1 through AC-7 |
| `hub/tests/idea-skill-sync-collapse.bats` | New: AC-10 drift-guard |

## Dependencies

- **Requires:** BTS-166 http substrate (idea.add via http), BTS-164 ticket.transition via http. Both shipped.
- **Blocked by:** Nothing.

## Out of Scope

- Modifying `idea-pending-append` (stays as-is — write side is already deterministic).
- Modifying `idea-sync` enumerate primitive (preserved for any external consumer).
- Concurrency safety (the log is single-writer; no locking added).
- Retry/backoff logic on failure — failed entries simply persist for the next manual `/idea sync` pass.

## Implementation Notes

- The dispatch logic mirrors the existing skill prose but lives in bash inside `cmd_idea_pending_replay`. Use `jq -c '.[]' <(jq -s . pending.log)` or equivalent to iterate entries cleanly without echo round-trips.
- Auth handling (`LINEAR_API_KEY`) is delegated to `linear-query.sh` — replay does not handle auth itself.
- Live-validation gate (per `.claude/rules/tdd.md` BTS-171): once the bash command is wired up, run ONE live `idea-pending-replay` against a real pending entry before committing — replays the `\n`-corruption regression directly. The substrate is mostly mechanical, but the eval-with-stdin-JSON contract is exactly the surface that broke at the skill-prose layer.
- BTS-127: any test block with ≥2 `jq -e` assertions starts with `set -e`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
