# Feature: Phase 2 Linear API substrate migration — /idea capture, list, triage

> Feature: bts-166-linear-substrate-phase-2
> Work: linear:BTS-166
> Created: 1777158862
> Status: Complete

## Summary

Close the BTS-164 substrate seam. Today `idea.add`, `idea.list`, `idea.triage`, and `idea.review-icebox` resolver verbs still emit `mechanism: mcp`, so `/idea` capture/list/triage-walkthrough only work from a Claude session — bash callers can't capture or list ideas. Migrate those four verbs to `mechanism: http` so they ride the same `linear-query.sh` substrate as `idea.count` and `ticket.transition`. The migration requires extending `linear-query.sh save-issue` to accept dynamic content (title, description) without shell-quoting friction — solved via Option 2 from the ticket: a `--input-json -` stdin-JSON merge flag + name-based create flags (`--team`, `--project`, `--labels`).

## Job To Be Done

**When** I (or a script) want to capture, list, or triage an idea on a Linear-routed project,
**I want to** dispatch through the unified http substrate,
**So that** scripts and skills share one provider-aware path and the whole `/idea` flow is reachable without an MCP indirection.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `linear-query.sh save-issue --input-json -` reads a JSON object from stdin and merges it into the IssueCreateInput / IssueUpdateInput before dispatch. CLI flags continue to override stdin fields when both are present.
- [ ] **AC-2:** `linear-query.sh save-issue` accepts `--team NAME`, `--project NAME`, `--labels NAME[,NAME...]` and resolves NAME→ID internally before posting. `--team-id` / `--project-id` / `--label-ids` continue to work and take precedence when both forms are passed.
- [ ] **AC-3:** Title/description with embedded newlines, double-quotes, single-quotes, backticks, `$VAR`, and `$(cmd)` are preserved verbatim through the stdin-JSON path. Verified by piping a fixture body containing all five and reading it back via `linear-query.sh get-issue`.
- [ ] **AC-4:** `operations.sh resolve idea.add` on a linear-routed project emits `mechanism: "http"` with a `linear-query.sh save-issue` command carrying `--team`, `--project`, `--labels`, and `--state` (when `state_ids.triage` is configured). The command is consumer-completable via stdin-JSON for `--title` and `--description`.
- [ ] **AC-5:** `operations.sh resolve idea.list` on a linear-routed project emits `mechanism: "http"` with a `linear-query.sh list-issues` command (`--project`, `--team`, `--label`).
- [ ] **AC-6:** `operations.sh resolve idea.triage` on a linear-routed project emits `mechanism: "http"` with a `linear-query.sh list-issues` command including `--state triage` (or the configured triage state ID, name-resolved by `list-issues`).
- [ ] **AC-7:** `operations.sh resolve idea.review-icebox` on a linear-routed project emits `mechanism: "http"` with `--state icebox`.
- [ ] **AC-8:** Local-routed projects continue to receive `mechanism: "bash"` for all four verbs (existing behavior preserved; no regression in `operations.bats`).
- [ ] **AC-9:** `/idea` skill `SKILL.md` updates: capture step uses `eval "$cmd"` with stdin-JSON pipe; list and triage steps use plain `eval "$cmd"`. No MCP tool calls remain in the linear path.
- [ ] **AC-10:** `cmd_idea_sync` docstring and the skill's sync replay enumerate `add` as a supported op alongside the existing `promote`/`defer`/`dismiss`/`merge`/`ticket.transition`. Replay of an `add` entry succeeds idempotently.
- [ ] **AC-11 (error):** When `LINEAR_API_KEY` is unset and `.env` is absent, the wrapper exits non-zero with a clear error referencing the env var (existing BTS-167 contract preserved).
- [ ] **AC-12 (edge):** Description containing a 6-byte UTF-8 sequence (emoji) and embedded markdown fence triple-backticks round-trips intact through the stdin-JSON path.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/linear-query.sh` | Modified — add `--input-json` flag and name-based create flags to `cmd_save_issue` |
| `.ccanvil/scripts/operations.sh` | Modified — migrate `idea.add`, `idea.list`, `idea.triage`, `idea.review-icebox` to `mechanism: http` |
| `.ccanvil/scripts/docs-check.sh` | Modified — extend `cmd_idea_sync` docstring to document `add` op replay |
| `.claude/skills/idea/SKILL.md` | Modified — rewrite Steps 3a (capture), List, and Triage to use http path |
| `hub/tests/linear-query.bats` | Modified — add `--input-json -` and name-based-create test cases |
| `hub/tests/operations-resolve-http.bats` | Modified — add idea.{add,list,triage,review-icebox} http-branch tests |
| `hub/tests/idea-triage-native.bats` | Modified if needed — verify triage walkthrough still passes under http resolver |

## Dependencies

- **Requires:** BTS-164 substrate (resolver `mechanism: http` + `linear-query.sh`) and BTS-167 (auto-source `.env` for `LINEAR_API_KEY`). Both shipped 2026-04-25.
- **Blocked by:** none.

## Out of Scope

- `backlog.list` semantic divergence (local = specs/, linear = backlog-state issues). Tracked as a separate concern; ticket explicitly defers.
- Provider-onboarding workflow (BTS-165, iceboxed).
- Refactoring `cmd_save_issue`'s flag list beyond the additive changes (`--input-json` + name-based variants).

## Implementation Notes

- **Shell-quoting decision:** Option 2 from the ticket — `--input-json -` reads a JSON object from stdin and is merged into the input via `jq '. + $stdin'`. The skill builds the JSON via `jq -n --arg title ... --arg description ...` (jq handles all string escaping deterministically). No `printf %q` rabbit hole; no env-var expansion surface.
- **Name → ID resolution in `save-issue`:** when `--team`/`--project`/`--labels` are passed without their `-id` counterparts, do a one-shot lookup at the top of `cmd_save_issue` via `cmd_list_teams` / `cmd_list_projects` / `cmd_list_labels` (already exist, lines 249-301). One extra GraphQL call per create — acceptable; mirrors `list-issues`'s name-filtering ergonomics.
- **Resolver shape:** follow the `idea.count` pattern at `operations.sh:527-552` for all four migrated verbs (jq builds the http command with `@sh`-quoted config values from the provider config). Conditional `--state $STATE` injection when `state_ids.<role>` is configured, mirroring the existing MCP shape for triage/icebox.
- **Skill prose pattern (capture):**
  ```bash
  RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .)
  cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
  jq -n --arg title "$TITLE" --arg description "$BODY" '{title:$title, description:$description}' \
    | eval "$cmd --input-json -"
  ```
- **Sync replay (add):** the `cmd_idea_sync` script already exposes the queue; the skill's replay loop (Step in /idea sync) needs an `add` branch that re-resolves and dispatches via the new http path. Idempotency at Linear's end is partial (creates aren't deduped server-side); the skill should `ticket.find-by-title` before re-creating to avoid dup captures from a queued log replay. Out of scope to implement here if a separate `ticket.find-by-title` shim isn't already in place — flag at plan time.
- **Test infra:** existing `operations-resolve-http.bats` setup helpers (`_with_linear_routing`) cover the resolver branch tests. `linear-query.bats` will need a stdin-JSON fixture pattern; reuse `bash -c "echo '$json' | linear-query.sh save-issue --input-json -"` only for ASCII fixtures (BTS-155 lesson — single quotes in `bash -c` get re-parsed; use heredoc tmpfile + `<<'JSON'` for any fixture containing single-quotes or shell metas).
- **Linear WAF (BTS-167 memory):** description prose is still WAF-filtered server-side for shell-injection patterns. Stdin-JSON doesn't bypass that — the wrapper-side test fixtures should avoid raw `;rm -rf /`-shaped strings to keep CI green.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
