# Feature: /idea --parent flag for capture-time parentId

> Feature: bts-162-idea-parent-flag
> Work: linear:BTS-162
> Created: 1777176703
> Status: In Progress

## Summary

The `/idea` skill currently captures issues without a parent link; setting `parentId` on Linear children requires a follow-up `save_issue` round-trip per child. During multi-capture sessions (the BTS-149 dogfood walk surfaced six follow-up tickets in one /permissions-review pass), that's 6 captures + 3 parent-link calls = 9 MCP round-trips. Add a `--parent <work-ref>` flag to `/idea` that stamps parent-id at capture time on both Linear and local providers, eliminating the post-hoc parent-link pass. Part 1 of the BTS-162 two-part proposal; Part 2 (`capture-from-context` shorthand) is deferred.

## Job To Be Done

**When** I'm capturing a child idea that belongs under a known parent issue (umbrella ticket, family pattern),
**I want to** pass `--parent <work-ref>` at capture time so the link is set in the same MCP / log write,
**So that** multi-capture sessions don't pay the per-child round-trip overhead and copy-paste-drift cross-references go away.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** On Linear-routed nodes, `/idea --parent BTS-158 "child idea text"` resolves `idea.add` and dispatches `linear-query.sh save-issue` with `--parent-id BTS-158` appended. The dispatched command string contains `--parent-id 'BTS-158'` (quoted via `@sh`). No second MCP call is made to set parentId.
- [ ] **AC-2:** On local-routed nodes, `/idea --parent idea-7 "child idea text"` calls `docs-check.sh idea-add --parent idea-7` which appends a JSONL entry that includes a `parent_id: "idea-7"` field. Captures without `--parent` produce JSONL entries with no `parent_id` field (omitted, not `null`).
- [ ] **AC-3:** When `--parent` is at the end of args (`/idea "text" --parent BTS-158`), it parses the same as the leading-flag form. Both positions route correctly.
- [ ] **AC-4:** `--parent` value validation rejects whitespace and empty strings: `docs-check.sh idea-add --parent "" "body"` exits 2 with `idea-add: --parent requires a non-empty value`. `--parent "BTS 158"` exits 2 with `idea-add: --parent value 'BTS 158' contains whitespace`.
- [ ] **AC-5:** Pending-log fallback path: when the Linear dispatch fails and the skill calls `docs-check.sh idea-pending-append --op add --parent BTS-158 ...`, the resulting pending entry's `args` object includes `parent_id: "BTS-158"`. `/idea sync` replay re-resolves and re-dispatches with `--parent-id` appended.
- [ ] **AC-6:** Drift-guard: existing `/idea <text>` (no `--parent`) flow is unchanged. JSONL shape on local has no `parent_id` key; Linear dispatch command string contains no `--parent-id` token. Existing tests pass without modification.

## Affected Files

| File | Change |
|------|--------|
| `.claude/skills/idea/SKILL.md` | Modified — add `--parent <ref>` parsing in capture step + dispatch hand-off |
| `.ccanvil/scripts/docs-check.sh` | Modified — extend `cmd_idea_add` and `cmd_idea_pending_append` (op=add) with `--parent` flag |
| `hub/tests/idea-parent-flag.bats` | New — AC-1 through AC-6 tests |

## Dependencies

- **Requires:** `linear-query.sh save-issue --parent-id` (already exists per `linear-query.sh` line 38).
- **Blocked by:** none.

## Out of Scope

- **Part 2: `capture-from-context` shorthand.** Auto-injected boilerplate (active-skill name, session context buffer, family cross-refs) depends on session-context plumbing that doesn't exist yet. Deferred to a follow-up ticket; capture as a new idea after Part 1 ships.
- **Cross-provider parent validation.** The `--parent` value is passed through verbatim. We don't pre-flight that `BTS-158` exists in Linear before dispatch — Linear's API surfaces a hard error if parentId is invalid, which is the same UX as today's manual parent-link flow. Pre-flight existence checks add latency without changing the failure surface.
- **Multi-parent.** `--parent` accepts a single ref. Linear's `parentId` is a single field; if multi-parent (relations) is wanted, that's a different ticket against the relations API.
- **Promote-time parent-setting.** `/idea promote --parent X` is a different surface (transition + parent set in one). Out of scope; capture-time only.

## Implementation Notes

- **Skill prose change.** In `.claude/skills/idea/SKILL.md` capture step, add a flag-parser pass before generating the title: extract `--parent <val>` from the raw input, leaving the rest as the body. Validate non-empty + no-whitespace at the skill layer (cheap). On Linear path, append `--parent-id $(printf '%s' "$parent" | jq -R @sh)` to the eval'd `$cmd`. On local path, pass `--parent "$parent"` through to `docs-check.sh idea-add`.
- **`cmd_idea_add` change.** Add `--parent <id>` to the arg loop; when set, include it in the JSONL via `--arg parent "$parent" '. + {parent_id:$parent}'` style merge. Keep the field omitted when unset (don't emit `null`).
- **`cmd_idea_pending_append` change.** Add `--parent` to the `add` op's flag list; when set, include `parent_id: "$parent"` in the `args` object. The replay path in `/idea sync` reads it back and forwards via `--parent-id`.
- **`linear-query.sh` is unchanged.** It already supports `--parent-id` (BTS-166). The work is in the resolver-consumer layer (skill) and the local script, not the http wrapper.
- **Test fixtures.** Linear-path tests use mocked dispatch (capture the eval'd command string, assert it contains `--parent-id 'BTS-158'`). Local-path tests run `cmd_idea_add` directly against a tmpdir node and assert JSONL shape via `jq`.
- **Validation regex.** Keep validation cheap and provider-agnostic — non-empty + no-whitespace is enough. Don't try to assert TEAM-N format; explicit `linear:` and `local:` prefixes are valid parent values too.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
