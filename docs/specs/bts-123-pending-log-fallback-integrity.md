# Feature: Harden pending-log fallback integrity

> Feature: bts-123-pending-log-fallback-integrity
> Work: linear:BTS-123
> Created: 1777073200
> Status: Complete

## Summary

The `/idea` skill's Linear-unavailable fallback path (append to `.ccanvil/ideas-pending.log`, exit 0) has two defects that silently corrupt the replay contract: (1) the writer snippet uses `echo` + shell interpolation into a single-quoted JSON literal, which breaks on newlines/quotes/backslashes/emoji in real bodies; (2) the count snippet uses `wc -l`, conflating physical lines with JSON entries (a single pretty-printed entry reads as N pending). Add a deterministic helper `docs-check.sh idea-pending-append` that owns the write contract via `jq -nc`, plus `idea-pending-validate` that counts entries via `jq -s length` and surfaces malformed lines. Update the `/idea` skill prose to call the helper instead of the unsafe echo snippets.

## Job To Be Done

**When** Linear MCP is unavailable and a capture or transition must fall back to the pending log,
**I want to** delegate the JSONL serialization to a deterministic primitive,
**So that** every pending entry is guaranteed compact, valid, and replayable — regardless of body content.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh idea-pending-append --op add --title <T> --body <B>` writes exactly one compact JSONL line to `.ccanvil/ideas-pending.log` containing `{op:"add", args:{title, body}, ts:<epoch>}`. Body containing literal newlines remains a single physical line in the log file.
- [ ] **AC-2:** Body with double quotes, single quotes, backslashes, backticks, dollar-prefixes, and emoji round-trips losslessly through `jq` after append.
- [ ] **AC-3:** `docs-check.sh idea-pending-append --op promote --id <ID> --priority <N>` writes `{op:"promote", args:{id, priority}, ts}`.
- [ ] **AC-4:** `--op defer|dismiss --id <ID>` writes `{op:..., args:{id}, ts}`.
- [ ] **AC-5:** `--op merge --id <ID> --duplicate-of <DID>` writes `{op:"merge", args:{id, duplicateOf}, ts}`.
- [ ] **AC-6:** `--op ticket.transition --id <ID> --role <ROLE>` writes `{op:"ticket.transition", args:{id, role}, ts}`.
- [ ] **AC-7:** `docs-check.sh idea-pending-validate` reads `.ccanvil/ideas-pending.log`, emits JSON `{count: N, valid: bool, errors: [<line-num>...]}`. Exits 0 when valid, non-zero when any line fails to parse.
- [ ] **AC-8:** `idea-pending-validate` correctly counts entries via `jq -s length` (NOT `wc -l`) — a pretty-printed multi-line legacy entry reports `count: 1, valid: true` if the file is treated as a JSON sequence (or `count: N, valid: false` if line-based and lines aren't JSON). The contract: report objects, not lines.
- [ ] **AC-9:** Missing pending log → `idea-pending-validate` emits `{count: 0, valid: true, errors: []}` and exits 0 (empty is valid).
- [ ] **AC-10:** `/idea` skill prose (`.claude/skills/idea/SKILL.md`) drops the two `echo` snippets in favor of explicit `idea-pending-append` invocations. Hub test asserts skill prose mentions `idea-pending-append` and does NOT contain the legacy `echo '{"op"` literal.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_idea_pending_append`, `cmd_idea_pending_validate`. Dispatch entries. |
| `.claude/skills/idea/SKILL.md` | Replace lines 66–69 and 119–122 echo snippets with helper invocations. Add per-op example calls. |
| `hub/tests/idea-pending-helpers.bats` | New — 9+ cases covering AC-1..AC-10. |

## Dependencies

- **Requires:** `jq` (already a hard dep across the script).
- **Blocked by:** Nothing (BTS-129 already shipped, unblocking this).

## Out of Scope

- **Migration of existing malformed logs.** No corrupt logs in this hub; downstream nodes hit corrupted logs are responsible for manual cleanup. Capture as separate idea if encountered.
- Changing `/idea sync` to read structured ops via the helper (separate concern; sync already reads JSONL).
- Add new ops not already present in the skill (out of scope).

## Implementation Notes

- Use `jq -nc` for serialization. Pattern mirrors `cmd_idea_add` if there's already a similar helper there — check before adding.
- Bash 3.2 compat — no associative arrays.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
- For `idea-pending-validate`, the safest count is: feed the log to `jq -s '. | length'` (slurp). If `jq -s` fails, parse line-by-line with `jq -e .` and report failing lines as errors.
