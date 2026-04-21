# Feature: cmd_register auto-commits node UUID file

> Feature: register-auto-commit
> Created: 1776711500
> Status: Complete

## Summary

When `ccanvil-sync.sh register` runs in a new downstream node, `persist_node_uuid` creates `.claude/ccanvil.local.json` containing the node's UUID. The file is left untracked, so the node's working tree is dirty and the very next `broadcast` pre-check aborts with "uncommitted changes". This blocks every first registration on a gitignore-respecting node — Claude has to manually `ALLOW_MAIN=1 git add/commit` before proceeding. The fix mirrors the existing `commit_hub_file` pattern with a `commit_node_file` helper, and has `cmd_register` invoke it on `.claude/ccanvil.local.json` after `persist_node_uuid` writes it. This is the first of three features in BTS-74 (sync-determinism-batch).

## Job To Be Done

**When** I run `register` in a fresh downstream node,
**I want** the generated `.claude/ccanvil.local.json` to be auto-committed,
**So that** the next `broadcast` pre-check passes without manual `git add/commit` ceremony.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given a downstream node git repo with no `.claude/ccanvil.local.json`, when `cmd_register` runs, then after completion the file is present, tracked, and committed (no untracked or uncommitted changes for this path).
- [ ] **AC-2:** Given a downstream node where `.claude/ccanvil.local.json` already exists and matches the in-lockfile UUID, when `cmd_register` runs, then no new commit is created (no-op commit semantics).
- [ ] **AC-3:** Given a downstream node where `.claude/ccanvil.local.json` exists but has changed since the last commit, when `cmd_register` runs, then a single commit is created with only `.claude/ccanvil.local.json` staged — unrelated uncommitted changes in the node are NOT picked up (same `--only` discipline as `commit_hub_file`).
- [ ] **AC-4:** Given a downstream node that is NOT a git repo, when `cmd_register` runs, then the command exits 0 without error and without attempting a commit (graceful no-op, parallel to `commit_hub_file`'s git-repo check).
- [ ] **AC-5:** Commit message format: `chore(ccanvil): register node <node_name> [<uuid>]` — mirrors the hub-side registry commit message style.
- [ ] **AC-6:** Error/edge: if the commit attempt itself fails (e.g., pre-commit hook rejects), print a WARNING but exit 0 — mirrors `commit_hub_file`'s failure tolerance so registration is never fully blocked by a local git hook.
- [ ] **AC-7:** Regression: all existing bats tests pass (`bats hub/tests/`).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `commit_node_file` helper near `commit_hub_file`; call it from `cmd_register` after `persist_node_uuid` |
| `hub/tests/register-auto-commit.bats` | New — bats tests for AC-1..AC-6 |

## Dependencies

- **Requires:** existing `commit_hub_file` helper (`.ccanvil/scripts/ccanvil-sync.sh:84`) as the pattern template.
- **Blocked by:** nothing.

## Out of Scope

- Features 2 and 3 of BTS-74 (`take-hub` auto stack-reapply, `relocate` subcommand) — separate specs.
- Auto-committing `.ccanvil/ccanvil.lock` in the node (it's gitignored across all current nodes; committing it would be a policy change).
- Changing `register`'s hub-side behavior — the hub-side registry commit via `commit_hub_file` is already correct.

## Implementation Notes

- **Helper pattern:** copy-paste `commit_hub_file` into `commit_node_file` with argument rename (no hub_path needed — operates on the current node cwd). Keep the same safety checks: git repo existence, unchanged-file short-circuit, untracked-file detection, `--only` staging, failure tolerance.
- **Signature:** `commit_node_file <rel_file> <commit_message>`. Operates on `$(pwd)` as the git repo.
- **Call site:** in `cmd_register` after `persist_node_uuid "$node_uuid"` and before the hub-side `commit_hub_file` call at the end. Message uses `$node_name` and `$node_uuid` already in scope.
- **Test harness:** follow `hub/tests/tech-stack-distribution.bats` pattern (isolated HUB + NODE temp dirs, each initialized as git repo). Invoke `register` from within NODE. Assert via `git -C "$NODE" log` and `git -C "$NODE" status --porcelain`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
