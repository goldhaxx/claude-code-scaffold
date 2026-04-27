# Feature: Separate IssueRelation API from IssueUpdate in linear-query.sh

> Feature: bts-228-linear-issue-relation-api
> Work: linear:BTS-228
> Created: 1777319847
> Status: Draft

## Summary

`linear-query.sh save-issue --duplicate-of <uuid>` currently appends `duplicateOf` to the `IssueUpdateInput` GraphQL payload. Linear's API rejects this field because duplicate-of is NOT a field on `IssueUpdateInput` — it's a separate `IssueRelation` (created via `issueRelationCreate` mutation with `type: "duplicate"`). Result: every `/idea triage` merge dispatch silently loses the duplicate-link relationship; the state transition lands but the canonical-parent link is dropped, leaving Duplicate-marked tickets detached in Linear's UI.

This ship adds a new `linear-query.sh create-relation` subcommand wrapping `issueRelationCreate` (the clean primitive), and fixes `save-issue --duplicate-of` to internally:

1. Strip `duplicateOf` from the `IssueUpdateInput` payload (the source of the GraphQL rejection).
2. After successful `issueUpdate`, call the new `create-relation` path with `type=duplicate`.
3. On relation failure, emit a structured WARN (BTS-219 pattern) without failing the overall command — the state transition succeeded, the relation is recoverable.

The `/idea triage` skill prose stays unchanged (callers still pass `save-issue --duplicate-of`), so this is backward-compatible. Operators can also call `create-relation` directly for non-duplicate relation types (`blocks`, `related`).

## Job To Be Done

**When** I run `/idea triage` and merge a duplicate ticket onto its canonical parent,
**I want to** have BOTH the state transition (Duplicate) AND the duplicate-of relation appear in Linear, atomically from my perspective,
**So that** Linear's UI rollups, cycle reports, and parent-issue traversals see the correct relationship and Duplicate-marked tickets aren't orphaned in cycle metrics.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `linear-query.sh create-relation --type duplicate --issue <a-uuid> --related <b-uuid>` invokes the `issueRelationCreate` GraphQL mutation and returns `{id, type}` on success. Supports relation types: `duplicate`, `blocks`, `related`.

- [ ] **AC-2:** `linear-query.sh save-issue --id <a> --state <state-uuid> --duplicate-of <b-uuid>` succeeds end-to-end against the live Linear API: the issue transitions to the target state AND the duplicate-of relation is created. Output shape preserved (`{id, title}`).

- [ ] **AC-3:** When `save-issue --duplicate-of` succeeds at the state transition but the relation creation fails (network glitch, permission issue, etc.), the substrate emits a `WARN: save-issue: relation-create-failed — ...` line on stderr with a copy-pasteable retry recipe (`bash linear-query.sh create-relation --type duplicate --issue <a> --related <b>`). Exit code stays 0 (state transition succeeded).

- [ ] **AC-4:** `create-relation` rejects unknown `--type` values with `_die 2` and a message listing valid types (`duplicate`, `blocks`, `related`).

- [ ] **AC-5:** `create-relation` rejects empty `--issue` or `--related` UUIDs with `_die 2` and a usage line.

- [ ] **AC-6:** A new bats test `hub/tests/issue-relation.bats` covers AC-1, AC-4, AC-5 via direct invocation (mocking the GraphQL layer or running against fixtures — not live API). AC-2 and AC-3 are validated via a lightweight live-API smoke check during implementation (per the live-API gate from `.claude/rules/tdd.md`) — not bats-encoded due to live-API dependency.

