# Feature: remote-presence check primitive

> Feature: bts-117-remote-presence-check
> Work: linear:BTS-117
> Created: 1777073597
> Status: Complete

## Summary

Conversational guidance after `ccanvil-sync.sh broadcast` (and other lifecycle handoffs) currently assumes every node has `origin` configured. Across 7+ downstream nodes, several didn't — Claude suggested `git push origin main` and the user got "fatal: 'origin' does not appear to be a git repository". Add a deterministic primitive `docs-check.sh remote-presence [repo-dir]` that emits structured JSON about origin presence, so any prose layer (broadcast summary, skill suggestions) can branch on it before recommending push commands.

## Job To Be Done

**When** I (Claude) am about to suggest `git push origin main` after a broadcast, land, or other lifecycle step,
**I want to** check origin presence via a deterministic call,
**So that** I never propose a push to a non-existent remote on local-only nodes.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh remote-presence` (no args, run inside a repo with origin) emits JSON `{"has_origin": true, "url": "<remote-url>", "git_repo": true}` and exits 0.
- [ ] **AC-2:** Same command in a repo WITHOUT origin emits `{"has_origin": false, "url": null, "git_repo": true}` and exits 0 (informational, not an error).
- [ ] **AC-3:** Run outside any git repo emits `{"has_origin": false, "url": null, "git_repo": false}` and exits 0.
- [ ] **AC-4:** Optional `[repo-dir]` positional arg targets a specific directory (default `.`).
- [ ] **AC-5:** JSON shape is stable: always an object with `has_origin` (bool), `url` (string|null), `git_repo` (bool) keys present.
- [ ] **AC-6:** Multiple remotes (origin + upstream + others) — only `origin` is reported (consistent with the failure mode described in the ticket).
- [ ] **AC-7:** Exit code is always 0 — this is a probe, not a gate. Callers branch on `has_origin`, never on exit code.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_remote_presence` + dispatch |
| `hub/tests/remote-presence.bats` | New — 7 cases covering AC-1..AC-7 |

## Dependencies

- **Requires:** Just `git` (already a hard dep).
- **Blocked by:** Nothing.

## Out of Scope

- Wiring the primitive into every existing prose path that suggests push. Adding `remote-presence` exposes the contract; skill prose adoption is a follow-on if the primitive's value is clear.
- Adding remote-add suggestions / interactive flows.
- Checking per-remote reachability (network call) — this is a local config probe only.
- Multiple remotes — only `origin` is in scope per the ticket's failure mode.

## Implementation Notes

- Use `git -C <dir> remote get-url origin 2>/dev/null` to check presence; non-zero exit means no origin.
- Use `git -C <dir> rev-parse --is-inside-work-tree 2>/dev/null` to gate the `git_repo` flag.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
