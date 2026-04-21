# Feature: pull-plan stack-origin classification

> Feature: pull-plan-stack-origin
> Created: 1776708365
> Status: Complete

## Summary

`cmd_pull_plan` in `.ccanvil/scripts/ccanvil-sync.sh` classifies a tracked file as "removed from hub" when the file does not exist at `$hub_source/$file` — regardless of the file's `origin`. Files with `origin: stack:<id>` live at `hub/stacks/<id>/<source-path>` (per the stack manifest), not at the hub root, so they wrongly appear removed on every broadcast. This makes stack-origin conflicts sticky: `keep-local` does not clear them, and the user has to mark the file `node-only` (a lie) to silence the noise. This fix teaches `pull-plan` to leave stack-origin files alone — they are owned by the `stack-apply` flow, not the broadcast flow.

## Job To Be Done

**When** broadcast runs `pull-plan` on a node that has stack-origin files,
**I want** those files to be ignored by the removed-from-hub check,
**So that** they are not perpetually flagged as conflicts and I do not have to misclassify them as `node-only`.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given a lockfile entry with `origin: "stack:fastapi-sqlite"` and the file absent from the hub root, when `cmd_pull_plan` runs, then the plan contains no entry for that file (neither `removed` nor any other action).
- [ ] **AC-2:** Given a lockfile entry with `origin: "hub"` and the file absent from the hub root, when `cmd_pull_plan` runs, then the plan contains an entry with `action: "removed"` for that file (existing behavior preserved).
- [ ] **AC-3:** Given a lockfile entry with `origin: "stack:fastapi-sqlite"` where the file exists on disk and the stack source exists, when `cmd_pull_plan` runs, then the plan does not include the file under any action — pull-plan is not responsible for reconciling stack files.
- [ ] **AC-4:** Given a lockfile entry with `origin: "local"`, when `cmd_pull_plan` runs, then the file is skipped (existing `status == "local-only"` handling preserved).
- [ ] **AC-5:** Error/edge: Given a lockfile entry with a malformed origin like `"stack:"` (empty stack id), when `cmd_pull_plan` runs, then the entry is skipped from the removed-from-hub check (treated as non-hub origin, same as valid `stack:<id>`).
- [ ] **AC-6:** Regression: The existing `broadcast` flow on taxes (with `protect-db.sh` tracked as `origin: stack:fastapi-sqlite`) runs `pull-plan` clean — zero conflicts, zero removed entries for stack files.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add non-hub origin short-circuit in `cmd_pull_plan` loop |
| `hub/tests/pull-plan-stack-origin.bats` | New — bats tests for AC-1..AC-5 |

## Dependencies

- **Requires:** existing `stack-apply` and lockfile `origin: stack:<id>` semantics (already present — `.ccanvil/scripts/ccanvil-sync.sh:2384`).
- **Blocked by:** nothing.

## Out of Scope

- Reconciling stack-origin files against `hub/stacks/<id>/<source>/` (detecting file removed from stack). That is a separate concern for `stack-apply` or a future `stack-check` command.
- Changing lockfile origin format or migrating existing entries.
- Automated revert of the taxes `node-only` workaround for `protect-db.sh`. That is a manual follow-up documented in the BTS-73 ticket.

## Implementation Notes

- **Fix shape (Option B from ticket):** In `cmd_pull_plan` (`.ccanvil/scripts/ccanvil-sync.sh:1181`), after reading `origin` (line 1192), short-circuit with `continue` when `origin != "hub"`. This covers `stack:*` and any future non-hub origins. The existing `status == "local-only"` guard already handles `origin: "local"`; this change makes the logic explicit instead of status-dependent.
- **Why Option B over A:** Resolving stack-origin against `hub/stacks/<id>/<source>/` requires looking up the manifest per file, which duplicates `stack-apply` logic and puts `pull-plan` in the stack-reconciliation business. The deterministic-first principle says keep each script focused. Broadcast handles hub-rooted files; stack-apply handles stack files.
- **Pattern to follow:** The existing `is_node_only` guard (line 1197) and `local-only` skip (line 1202) — same shape: check a condition, `continue` to the next file.
- **Test harness:** follow `hub/tests/tech-stack-distribution.bats` setup pattern (isolated temp HUB + NODE dirs, copy real script, seed lockfile directly with `jq`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