- [ ] **AC-7:** Full bats suite remains green: `bash .ccanvil/scripts/bats-report.sh --parallel` reports `PASS: <count>, FAIL: 0, TOTAL: <count>` with `<count>` ≥ 1726 (current baseline).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/linear-query.sh` | Add `cmd_create_relation` (new subcommand). Strip `duplicateOf` from `IssueUpdateInput` in `cmd_save_issue`. Add post-update relation dispatch when `--duplicate-of` was supplied. WARN-on-failure for the relation half. |
| `hub/tests/issue-relation.bats` | New bats: AC-1 (happy path against fixture / mocked GraphQL), AC-4/5 (input validation). |
| `.ccanvil/guide/command-reference.md` | Document the new `create-relation` subcommand + the two-step shape (state transition + relation creation are now separate Linear API mutations). |

## Dependencies

- **Requires:** Nothing — purely substrate-internal change to `linear-query.sh`.
- **Blocked by:** Nothing.

## Out of Scope

- Migrating other Linear-side relation types (`blocks`, `related`) into the substrate beyond the `create-relation` primitive itself. This spec adds the primitive; specific consumers (e.g. /idea-triage merge for blocking-ticket flows) can ramp later as friction surfaces.
- Updating `/idea triage` skill prose. The skill's existing `save-issue --duplicate-of` call now works end-to-end thanks to the substrate fix. Prose updates would only be needed if we removed `--duplicate-of` from save-issue (which we're NOT doing — backward compat preserved).
- Cleaning up the orphaned duplicate-relations from prior failed merges (BTS-220 → BTS-191, BTS-221 → BTS-192, etc., per BTS-227 cleanup). Manual one-shot operator step or a separate `/idea reconcile-duplicates` follow-up ticket.
- Atomicity. The substrate fires two sequential GraphQL mutations (issueUpdate, then issueRelationCreate). If the second fails, the first is NOT rolled back. The WARN + retry recipe is the recovery path. True atomic semantics would require Linear to expose a combined mutation, which it doesn't.

## Implementation Notes

- **`create-relation` arg shape:** `--type <duplicate|blocks|related> --issue <issue-uuid> --related <related-uuid>`. Output: `{id, type}` on success. Error class: `_die 2` for input validation, `_die 3` for GraphQL errors (per existing linear-query.sh convention).

- **GraphQL mutation reference:**
  ```graphql
  mutation IssueRelationCreate($input: IssueRelationCreateInput!) {
    issueRelationCreate(input: $input) {
      success
      issueRelation { id type }
    }
  }
  ```
  Where `$input = {issueId: <a>, relatedIssueId: <b>, type: "duplicate"}`. The `type` field is a string enum; Linear accepts `"duplicate"`, `"blocks"`, `"related"`.

- **`save-issue --duplicate-of` two-step flow:**
  1. Existing arg-loop captures `--duplicate-of <uuid>` into `$duplicate_of`.
  2. **REMOVE** the `input=$(... '. + {duplicateOf:$v}')` line that appends to IssueUpdateInput. (Substrate bug — line ~536 of current linear-query.sh.)
  3. Run `issueUpdate` mutation as before, with the WORKING input shape.
  4. After successful update, if `$duplicate_of` is non-empty, internally call `cmd_create_relation --type duplicate --issue "$id" --related "$duplicate_of"`. The `$id` here is the issue's UUID; verify that's what's passed (vs the BTS-N identifier — Linear's relation API needs UUIDs, while the BTS-N form might be acceptable for issue lookup but not for relation creation).
  5. On relation failure, emit `WARN: save-issue: relation-create-failed — type=duplicate from=$id to=$duplicate_of` and `Retry: bash linear-query.sh create-relation --type duplicate --issue $id --related $duplicate_of`.
  6. Return the existing `{id, title}` output regardless of relation success.

- **Live-API gate (per `.claude/rules/tdd.md`):** AC-2 and AC-3 explicitly call out live-API contract risk. Run ONE live `save-issue --id BTS-XXX --duplicate-of <uuid>` call against a real test ticket BEFORE committing to verify the two-step flow lands cleanly. Stub-only tests would re-introduce the BTS-115 / BTS-170 contract-bug class.

- **Symmetry with BTS-219:** The WARN emission for relation-create-failed reuses the BTS-219 WARN format (`WARN: <subcmd>: <class> — <context>` + `Retry: <recipe>`). Future consolidation into a shared `_warn_with_retry` helper is a nice-to-have but not required here.

- **Backward compat verification:** existing /idea triage skill prose calls `eval "$cmd --duplicate-of <target>"` after resolving `ticket.transition <id> duplicate`. After this fix, the same call:
  1. Sends valid IssueUpdateInput (no duplicateOf field) → state transition succeeds.
  2. Internally fires issueRelationCreate → relation is created.
  3. Output `{id, title}` shape matches existing expectations.
  No skill-prose change needed.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
