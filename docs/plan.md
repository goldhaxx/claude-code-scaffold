# Implementation Plan: Separate IssueRelation API from IssueUpdate

> Feature: bts-228-linear-issue-relation-api
> Work: linear:BTS-228
> Created: 1777319847
> Spec hash: 29100754
> Based on: docs/spec.md

## Objective

Add `linear-query.sh create-relation` as a clean primitive wrapping `issueRelationCreate`. Fix `save-issue --duplicate-of` to remove the invalid `duplicateOf` field from `IssueUpdateInput` and dispatch a follow-up `issueRelationCreate` after a successful state transition. WARN-on-failure for the relation half preserves backward compat.

## Sequence

### Step 1 (RED): Write the bats drift-guard for AC-1, AC-4, AC-5

- **Test:** Create `hub/tests/issue-relation.bats`. Test blocks:
  - AC-4: invoking `create-relation --type bogus --issue X --related Y` with an unknown type emits `_die 2` + lists valid types.
  - AC-5: empty `--issue` or empty `--related` triggers `_die 2` + usage line.
  - AC-1 happy-path: deferred to live-API smoke during implementation; the bats can stub via `_extract_*` patterns testing the input-validation pre-amble of `cmd_create_relation`.
- **Implement:** New bats file. Test blocks expect helpers that don't exist yet.
- **Files:** `hub/tests/issue-relation.bats` (new).
- **Verify:** `bash .ccanvil/scripts/bats-report.sh -f issue-relation` reports failures (RED — `cmd_create_relation` doesn't exist).

### Step 2 (GREEN): Add `cmd_create_relation` to linear-query.sh

- **Test:** Re-run `bats-report.sh -f issue-relation`.
- **Implement:** Add subcommand near `cmd_save_issue` (or before, since it'll be called from there). Body:
  ```bash
  cmd_create_relation() {
    _require_api_key
    local rel_type="" issue_id="" related_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)    rel_type="$2"; shift 2 ;;
        --issue)   issue_id="$2"; shift 2 ;;
        --related) related_id="$2"; shift 2 ;;
        *) _die 2 "create-relation: unknown flag: $1" ;;
      esac
    done
    case "$rel_type" in
      duplicate|blocks|related) ;;
      "")  _die 2 "create-relation: --type required (duplicate|blocks|related)" ;;
      *)   _die 2 "create-relation: unknown --type '$rel_type' (valid: duplicate|blocks|related)" ;;
    esac
    [[ -z "$issue_id" ]]   && _die 2 "create-relation: --issue required (issue UUID)"
    [[ -z "$related_id" ]] && _die 2 "create-relation: --related required (related issue UUID)"

    local query='mutation IssueRelationCreate($input: IssueRelationCreateInput!) {
      issueRelationCreate(input: $input) {
        success
        issueRelation { id type }
      }
    }'
    local variables
    variables=$(jq -nc \
      --arg type "$rel_type" \
      --arg issueId "$issue_id" \
      --arg relatedIssueId "$related_id" \
      '{input:{type:$type, issueId:$issueId, relatedIssueId:$relatedIssueId}}')

    _post_graphql "$query" "$variables" | jq '.issueRelationCreate.issueRelation | {id, type}'
  }
  ```
  Plus dispatcher case: `create-relation) cmd_create_relation "$@" ;;`.
  Plus help-text update at top of script.
- **Files:** `.ccanvil/scripts/linear-query.sh`.
- **Verify:** AC-4 + AC-5 tests pass (validation paths). AC-1 happy path needs live API.

### Step 3 (RED): Add bats coverage for save-issue's two-step flow

- **Test:** Add a test block to `issue-relation.bats` (or a new file) verifying that `cmd_save_issue` no longer emits `duplicateOf` in IssueUpdateInput. Approach: extract the input-construction logic (the `if [[ -n "$duplicate_of" ]]; then input=...{duplicateOf:$v}...` block) and assert it's absent OR replaced with a relation-dispatch. Static check — grep linear-query.sh for the broken assignment and fail if present.
- **Implement:** Test that fails until the broken line is removed.
- **Files:** `hub/tests/issue-relation.bats`.
- **Verify:** Test fails initially (broken line still in source).

### Step 4 (GREEN): Fix save-issue --duplicate-of two-step flow

- **Test:** Re-run `issue-relation.bats`.
- **Implement:** In `cmd_save_issue`:
  1. **Remove** the line `input=$(printf '%s' "$input" | jq --arg v "$duplicate_of" '. + {duplicateOf:$v}')` (currently around line 535).
  2. **After** the issueUpdate mutation runs successfully (the `else` branch around line ~570), if `$duplicate_of` is non-empty, dispatch the relation:
     ```bash
     # BTS-228: duplicate-of is a separate IssueRelation, NOT a field on
     # IssueUpdateInput. State transition succeeded; now create the relation.
     # WARN-on-failure preserves the state-transition outcome.
     if [[ -n "$duplicate_of" ]]; then
       local issue_uuid
       issue_uuid=$(printf '%s' "$update_response" | jq -r '.issueUpdate.issue.id // empty')
       if [[ -n "$issue_uuid" ]]; then
         if ! cmd_create_relation --type duplicate --issue "$issue_uuid" --related "$duplicate_of" >/dev/null 2>&1; then
           echo "WARN: save-issue: relation-create-failed — type=duplicate from=$id to=$duplicate_of" >&2
           echo "Retry: bash linear-query.sh create-relation --type duplicate --issue $issue_uuid --related $duplicate_of" >&2
         fi
       else
         echo "WARN: save-issue: relation-create-failed — could not resolve issue uuid for relation dispatch" >&2
       fi
     fi
     ```
  3. **Caveat:** `cmd_save_issue`'s update path currently pipes `_post_graphql ... | jq '...'` and returns. The piped jq strips out the issue UUID. Need to capture the raw response into `$update_response` first, THEN extract the UUID for relation dispatch, THEN re-emit the truncated `{id, title}` shape. Re-shape the update path:
     ```bash
     local update_response
     update_response=$(_post_graphql "$query" "$variables")
     # ... relation dispatch above using $update_response ...
     printf '%s' "$update_response" | jq '.issueUpdate.issue | {id: .identifier, title: .title}'
     ```
  4. The IssueUpdate GraphQL query needs to also return `id` (UUID) alongside `identifier` + `title` so the relation dispatch has the UUID. Update the mutation block: `issueUpdate(...) { success issue { id identifier title } }`.
- **Files:** `.ccanvil/scripts/linear-query.sh`.
- **Verify:** Step 3's test passes. AC-2 / AC-3 require live API.

### Step 5 (live-API gate): Smoke test the two-step flow

- **Test:** Per `.claude/rules/tdd.md` live-API gate, run ONE live `save-issue --id <real-ticket> --duplicate-of <other-real-uuid>` against a controlled test ticket BEFORE committing the final state.
- **Implement:** Pick a fresh test scenario. Recipe:
  ```bash
  # Pick an existing test ticket (low-stakes) and a target to merge it onto.
  # Verify: state transitions AND relation appears in Linear UI / via Linear MCP get_issue.
  source .env
  bash .ccanvil/scripts/linear-query.sh save-issue --id BTS-XXX --state <duplicate-state-uuid> --duplicate-of <target-uuid>
  bash .ccanvil/scripts/linear-query.sh get-issue BTS-XXX  # verify state
  # Use Linear MCP get_issue with includeRelations=true to verify the relation landed.
  ```
- **Files:** None (one-shot validation).
- **Verify:** State transitioned + relation visible. If relation didn't land, debug before committing.

### Step 6 (drift-guard): Lock the contract

- **Test:** Add a static assertion to `issue-relation.bats`: linear-query.sh contains `cmd_create_relation` AND does NOT contain the broken `duplicateOf:$v` line in `cmd_save_issue`.
- **Implement:** Static greps; same pattern as the `audit-lock` test in `json-pipe-safety.bats`.
- **Files:** `hub/tests/issue-relation.bats`.
- **Verify:** Test passes; substrate state is locked.

### Step 7 (GATE): Full suite green

- **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel`.
- **Verify:** PASS ≥ 1726 + new tests; FAIL = 0.

### Step 8: Documentation

- **Test:** None.
- **Implement:** Update `.ccanvil/guide/command-reference.md` to:
  1. Document the new `linear-query.sh create-relation` subcommand.
  2. Note the two-step shape for save-issue --duplicate-of (substrate transparently handles both calls; backward compat preserved).
- **Files:** `.ccanvil/guide/command-reference.md`.
- **Verify:** Skim diff; no contradiction.

## Risks

- **`update_response` capture re-shape might break existing save-issue callers** that depend on the exact `{id, title}` output shape. Mitigation: re-emit the same shape from `update_response`, just via a separate jq invocation. The output bytes match the previous `_post_graphql | jq` direct pipe.
- **GraphQL schema field name for relation type** is hypothesized as `type` (string enum). If Linear's schema uses a different name (e.g., `relationType`), the live-API smoke (Step 5) catches it. Mitigation: documented as a live-API contract risk; gate enforces validation before commit.
- **AC-3 (relation-create-failed WARN)** is hard to trigger in tests. The WARN code path is exercised by the live-API gate's failure scenario; bats-encoded only via the static lock that the WARN line exists in source.
- **Backward compat in the live system.** Multiple skills currently dispatch `save-issue --duplicate-of` (most prominently /idea triage merge). After this fix, those calls succeed end-to-end. Verify by post-merge live test against an idea-triage merge scenario. Out of scope to encode in bats since the skill prose isn't directly testable.

## Definition of Done

- [ ] All AC-1 through AC-7 from spec pass.
- [ ] `cmd_create_relation` exists in linear-query.sh + has dispatcher entry + help text.
- [ ] `cmd_save_issue` no longer appends `duplicateOf` to IssueUpdateInput.
- [ ] Live-API smoke test passes.
- [ ] Bats suite green (≥1726 baseline).
- [ ] Code reviewed (run `/review`).
- [ ] BTS-228 transitions to Done at /land time (manual via ccanvil-owned dispatch per BTS-231 substrate gap).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
