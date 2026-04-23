# Feature: Idea Upgrade

> Feature: idea-upgrade
> Created: 1776896787
> Status: Complete

## Summary

Collapse the 4-step downstream node adoption of the Linear idea system into one `docs-check.sh idea-upgrade` subcommand, add a `title-from-body` helper so legacy-file migrations stop requiring hand-written titles, and enforce an archive-only semantic for `.ccanvil/ideas.log` on Linear-configured nodes. Three features, one command surface: without bundling, we'd ship a dangling primitive (`title-from-body` with no caller), an ambiguous dual-store on every Linear node, and a migration path that still requires four tool calls.

## Job To Be Done

**When** a downstream node adopts ccanvil and wants Linear-backed ideas,
**I want to** run one command that configures the node, migrates legacy entries with auto-generated titles, marks the local log archive-only, and commits the result,
**So that** new node adoptions take one step instead of four, and post-migration nodes have one writable source of truth for ideas.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### idea-upgrade command

- [ ] **AC-1:** `docs-check.sh idea-upgrade --provider local [project-dir]` writes `.claude/ccanvil.local.json` with `integrations.routing.idea = "local"`, updates `.gitignore`, commits with message `chore(idea-upgrade): configure local provider`. Exit 0.
- [ ] **AC-2:** `docs-check.sh idea-upgrade --provider linear --team T --project P [project-dir]` writes the Linear routing + `providers.linear.{team, project}` into `ccanvil.local.json`, updates `.gitignore`, commits. Exit 0.
- [ ] **AC-3:** `--create-project` with `--provider linear` emits a stdout JSON intent (`{"tool": "mcp__claude_ai_Linear__save_project", "params": {...}}`) that the invoking skill layer can dispatch. Script itself does not call MCP (operations.sh-style separation). Exit 0.
- [ ] **AC-4:** `--from-legacy` when `docs/ideas.md` is tracked: runs title generation for each entry body, writes JSONL lines to `.ccanvil/ideas.log` with generated titles, `git rm`s `docs/ideas.md`, commits the full change set in one commit.
- [ ] **AC-5:** `--from-legacy` when `docs/ideas.md` is absent: proceeds with config-only upgrade; does not fail. Stdout notes "Nothing to migrate".
- [ ] **AC-6:** `--dry-run` prints the step plan (config changes, files migrated, commit message) to stdout and makes zero mutations.
- [ ] **AC-7:** Idempotent: running `idea-upgrade` a second time on an already-upgraded node exits 0 with stdout `Already upgraded` and makes no commits.
- [ ] **AC-8:** `--provider linear` without `--team` or `--project` exits non-zero with stderr `ERROR: --provider linear requires --team and --project`.

### title-from-body helper

- [ ] **AC-9:** `docs-check.sh title-from-body "<body>"` with body ≤80 chars and single-line: stdout is the body verbatim (short-text fast path). Exit 0.
- [ ] **AC-10:** Body >80 chars or multi-line: stdout is a title ≤80 chars derived from the body. Implementation invokes the local `claude` CLI; if unavailable, falls back to the first 80 chars of the first line (deterministic fallback).
- [ ] **AC-11:** `--title-map <file>` flag (JSON or YAML, body→title): bypass the stochastic path for bodies present in the map. Unknown bodies fall through to AC-9/10 logic.
- [ ] **AC-12:** Empty body: stdout is empty string, exit 0. (Edge case — matches existing `cmd_idea_add` empty-body handling.)

### Archive-only semantic for Linear-configured nodes

- [ ] **AC-13:** `idea-upgrade --provider linear` writes header line `# ARCHIVE: read-only after <ISO-8601 date>` as the first line of `.ccanvil/ideas.log` (prepend; preserves any existing content below).
- [ ] **AC-14:** `cmd_idea_add` detects `routing.idea = "linear"` on the target project; when true, refuses to append to `.ccanvil/ideas.log` and returns non-zero with stderr `ERROR: node is Linear-configured — captures must route via /idea skill`. (Defense-in-depth: /idea skill already branches correctly; this prevents direct script misuse.)
- [ ] **AC-15:** `cmd_idea_list` on a Linear-configured project defaults to querying Linear (via operations.sh resolve). `--include-archive` flag additionally emits historical local log entries, clearly separated under an `ARCHIVE:` header in the output.
- [ ] **AC-16:** The archive header is preserved through re-runs of `idea-upgrade` (idempotent; never duplicated).

### Documentation

- [ ] **AC-17:** `.ccanvil/guide/command-reference.md` documents `idea-upgrade` and `title-from-body` in the `docs-check.sh` command table.
- [ ] **AC-18:** `.ccanvil/guide/ideas-migration.md` is rewritten to describe the one-command upgrade path as the primary flow; the 4-step manual path is retained as "Manual alternative" for operators who need fine-grained control.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `cmd_idea_upgrade`, `cmd_title_from_body`; extend `cmd_idea_add` routing check; extend `cmd_idea_list` with archive surfacing |
| `.ccanvil/guide/command-reference.md` | Modified — document new commands |
| `.ccanvil/guide/ideas-migration.md` | Rewritten — one-command flow is primary |
| `hub/tests/idea-upgrade.bats` | New — 18 AC tests |
| `hub/tests/ideas-to-linear.bats` | Modified — adjust assertions where `/idea list` and `cmd_idea_add` behavior changed |
| `hub/tests/legacy-refs-allowlist.txt` | Modified — new lines from docs-check.sh expansion |

## Dependencies

- **Requires:** `ideas-to-linear` (shipped PR #41) — `cmd_idea_setup`, `cmd_idea_migrate`, operations.sh routing layer.
- **Blocked by:** Nothing.

## Out of Scope

- Workspace-level "Ideas Inbox" initiative for cross-project ideas (deferred).
- Linear status auto-creation (still blocked upstream; MCP lacks `create_issue_status`).
- Retroactively backfilling historical-decision labels in Linear.
- Batch MCP `save_issue` helper (separate determinism candidate — `idea-upgrade` internally dispatches N intents; the user-facing step count is what this feature optimizes).
- `title-from-body` consumed by anything other than `idea-upgrade --from-legacy` (future: `/idea` skill could call it for long captures, but that's a separate change).

## Implementation Notes

- Follow the same shape as `cmd_idea_setup` (docs-check.sh:1407) and `cmd_idea_migrate` (docs-check.sh:1316) — bash function, flag parsing via getopts-style while-loop, exits on first error with clear stderr.
- `--create-project` follows the operations.sh "emit intent, let the caller dispatch" pattern — the script stays MCP-free.
- `title-from-body` invokes `claude` CLI via `command -v claude` guard; degrades to the deterministic first-80-chars fallback if absent. The `claude` CLI is already used by the /spec skill's title derivation.
- Archive header is a single line; use `sed -i '' '1i\# ARCHIVE...\n'` on macOS and `sed -i '1i# ARCHIVE...'` on Linux (existing scripts already handle this portably — mirror their pattern).
- Commit messages from `idea-upgrade` should use `chore(idea-upgrade): ...` form to match existing `chore(stasis-migration)` / `chore(idea-setup)` style.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
