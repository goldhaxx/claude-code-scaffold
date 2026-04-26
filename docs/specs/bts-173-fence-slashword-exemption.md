# Feature: guard-workspace.sh exempts single-segment slash-prefixed lexical tokens

> Feature: bts-173-fence-slashword-exemption
> Work: linear:BTS-173
> Created: 1777179134
> Status: Complete

## Summary

`guard-workspace.sh` tokenizes inbound Bash commands and runs an absolute-path scan on any token starting with `/`. Slash-command names (`/idea`, `/permissions-review`, `/stasis`) appearing in heredoc bodies, prose strings, or commit-message narratives match the path-shape glob `/?*` and trigger the fence with `BLOCKED: path '<token>' is outside the workspace` — even though they have no filesystem meaning. BTS-169 closed the pure-slash sub-case (`//`, `///+`); this ticket closes the single-segment-alphabetic sub-case. Surfaced 3× in the 2026-04-26 backlog session: BTS-172 capture body (`/idea` token), BTS-173's own capture (`/word` in title), BTS-125 repro flow (`/spec` in payload). Fix: extend the token loop with a second skip rule for tokens matching `^/[a-zA-Z][a-zA-Z0-9_-]{0,29}$` — single-segment, alphabetic-leading, no further separators.

## Job To Be Done

**When** a Bash command contains a slash-command name as a literal lexical fragment (heredoc body, prose, commit message),
**I want** `guard-workspace.sh` to recognize the fragment is not a filesystem path and pass it through,
**So that** captures, repros, and prose-handling flows don't sidestep into tmpfiles to bypass a false-positive that has no security relevance.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cat <<EOF\nslash-idea token in heredoc body\nEOF` (where `slash-idea` is the literal `/idea`) does NOT trigger the fence. Command exits 0 from the hook. Validated by piping the synthetic JSON tool_input to the hook and asserting exit 0.
- [ ] **AC-2:** A real-path absolute `rm /etc/passwd` STILL triggers the fence (regression-guard). Hook exits 2 with `BLOCKED: path '/etc/passwd'`.
- [ ] **AC-3:** A nested-segment absolute `mv /var/log/foo /tmp/bar` STILL triggers the fence on the unauthorized prefix `/var/log/foo`. Hook exits 2.
- [ ] **AC-4:** BTS-169 regression — pure-slash tokens (`//`, `///`) STILL pass through (jq alternative-default operator scenario unchanged). Hook exits 0.
- [ ] **AC-5:** Edge — a non-alphabetic-leading single-segment token (e.g., `/123`, `/_foo`) is NOT exempted by the new rule and continues to hit the path scan. The exemption regex requires alphabetic first character to avoid weakening the real-path check on numeric-prefixed paths or hidden files.
- [ ] **AC-6:** Edge — a long single-segment token (e.g., `/abcdefghijklmnopqrstuvwxyzabcd123` — 33 chars) is NOT exempted. Length cap (≤30 chars after the slash) prevents abuse via long lexical strings that look path-like.
- [ ] **AC-7:** Drift-guard — the exemption rule is annotated with the BTS-173 reference inline so future readers can cross-link to spec + repro evidence.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | Modified — add single-segment-slashword skip rule before path-shape scan |
| `hub/tests/guard-workspace-slashword-exemption.bats` | New — AC-1 through AC-7 regression-and-positive tests |

## Dependencies

- **Requires:** none. Guard is self-contained.
- **Blocked by:** none.

## Out of Scope

- **Punctuation-shaped path tokens.** `/):` from prose like `~/projects/):` (parenthesis-suffix from a comma-list rendering) ALSO triggers the fence. That's a different shape — non-alphabetic, non-numeric, shell-punctuation. Don't expand this ticket; capture as a follow-up if the punctuation case continues to bite. Keep this ticket scoped to the single observed-recurring class (slash-command names).
- **Multi-segment slash-command-like tokens.** `/foo/bar` with two segments looks like a real path; we don't try to disambiguate "this is a doc reference" from "this is a real path." If a slash-command develops two-segment forms, revisit then.
- **Variable-indirection bypass.** Tokens like `$SLASH_CMD` are already known limitations of the fence and out of scope for this ticket.
- **Tilde-prefixed lexical fragments.** `~/something` could in principle be lexical, but the current friction is exclusively `/something`. Out of scope.

## Implementation Notes

- **Allowlist approach (revised mid-implementation).** First-attempt regex-only exemption `^/[a-zA-Z][a-zA-Z0-9_-]{0,29}$` correctly exempted `/idea` BUT also exempted `/etc`, `/var`, `/usr`, `/a` — real system paths and slash-command names are syntactically identical. Two existing tests (BTS-155 AC-10 `find /etc` traversal; BTS-147 AC-6 `/a` whitelist) regressed. Pure-syntactic disambiguation is impossible. Fix: build an allowlist on first-match-attempt by enumerating `$CLAUDE_PROJECT_DIR/.claude/commands/*.md` and `.claude/skills/*/`, cache for the rest of the hook invocation, exempt only single-segment tokens whose basename appears in the allowlist.
- **Skip-rule placement.** Insert AFTER the BTS-169 pure-slash skip and BEFORE the `case "$token" in /?*)` path-shape scan.
- **Why the regex prefilter still applies.** Defense in depth — the regex prunes obvious non-candidates (numeric-leading, underscore-leading, too-long, multi-segment) before paying the directory-listing cost. A token like `/123` doesn't make it to the allowlist check.
- **Allowlist build cost.** Two `for entry in dir/*` glob expansions on first match-attempt within a single hook invocation. Both directories are O(20) entries. Negligible; cost is amortized across the rest of the token loop.
- **Test-fixture pattern.** Mirror `hub/tests/guard-workspace-jq-exemption.bats` (BTS-169) — synthesize the hook's stdin JSON via `jq -n --arg cmd "$CMD" '{tool_input:{command:$cmd}}'` and pipe to the hook script; assert exit code + stderr content.
- **No live-API risk.** Pure shell-logic substrate change. /review skipped per skip-feedback memory.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
