# Feature: Live-API diagnostic surfacing — WARN-on-failure + safe JSON pipe

> Feature: bts-219-live-api-diagnostic-surfacing
> Work: linear:BTS-219
> Created: 1777318789
> Status: In Progress

## Summary

Two substrate gaps in the live-API path silently degrade caller experience:

1. **`cmd_artifact_read` exits 2 with empty stderr** when the Linear API auth is missing, the document doesn't exist, or the network is unreachable. Callers can't distinguish these cases — `recall` sees a blank stasis briefing without diagnostic, `pr-cleanup` archives nothing without explaining why.
2. **drift-watchdog's verification step double-queues successfully-created tickets to the pending log** because `echo "$VERIFY" | jq` hits macOS bash's `echo`-builtin escape interpretation on `\n` sequences inside Linear-API JSON responses (description fields with literal newlines), producing `jq: parse error: Invalid string: control characters from U+0000 through U+001F must be escaped`.

This ship adds WARN-on-failure to `cmd_artifact_read` (mirroring the symmetric pattern already present in `cmd_artifact_write` per BTS-213) and replaces the broken `echo "$VAR" | jq` pattern with safe alternatives (`jq <<< "$VAR"` or `printf '%s' "$VAR" | jq`) wherever the captured variable contains JSON-escape-prone content.

Closes BTS-227 (drift-watchdog false-negative). Note: BTS-227's title frames the bug as a `linear-query.sh get-issue` JSON serialization issue — investigation during this spec session shows the JSON output IS valid; the bug is in the caller's `echo`-based pipe, not in the encoder. The correct fix lives in the caller (drift-watchdog SKILL prose), not in `linear-query.sh`. The spec body acknowledges this re-framing.

## Job To Be Done

**When** a substrate primitive (`cmd_artifact_read`, drift-watchdog verification, etc.) calls a live Linear API and something goes wrong (auth missing, network down, not found, parse error),
**I want to** see a single-line WARN on stderr that names the failure class + a copy-pasteable retry recipe, AND have JSON responses round-trip safely through bash-variable + jq pipes,
**So that** caller skills (`/recall`, `/pr-cleanup`, `/drift-watchdog`) surface actionable failure diagnostics instead of silent exit-2 OR silent double-queue-to-pending.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1 (BTS-219):** `cmd_artifact_read --kind spec --feature BTS-N` emits a WARN line on stderr (matching `^WARN: artifact-read:`) when the linear branch fails, identifying one of four failure classes: `auth-missing`, `network-error`, `not-found`, `parse-error`. Exit code preserves existing semantics (2 for not-found-or-recoverable, 3 for substrate problem). Pre-existing `ERROR:` lines from `linear-query.sh` continue to surface.

- [ ] **AC-2 (BTS-219):** When `LINEAR_API_KEY` is unset and the linear branch is taken, the WARN line specifically identifies `auth-missing` and includes the recipe: `Set LINEAR_API_KEY in env or source .env from project root`.

