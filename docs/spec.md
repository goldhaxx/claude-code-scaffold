# Feature: canonical hook failure recording — loud, never-block, never-snuff

> Feature: bts-209-hook-failure-recording
> Work: linear:BTS-209
> Created: 1777343134
> Subject: canonical hook failure recording — loud, never-block, never-snuff
> Status: In Progress

## Summary

Telemetry hooks (`post-compact-marker.sh`, `session-boundary.sh`) currently use two inconsistent failure-handling patterns: the BTS-113 hook propagates errors via `set -euo pipefail`; the BTS-206 hook uses `set +e` with explicit per-step `WARN-then-exit-0` guards. Both work, but they diverge on the third property of the canonical contract — *never-snuff*: failures must be recorded durably enough to be reviewable later, not lost when the session ends.

This ship establishes the canonical pattern: per-step explicit guards (BTS-206 shape) PLUS a durable JSONL append to `.ccanvil/state/hook-failures.log`. Provides `_hook_record_failure <hook> <step> <message>` as the deterministic primitive every hook calls on guarded failure. Migrates both existing telemetry hooks. Guard hooks (PreToolUse blockers like `guard-destructive.sh`, `protect-files.sh`) keep their blocking contract — separate concern.

## Job To Be Done

**When** a telemetry hook fails (filesystem I/O error, malformed state file, etc.),
**I want to** see the failure on stderr AND have it persisted to a durable log,
**So that** failures are reviewable in stasis/recall sections after the session ends — not lost to the void.

## Acceptance Criteria

- [ ] **AC-1:** New helper `.claude/hooks/_lib/record-failure.sh` exposes `_hook_record_failure <hook_name> <step> <message>` as a sourceable shell function. Appends one JSONL line `{ts:<epoch>,hook:<name>,step:<step>,message:<message>}` to `.ccanvil/state/hook-failures.log` (JSONL, gitignored).

- [ ] **AC-2:** `post-compact-marker.sh` migrates to the canonical pattern: `set +e`, explicit guards on `mkdir` + `date+write`, calls `_hook_record_failure` on any failure, exits 0.

- [ ] **AC-3:** `session-boundary.sh` (already on the canonical shape) calls `_hook_record_failure` on every WARN path so failures are durable. WARN-to-stderr behavior preserved (loud).

- [ ] **AC-4:** Helper is deterministic: writes use atomic mktemp+append (no read-modify-write race). Append failure (e.g., disk full) is itself silently swallowed at the helper level — there's no further fallback. The failure ALSO emits to stderr so the operator sees it even if the log write fails.

- [ ] **AC-5:** Bats: simulate hook failure (induce a writable-state-dir error or use an explicit test invocation) and assert that the JSONL line appears in `.ccanvil/state/hook-failures.log` with the expected fields.

- [ ] **AC-6:** Bats: hook always exits 0 even when guarded steps fail (regression — never-block contract).

- [ ] **AC-7:** Drift-guard: `BTS-209` referenced inline in `post-compact-marker.sh`, `session-boundary.sh`, and `_lib/record-failure.sh`.

- [ ] **AC-8:** Full bats suite ≥ 1858 (post-BTS-236 baseline).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/_lib/record-failure.sh` | New file: `_hook_record_failure` helper. |
| `.claude/hooks/post-compact-marker.sh` | Migrate to canonical pattern. |
| `.claude/hooks/session-boundary.sh` | Add `_hook_record_failure` calls on WARN paths. |
| `hub/tests/hook-failure-recording.bats` | Tests AC-5, AC-6 + drift. |

## Out of Scope

- **Guard-hook contract change.** PreToolUse blockers (protect-files, guard-destructive, etc.) keep their blocking shape. Telemetry-vs-guard distinction is by hook function, not by file location.
- **Log rotation.** The log grows unbounded. Acceptable for now — revisit if it becomes a problem (separate ticket).
- **Stasis/recall surfacing.** Reading the log into stasis briefings is a downstream concern (BTS-208 territory or a follow-up).
- **Migrating ALL hooks to a uniform shape.** Lint-on-write, format-on-write, and the other dual-purpose hooks have their own contracts. Only the two telemetry hooks are migrated here.
- **Configuration of log location.** Hardcoded to `.ccanvil/state/hook-failures.log`. Future ship can parameterize if needed.

## Implementation Notes

- Helper sources by absolute path: `source "$CLAUDE_PROJECT_DIR/.claude/hooks/_lib/record-failure.sh"` (or relative to the calling hook's location).
- JSONL format: `jq -nc --arg hk "$hook" --arg st "$step" --arg msg "$message" --argjson ts "$(date +%s)" '{ts:$ts,hook:$hk,step:$st,message:$msg}'` then append. jq handles escaping; never use `echo`+interpolation.
- Atomicity: `>>` is sufficient for single-line JSONL appends on local filesystems. No mktemp+mv needed for line-at-a-time writes.
