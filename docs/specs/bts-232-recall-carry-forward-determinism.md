# Feature: /recall surfaces carry-forward determinism candidates from prior stasis

> Feature: bts-232-recall-carry-forward-determinism
> Work: linear:BTS-232
> Created: 1777333997
> Status: Complete

## Summary

`/recall` already surfaces the prior stasis's `## Determinism Review` candidates under "Outstanding determinism improvements." It does NOT verify that each candidate was actually dual-captured to Linear. This means determinism candidates can silently evaporate across context resets when `/stasis`'s dual-capture step fails (or — as session 7 just demonstrated — when the candidate's bullet shape doesn't match the slug-derivation protocol and never reaches the dual-capture loop).

This ship adds a read-side check: after parsing the prior stasis's determinism review, query the current Linear idea listing for matching `Determinism: <slug>` titles. Any candidate with NO matching idea entry surfaces as `**Carry-forward determinism candidate:**` — flagging that the dual-capture didn't land and the operator should manually create the ticket.

This closes the BTS-205 read-side gap. BTS-205 fixed write-side resilience (emergency dead-letter, local-routed mechanism dispatch); BTS-232 adds the read-side detector that surfaces any historical drops.

## Job To Be Done

**When** I run `/recall` to orient on a new session and the prior stasis listed determinism candidates,
**I want to** see which candidates have NOT been captured as Linear ideas,
**So that** I can manually create the missing tickets and no determinism candidate evaporates silently.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** New substrate primitive `docs-check.sh stasis-carry-forward --project-dir .` reads the active stasis (via `artifact-read`), parses the `## Determinism Review` section, extracts each candidate's slug, queries the current Linear idea listing, and emits JSON: `{candidates: [{slug, has_idea: bool, idea_id: string|null}], count_total: N, count_carry_forward: M}`.

- [ ] **AC-2:** Slug extraction tolerates two bullet shapes: (a) `**bolded operation name**: ...` (per BTS-115/205 protocol) → slug is the bolded text; (b) any other shape (`\`code\` text...`, plain text, etc.) → slug is the leading non-whitespace text up to the first `:` or first 60 chars, whichever is shorter. Both shapes are queried via case-insensitive substring match against `Determinism: <slug>` idea titles.

- [ ] **AC-3:** `/recall` skill prose calls `stasis-carry-forward` after step 6, parses the JSON, and renders a `**Carry-forward determinism candidates:**` section in the briefing IFF `count_carry_forward > 0`. When `count_carry_forward == 0`, OMIT the section entirely (no zero-noise). Output format: one bullet per carried candidate as `- <slug>` (not `- BTS-X — <slug>` since these candidates have NO ticket — that's the point).

- [ ] **AC-4:** Empty-state — when the prior stasis's determinism review section reads `No candidates this session.`, `stasis-carry-forward` emits `{candidates: [], count_total: 0, count_carry_forward: 0}` without error. `/recall` surfaces nothing.

- [ ] **AC-5:** Edge — when no prior stasis exists (first-recall node), `stasis-carry-forward` exits 0 with `{candidates: [], count_total: 0, count_carry_forward: 0}` and a `note: "no prior stasis"` field. `/recall` does not error and surfaces nothing.

- [ ] **AC-6:** New bats `hub/tests/stasis-carry-forward.bats` covers AC-1 through AC-5: stasis with all candidates matched (empty carry-forward), all unmatched (full carry-forward), mixed, empty-state literal, no prior stasis. Uses fixtures + a `LINEAR_QUERY_OVERRIDE` stub to avoid live API.

- [ ] **AC-7:** Full bats suite remains green at ≥ 1787 (post-BTS-205 baseline). Existing `/recall` skill drift-guard tests continue to pass — the new section is additive.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | New `cmd_stasis_carry_forward` function + dispatch entry. Calls `cmd_artifact_read` for stasis content + `linear-query.sh list-issues` (or local `cmd_idea_list`) for idea titles. |
| `.claude/skills/recall/SKILL.md` | New step (between current step 6 and step 6a) calling `stasis-carry-forward`; new `**Carry-forward determinism candidates:**` section in the Briefing block. |
| `hub/tests/stasis-carry-forward.bats` | New bats covering AC-1–AC-5. Uses fixtures + `LINEAR_QUERY_OVERRIDE` stub. |

## Dependencies

- **Requires:** BTS-204 (`artifact-read` substrate); BTS-205 (dual-capture write-side closure — establishes the slug protocol this read-side check verifies); BTS-203 (`LINEAR_QUERY_OVERRIDE` env-var pattern). All shipped.
- **Blocked by:** Nothing.

## Out of Scope

- **Auto-creating missing tickets.** This ship surfaces gaps; operator decides whether to manually capture each. Auto-create is a separate ship (would need dedup logic + decision on default priority).
- **Fixing stasis composition to always emit `**bolded**` slugs.** Session 7's bullets used `` `code` `` shapes — that's a separate `/stasis` skill prose update. AC-2's tolerance handles it gracefully without requiring the fix.
- **Surfacing carry-forward across multiple prior sessions.** Only the most recent stasis is checked. Multi-session walk-back is a follow-up if friction surfaces.
- **Running `stasis-carry-forward` on a non-stasis-bearing node.** When `artifact-read --kind stasis` returns empty (no active stasis), the primitive exits 0 with empty candidates and a note — same as first-recall.

## Implementation Notes

- **Substrate boundary:** the parsing logic (extract `## Determinism Review` section, extract candidate slugs) lives in `cmd_stasis_carry_forward`, NOT in skill prose. Skill prose only consumes the JSON envelope. This follows deterministic-first.
- **Slug extraction is line-based parsing, not regex magic.** Read the section line-by-line, recognize bullet starts (`* ` or `- `), then dispatch on the first non-whitespace char of the bullet body: `*` → bolded-shape; `\`` → backtick-shape; otherwise plain. Case-insensitive substring match is the dedup key against idea titles — robust to whitespace/punctuation drift.
- **Linear vs local idea listing:** route through `operations.sh resolve idea.list` then `eval` the resolved command, same pattern as `/idea list` skill prose. Both http and bash mechanisms return the same `[{id, title, status}, ...]` shape.
- **Test fixture pattern (AC-6):** create a temp project-dir with `docs/stasis.md` containing canned `## Determinism Review` sections + a `LINEAR_QUERY_OVERRIDE` stub script that emits canned issue listings. Same shape as `hub/tests/evidence-scan-description-fetch.bats` (BTS-203).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
