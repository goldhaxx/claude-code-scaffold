# Implementation Plan: Linear Dispatch stateId → state Rename

> Feature: bts-139-linear-state-param-fix
> Work: linear:BTS-139
> Created: 1777064736
> Spec hash: (computed at step-start)
> Based on: docs/spec.md

## Objective

Rename `stateId` → `state` in every resolver emission + skill doc + test assertion so ccanvil's Linear MCP dispatches match the tool's actual schema. No semantic change; pure naming fix.

## Sequence

### Step 1: Add the regression test (RED)
- **Test:** `hub/tests/stateid-rename-regression.bats` — asserts `operations.sh resolve idea.add / ticket.transition <id> <role> / idea.triage / idea.review-icebox` outputs contain NO `stateId` key.
- **Implement:** NEW file. Use `jq -e 'has("stateId") | not'` on `.invocation.params`.
- **Verify:** Tests fail because current emission uses `stateId`.

### Step 2: Rename in operations.sh (partial GREEN)
- **Implement:** `sed -i '' 's/"stateId":/"state":/g' .ccanvil/scripts/operations.sh` (19 occurrences). Audit comments for stale references to `stateId` dispatch — convert narrative references to `state`.
- **Verify:** Regression test passes. Existing `idea-triage-native.bats`/`ticket-transition.bats`/`ideas-to-linear.bats` FAIL because they assert `stateId`.

### Step 3: Cascade test assertion updates (full GREEN)
- **Implement:** update 48 test assertions across the 3 existing test files. Same `sed` pattern on each file.
- **Verify:** Full suite green.

### Step 4: Update skill + command docs
- **Implement:** `.claude/skills/idea/SKILL.md` (15+ refs), `.claude/commands/land.md` (2 refs), `.ccanvil/guide/command-reference.md` (2 refs). Replace `stateId` with `state`; update narrative (e.g., "resolver injects `stateId`" → "resolver injects `state`").
- **Verify:** `grep -rn 'stateId' .claude/ .ccanvil/guide/` returns only comments documenting the migration, if any. Full suite still green.

### Step 5: Dogfood-smoke
- **Implement:** capture a throwaway test idea via `mcp__claude_ai_Linear__save_issue` using the newly-resolved `state: <uuid>` param. Verify it lands in `status: Triage`. Immediately transition to Canceled to clean up.
- **Verify:** If lands in Triage → fix works in production. If lands in Backlog → debug further.

### Step 6: /pr + /review + merge + /land
- **Implement:** run full bats suite, `/review`, `security-audit`, `/pr`. Merge. `/land` self-closes via the NEW correct `state` param — this is the ultimate dogfood-close.
- **Verify:** BTS-139 transitions to Done on self-merge without manual intervention.

## Risks

- **Over-rename.** `sed` could hit comments, docstrings, local-log semantics (JSONL fields). Audit every diff before committing.
- **Bats test isolation.** Bats preprocessor / heredocs that embed `stateId` may need the same sentinel pattern from BTS-127.
- **Dogfood-smoke pollutes workspace.** Mitigate by capturing with title prefix `SMOKE TEST (BTS-139):` and transitioning to Canceled within the same flow.

## Definition of Done

- [ ] All 10 ACs pass
- [ ] Full bats suite green
- [ ] `grep -rn '"stateId"' .ccanvil/scripts/` returns nothing
- [ ] Dogfood-smoke: a test capture lands in Triage
- [ ] `/review` clean
- [ ] PR #55 merged and BTS-139 auto-transitions to Done via renamed `state` dispatch