- [ ] **AC-3 (BTS-219):** When the Linear Document does not exist (canonical path: ticket has no parented Document of the requested kind), the WARN line specifically identifies `not-found` and exit code is 2 (existing recoverable semantics — caller's no-document branch should fire).

- [ ] **AC-4 (BTS-227):** drift-watchdog skill (`.claude/skills/drift-watchdog/SKILL.md`) verification block uses `jq <<< "$VERIFY"` (or `printf '%s' "$VERIFY" | jq`) instead of `echo "$VERIFY" | jq`. Reproducer: a `linear-query.sh get-issue <id>` response containing description-field newline escapes round-trips through bash-variable capture + jq label-check WITHOUT triggering macOS bash's `echo`-escape interpretation.

- [ ] **AC-5 (BTS-227 audit):** A grep across `.claude/skills/` for the pattern `echo "\$[A-Z_]+" | jq` finds zero remaining cases where the variable could contain Linear-API JSON with description-rich content. Variables holding short JSON (resolver outputs like `$RESOLUTION`, `$DRIFT`) where descriptions are not present can keep `echo` — the audit is targeted at description-carrying responses.

- [ ] **AC-6 (drift-guard):** A new bats test verifies the `cmd_artifact_read` WARN-on-failure behavior across all four failure classes with stub responses. Plus a separate test verifies the `jq <<< "$VAR"` pattern round-trips description-containing JSON correctly (canned fixture, not live API).

- [ ] **AC-7:** Full bats suite remains green: `bash .ccanvil/scripts/bats-report.sh --parallel` reports `PASS: <count>, FAIL: 0, TOTAL: <count>` with `<count>` ≥ 1715 (current baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Add WARN-on-failure block to `cmd_artifact_read`'s linear branch (mirror of `cmd_artifact_write` per BTS-213). |
| `.claude/skills/drift-watchdog/SKILL.md` | Replace `echo "$VERIFY" \| jq` with `jq <<< "$VERIFY"` in the verification block (line ~116). |
| `.claude/skills/drift-watchdog/SKILL.md` (audit) | Audit + fix any other `echo "$VAR" \| jq` patterns where `$VAR` carries description-rich JSON. |
| `hub/tests/artifact-read-warn.bats` | New bats: AC-1/2/3 — WARN-on-failure across four classes with stubbed responses. |
| `hub/tests/json-pipe-safety.bats` | New bats: AC-4 — round-trip a description-containing JSON fixture through `jq <<< "$VAR"`. |

## Dependencies

- **Requires:** Nothing new — purely substrate-internal + skill-prose changes.
- **Blocked by:** Nothing.

## Out of Scope

- Migrating ALL `echo "$VAR" | jq` patterns across the codebase. Only the description-rich-content cases need fixing for AC-5; the audit may identify additional targets but those are nice-to-have, not blocking.
- Adding similar WARN-on-failure to other live-API substrate primitives (e.g., `linear-query.sh` direct callers, `cmd_idea_count`'s linear branch, etc.). Out of scope; capture as follow-up if friction surfaces.
- Re-framing BTS-227's title to match the actual root cause. The spec body acknowledges the re-framing; the ticket title can stay since the FIX still closes the symptom even if the diagnosis was different.
- A linter/drift-guard test that catches future `echo "$VAR" | jq` patterns at PR time. Out of scope; capture as follow-up if the audit finds many cases worth preventing systemically.

## Implementation Notes

- **Pattern to follow** for AC-1's WARN block: same shape as `cmd_artifact_write` (lines ~4585-4595 of `docs-check.sh`), which already calls the BTS-213 WARN flow on Linear failure. Detection logic for the four failure classes:
  - `auth-missing`: `linear-query.sh` returns "ERROR: LINEAR_API_KEY not set" or similar — grep stderr for the auth marker.
  - `not-found`: `linear-query.sh get-document` returns "Entity not found: Document" — already partially handled (returns 2 today); just add the WARN line.
  - `network-error`: curl/connection failure surfaces as a non-graphql exit; grep for `curl:` or `Connection refused`.
  - `parse-error`: jq fails on the response body — last resort catch-all.

- **AC-4 fix** is one line: change `echo "$VERIFY" | jq -e '.labels | index("drift-watchdog")'` to `jq -e '.labels | index("drift-watchdog")' <<< "$VERIFY"`. Tested in-session via `printf '%s' "$VERIFY" | jq` — works; `<<<` should work identically since here-strings don't interpret escapes.

- **AC-5 audit scope.** Likely targets to inspect (variables that COULD carry description-rich Linear JSON):
  - drift-watchdog: `$VERIFY` (confirmed broken) — primary target.
  - drift-watchdog: `$EXISTING`, `$DUP` — list-issues output, no description field by default; verify by reading the linear-query.sh `cmd_list_issues` body.
  - Other skills with `$()`-captured Linear JSON to be filtered through jq.

- **No new helper function** for the safe-pipe pattern — a one-line `<<<` substitution is direct enough. If the audit finds 5+ occurrences worth abstracting, capture as a separate substrate ticket.

- **Bash 3.2 portability** confirmed: `<<<` here-strings are bash-builtin and work in 3.2+. macOS `/bin/bash` is 3.2; Homebrew bash is 5+. Both honor the here-string.

- **Live-API gate:** AC-1/2/3 can be tested via stubbed responses (matching the pattern in `hub/tests/ssot-linear.bats` that mocks `linear-query.sh`). Live-API validation NOT required — the WARN behavior is local-only stderr emission, no contract risk against Linear's API. AC-4's fix is also testable via canned fixture (no live call needed). The ROOT-CAUSE investigation that produced this spec already validated the bug live.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
