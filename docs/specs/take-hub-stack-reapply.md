# Feature: pull-apply take-hub auto-reinvokes stack-apply

> Feature: take-hub-stack-reapply
> Created: 1776712000
> Status: Complete

## Summary

When `ccanvil-sync.sh pull-apply <file> take-hub` runs on `.claude/settings.json`, hub's version replaces the node's — wiping any stack-specific hook entries (e.g., fastapi-sqlite's `protect-db.sh` PreToolUse hook). Hub settings intentionally exclude stack hooks because stacks are node-scoped. Currently the user (or Claude) must manually re-run `ccanvil-sync.sh stack-apply <stack-id>` for every active stack on the node to restore those entries. The fix: after a `take-hub` on `.claude/settings.json`, `cmd_pull_apply` inspects `.claude/ccanvil.json.stacks[]` and automatically invokes `cmd_stack_apply` for each active stack. This is Feature 2 of 3 in BTS-74 (sync-determinism-batch).

## Job To Be Done

**When** `pull-apply take-hub` targets `.claude/settings.json` on a node with active stacks,
**I want** the stack hook entries to be re-merged into settings.json automatically,
**So that** the stack's guardrails continue to fire without manual `stack-apply` ceremony.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given a node with `.claude/ccanvil.json.stacks = ["fastapi-sqlite"]` and a conflict on `.claude/settings.json` whose hub version lacks `protect-db.sh` hooks, when `pull-apply .claude/settings.json take-hub` runs, then after completion `.claude/settings.json` contains the stack's hook entries (as produced by `stack-apply fastapi-sqlite`).
- [ ] **AC-2:** Given a node with no active stacks (`.claude/ccanvil.json.stacks` missing or `[]`), when `pull-apply .claude/settings.json take-hub` runs, then no stack-apply invocation occurs and behavior is identical to pre-fix.
- [ ] **AC-3:** Given a node with active stacks, when `pull-apply` runs on any file OTHER than `.claude/settings.json` with action `take-hub` (e.g., `.claude/rules/tdd.md`), then no stack-apply invocation occurs — the auto-reapply is scoped to the settings.json target only.
- [ ] **AC-4:** Given a node with two active stacks `["fastapi-sqlite", "fake-stack"]` where `fake-stack` does not exist in `hub/stacks/`, when `pull-apply .claude/settings.json take-hub` runs, then `fastapi-sqlite` re-applies successfully and a WARNING is printed for `fake-stack`, but the overall command exits 0 (graceful partial).
- [ ] **AC-5:** Error/edge: when `.claude/ccanvil.json` is missing entirely, `pull-apply .claude/settings.json take-hub` exits 0 without attempting stack-apply (mirrors AC-2).
- [ ] **AC-6:** Output: after a successful auto-reapply, a human-readable line is printed, e.g. `REAPPLIED STACK: fastapi-sqlite (settings.json was overwritten)`.
- [ ] **AC-7:** Regression: all existing bats tests pass.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — in `cmd_pull_apply` `take-hub` branch, after lockfile update, detect settings.json target and iterate stacks |
| `hub/tests/take-hub-stack-reapply.bats` | New — bats tests for AC-1..AC-6 |

## Dependencies

- **Requires:** existing `cmd_stack_apply` (`.ccanvil/scripts/ccanvil-sync.sh:2357`) and `.claude/ccanvil.json.stacks` convention.
- **Blocked by:** nothing. BTS-74 Feature 1 (register-auto-commit) is already merged; this feature is independent.

## Out of Scope

- Features 1 and 3 of BTS-74 (register auto-commit already merged; relocate subcommand is a separate spec).
- Triggering auto-reapply from actions other than `take-hub` — `accept-new`, `section-merge`, `adopt-conflict` on settings.json are unusual and left manual.
- Auto-reapply for files other than settings.json — current stacks only affect settings.json. Future stacks that touch other files will extend this guard.
- Hub-side detection of which files would benefit from reapply — the node side is authoritative for active stacks.

## Implementation Notes

- **Call site:** in `cmd_pull_apply`'s `take-hub` case (`.ccanvil/scripts/ccanvil-sync.sh:1398-1410`), after the `safe_lock_mv` for the lockfile update and before the `echo "APPLIED"`. Guard on `[[ "$file" == ".claude/settings.json" ]]`.
- **Stacks lookup:** `.claude/ccanvil.json` may not exist; use `jq -r '.stacks[]? // empty' .claude/ccanvil.json 2>/dev/null || true` to produce an empty stream on missing file or missing field.
- **Re-apply invocation:** call `cmd_stack_apply "$stack_id"` for each stack id in the list. `cmd_stack_apply` already handles missing stacks via `die`, so wrap in a subshell or error-tolerant block to keep iteration going: `(cmd_stack_apply "$sid") || echo "WARNING: stack-apply $sid failed" >&2`.
- **Pattern to follow:** same iterate-and-continue shape as `cmd_broadcast`'s node loop. Keep the auto-reapply block under ~15 lines.
- **Test harness:** follow `hub/tests/tech-stack-distribution.bats` setup (real `fastapi-sqlite` stack copied into temp HUB). Seed `.claude/ccanvil.json.stacks` directly with `jq` in the test.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
