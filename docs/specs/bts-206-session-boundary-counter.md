# Feature: Session-boundary counter + ISO local timestamp

> Feature: bts-206-session-boundary-counter
> Work: linear:BTS-206
> Created: 1777254424
> Status: Complete

## Summary

Every fresh Claude Code session bumps a persistent session counter and stamps the boundary epoch + ISO-8601 local time into `.ccanvil/state/`. Both surfaces are then read by `/stasis` (write side, into metadata) and `/recall` (read side, into the cold-start briefing). The result: stasis archives carry a human-readable "Session 47, started 2026-04-26T18:44:36-07:00" header, and /recall reports the current local-time context on resume — no more squinting at epoch integers to tell when a session ran.

## Job To Be Done

**When** I open Claude Code on a fresh session,
**I want to** see a monotonically-increasing session number and a human-readable local timestamp at the boundary,
**So that** I can scan stasis archives for cross-session patterns and orient on resume without converting epoch integers in my head.

## Acceptance Criteria

- [ ] **AC-1: SessionStart hook bumps counter.** A `SessionStart` hook (registered in `.claude/settings.json`) atomically increments `.ccanvil/state/session-counter` (single integer file) on every fresh session boundary. First-run on a node initializes the file to `1`.
- [ ] **AC-2: SessionStart hook stamps ISO boundary.** Same hook writes `.ccanvil/state/session-boundary` containing `{epoch:<int>, iso:<ISO-8601-local>, tz:<IANA-or-offset>}` JSON. ISO timestamp includes timezone offset (e.g., `2026-04-26T18:44:36-07:00`) derived from `TZ` env or system default.
- [ ] **AC-3: `docs-check.sh session-info` primitive.** New subcommand emits `{counter, epoch, iso, tz}` JSON from the two state files. Used by /stasis and /recall as a single resolver call. Exit 0 with `{counter:0, epoch:null, iso:null, tz:null}` if state files don't exist (fresh node).
- [ ] **AC-4: stasis metadata carries session + boundary.** `.ccanvil/templates/stasis.md` adds `> Session: N` and `> Boundary: <ISO>` lines. The /stasis skill reads `session-info` and substitutes both fields. Validator (`docs-check.sh validate`) treats absence as legacy-grandfathered, presence as canonical.
- [ ] **AC-5: /recall briefing surfaces session + boundary.** Briefing prose includes a one-liner like "**Session N** — boundary <ISO>" near the top, sourced from `session-info`. When `session-info` returns counter=0 (fresh node), the line is omitted (no zero-noise).
- [ ] **AC-6: counter is monotonic across compact.** The hook fires on every `SessionStart`, including post-compact session resumes. The counter MUST increment, never reset, never skip. Drift-guard: a bats test that simulates two sequential SessionStart invocations and asserts counter goes N → N+1.
- [ ] **AC-7: edge — TZ env override respected.** When `TZ` env is set, `iso` reflects that zone. When `TZ` is unset, system local time is used. Drift-guard: bats test runs the hook with `TZ=UTC` and asserts the ISO string ends in `+00:00` or `Z`.
- [ ] **AC-8: edge — counter file corruption.** If `.ccanvil/state/session-counter` exists but contains a non-integer, the hook resets to `1` and logs a single WARN to stderr. Never aborts the session start.
- [ ] **AC-9: hook is non-blocking.** SessionStart hook total runtime <50ms on warm cache. Failures (write errors, fs full) MUST log WARN and exit 0 — never block the session.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/session-boundary.sh` | New — SessionStart hook script |
| `.claude/settings.json` | Modified — register SessionStart hook |
| `.ccanvil/scripts/docs-check.sh` | Modified — add `cmd_session_info` + dispatcher entry |
| `.ccanvil/templates/stasis.md` | Modified — add `> Session:` and `> Boundary:` metadata |
| `.claude/skills/stasis/SKILL.md` | Modified — call `session-info`, inject into metadata |
| `.claude/skills/recall/SKILL.md` | Modified — call `session-info`, surface in briefing |
| `hub/tests/session-boundary.bats` | New — drift-guards for AC-1, AC-2, AC-3, AC-6, AC-7, AC-8 |
| `hub/tests/stasis-skill.bats` | Modified — assert stasis prose mentions session-info |
| `hub/tests/recall-skill.bats` | Modified — assert recall prose mentions session-info |

## Dependencies

- **Requires:** `.ccanvil/state/` directory (already present per BTS-113 last-compact-ts)
- **Blocked by:** none

## Out of Scope

- Backfilling session numbers for historical archives in `docs/sessions/` (forward-only)
- Multi-machine counter sync (counter is per-node by design)
- Drift recovery if counter file is deleted (next SessionStart resets to 1; acceptable)
- Surfacing session number in commit messages or PR bodies (separate concern)
- Cross-session pattern detection logic that *uses* the counter (this ship makes it available; future work consumes it)

## Implementation Notes

- Mirror the deterministic-script pattern from `.claude/hooks/post-compact-marker.sh` — short bash, atomic write via `mktemp + mv`, never blocks
- Use `date -u +%s` for epoch and `date '+%Y-%m-%dT%H:%M:%S%z'` (with sed to insert `:` in offset) for ISO. macOS `date` lacks `--iso-8601=seconds`; do the format manually.
- Atomic counter increment: read int → bump → write to `.tmp` → mv. No flock needed (SessionStart fires once per session boundary, not concurrently).
- `cmd_session_info` is a thin reader — pure deterministic, no Linear or git side-effects.
- Follow `.claude/rules/deterministic-first.md` — every step is computable; no Claude reasoning in the hook path.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
