# Feature: ideas-to-linear — Linear-native idea capture + pre-activate push-guard

> Feature: ideas-to-linear
> Created: 1776826648
> Status: In Progress

## Summary

Migrate `/idea` capture from tracked markdown (`docs/ideas.md`) to a pluggable provider system, eliminating the `ALLOW_MAIN=1` direct-to-main commits that have been the dominant source of local/origin `main` divergence across sessions. Adds custom statuses `Idea` and `Icebox` to the Blocktech Solutions team and rewires `/idea add|list|triage` to route through `operations.sh`: projects with Linear configured go to Linear Triage via MCP; other projects write to a gitignored `.ccanvil/ideas.log`. Adds an offline-safe pending log for Linear failures and a migration tool. Bundles a pre-activate push-guard in `docs-check.sh activate` to halt any remaining local-ahead-of-origin states at activation time. Works for the hub and every downstream node, each configured per-node via `.claude/ccanvil.local.json`.

## Job To Be Done

**When** I'm mid-feature and a stray thought or follow-up deserves to be captured,
**I want to** record it from any machine or surface without committing to main, without needing a feature branch, and without losing it if the network is down,
**So that** ideas become cross-machine, cross-project, and lifecycle-aware without paying a git-divergence tax every time a PR squash-merges.

## Acceptance Criteria

### Linear workspace setup

- [ ] **AC-1:** Custom statuses `Idea` and `Icebox` exist on Blocktech Solutions team, both in the `backlog` category. Verified by `mcp__claude_ai_Linear__list_issue_statuses` returning both names.
- [ ] **AC-2:** Workspace-level label `idea` exists, color `#F2C94C`, description `"Untriaged idea captured via /idea"`. Verified by `mcp__claude_ai_Linear__list_issue_labels` search.
- [ ] **AC-3:** Hub's `.claude/ccanvil.json` ships defaults: `integrations.routing.idea = "linear"` and `integrations.providers.linear = {mechanism: "mcp", idea_label: "idea", idea_status: "Idea", icebox_status: "Icebox"}`. Node-specific fields (`project`, `team`) live in each node's `.claude/ccanvil.local.json` (hub ≠ ccanvil node; the hub sets its own via `ccanvil.local.json` just like every other downstream).

### /idea add (capture)

- [ ] **AC-4:** `/idea <text>` generates a concise summary title (≤80 chars, intent-preserving) from the raw text via Claude, then creates a Linear issue with title=summary, description=original text verbatim, project=configured project, label=configured idea label, status=configured idea status.
- [ ] **AC-5:** Capture succeeds without requiring a clean git worktree, without a branch, and without any commit to any branch.
- [ ] **AC-6:** Post-capture output echoes the new Linear issue ID (e.g., `Captured: BTS-123 — <title>`), then returns the session to whatever was in progress.

### /idea list + /idea triage

- [ ] **AC-7:** `/idea list` queries Linear (`project=<configured>`, `label=idea`, `state in (Idea, Triage)`) and renders `ID | Created | Title | Status` table. No local file read.
- [ ] **AC-8:** `/idea triage` iterates `Idea`-status issues, presents them with roadmap/backlog context, and applies user-chosen outcomes via MCP: **promote** → status=Backlog + priority set, **merge** → Mark-as-duplicate of named parent (prompts for parent ID), **park** → status=Icebox, **dismiss** → state=Canceled with optional comment.

### Offline pending log

- [ ] **AC-9:** When any MCP call in `/idea add|list|triage` fails (network, auth, server error), the intended write is appended to `.ccanvil/ideas-pending.log` (JSONL, gitignored). Each line: `{"op": "add|promote|park|…", "args": {...}, "ts": <epoch>}`.
- [ ] **AC-10:** `docs-check.sh idea-sync` (new subcommand) reads the pending log, replays each entry via MCP in order, and removes successfully-applied entries. Entries that fail stay in the log; the command reports `SYNCED: N / PENDING: M`.
- [ ] **AC-11:** **Edge — auth expired:** pending log entries persist across sessions; `/idea sync` after re-auth drains them in FIFO order.

### Migration of docs/ideas.md

- [ ] **AC-12:** `docs-check.sh idea-migrate` reads existing `docs/ideas.md`, creates a Linear Triage issue per entry (description=original line, label=`idea` + `migrated-from-docs`, title=Claude-summarized), `git rm`s `docs/ideas.md`, and appends `docs/ideas.md` + `.ccanvil/ideas-pending.log` to `.gitignore` if not already present.
- [ ] **AC-13:** **Edge — migration is idempotent:** running `idea-migrate` a second time when `docs/ideas.md` is absent exits 0 with `"Nothing to migrate"`.

### Operations routing

- [ ] **AC-14:** `operations.sh` registers new operations `idea.add`, `idea.list`, `idea.triage`, `idea.sync`. `is_valid_operation` returns 0 for each.
- [ ] **AC-15:** `linear_mcp_adapter` handles all four idea operations and falls back to the local bash adapter when integrations are absent or Linear provider is missing (zero-config projects still work without Linear).
- [ ] **AC-16:** The `local_adapter` in `operations.sh` handles all four idea operations by writing to/reading from `.ccanvil/ideas.log` (JSONL, gitignored — same shape as `events.log` and the pending log). `docs-check.sh cmd_idea_add|list|count|update` are rewritten to back this local adapter (no longer touching `docs/ideas.md`). Both providers coexist cleanly.

### Pre-activate push-guard

- [ ] **AC-17:** At the top of `cmd_activate`, the script runs `git rev-list origin/main..main | wc -l`. If count > 0, halt with exit 1 and print unpushed commit hashes + short messages.
- [ ] **AC-18:** `docs-check.sh activate <feature-id> --force-local-ahead` bypasses the guard and proceeds. The flag is documented in the halt message as the explicit escape hatch.
- [ ] **AC-19:** **Edge — detached HEAD / no origin:** if `origin/main` does not exist, the guard is a no-op (not every repo has a remote).

### Downstream propagation

- [ ] **AC-27:** `idea-migrate` is per-node-aware: it reads the local `docs/ideas.md`, resolves `idea.add` via `operations.sh` for the current node's config, and routes each entry accordingly (Linear MCP when `routing.idea = "linear"`, local JSONL otherwise). Same command works from hub or any downstream.
- [ ] **AC-28:** `ccanvil-sync.sh broadcast` detects legacy `docs/ideas.md` in each registered node (via `git ls-files` on the node path) and prints a per-node migration hint: `"<node-name>: docs/ideas.md still tracked — run \`docs-check.sh idea-migrate\` on that node"`. Broadcast does NOT auto-migrate.
- [ ] **AC-29:** After `broadcast` + `/ccanvil-pull` delivers the new skill and scripts to a node that hasn't configured a provider yet, `/idea <text>` succeeds via the default local provider. First-time Linear setup is an explicit per-node action, not a side effect of syncing.
- [ ] **AC-30:** The hub's own Linear config lives in its `ccanvil.local.json`, not in the distributed `ccanvil.json`. Verified by: fresh-fixture `git grep '"project"' .claude/ccanvil.json` returns no hub-specific project name.

### Error / edge cases

- [ ] **AC-20:** **Error — Linear unreachable at capture:** `/idea <text>` writes the capture to `.ccanvil/ideas-pending.log` and reports `PENDING: <summary> (N total pending)`. Exit 0.
- [ ] **AC-21:** **Error — missing Linear config:** when `routing.idea = "linear"` but `integrations.providers.linear` is missing `project` / `team`, `/idea` exits 1 with a setup hint pointing to `.claude/ccanvil.local.json` keys. When `routing.idea` is unset or `"local"`, capture proceeds via the local provider — no error.
- [ ] **AC-22:** **Edge — summary generation:** if the raw text is already ≤80 chars and single-line, it becomes the title unchanged (skip the summarization round-trip).

### Documentation

- [ ] **AC-23:** `.claude/skills/idea/SKILL.md` rewritten to describe the Linear-backed flow (capture, list, triage, sync, migrate).
- [ ] **AC-24:** `.ccanvil/guide/command-reference.md` updates the Idea Management Scripts section and adds a note about the Linear integration dependency.
- [ ] **AC-25:** `docs-check.sh activate`'s dirty-worktree allowlist removes `docs/ideas.md` (no longer a tracked file).
- [ ] **AC-26:** Bats tests in `hub/tests/` cover AC-4/5/6/9/10/12/13/17/18/19/20/21. New file `hub/tests/ideas-to-linear.bats`; Linear MCP calls are mocked via a test stub shim.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — remove `cmd_idea_add|list|count|update`, add `cmd_idea_sync` + `cmd_idea_migrate`; add push-guard to `cmd_activate`; remove `ideas.md` from dirty-allowlist |
| `.ccanvil/scripts/operations.sh` | Modified — register `idea.*` operations; extend `linear_mcp_adapter` AND `local_adapter` for them (local adapter writes to `.ccanvil/ideas.log`) |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — `broadcast` detects legacy `docs/ideas.md` per node, prints migration hint |
| `.claude/ccanvil.json` | Modified — populate shared defaults in `integrations.routing.idea` + `integrations.providers.linear` (no node-specific fields) |
| `.claude/ccanvil.local.json` | Modified (hub) — hub's own `project` / `team` (not distributed) |
| `.claude/skills/idea/SKILL.md` | Rewritten — Linear-backed flow, offline fallback, summarization instructions |
| `.ccanvil/guide/command-reference.md` | Modified — Idea scripts section + integration dep note |
| `.gitignore` | Modified — add `docs/ideas.md` and `.ccanvil/ideas-pending.log` |
| `docs/ideas.md` | Deleted after migration |
| `hub/tests/ideas-to-linear.bats` | New — AC-4…AC-22 coverage with MCP stub |
| `hub/tests/activate-push-guard.bats` | New — AC-17/18/19 coverage |

## Dependencies

- **Requires:** Linear MCP authenticated on Zach's workstation (already configured). Manual one-time Linear workspace changes for AC-1/2 (add statuses + label).
- **Blocked by:** none.

## Out of Scope

- Slack / Asks intake (Business plan; future enhancement).
- Registering ccanvil as a custom Linear Agent.
- Cross-project "Ideas Inbox" Initiative view (workspace filter view is sufficient initially).
- Webhook-driven roadmap auto-updates when ideas are parked.
- Triage Rules / Triage Intelligence (Business plan).
- Multi-user triage (single-developer assumption; revisit when ccanvil has external users).
- Auto-detection of which project an idea belongs to based on working directory — explicit config in `.claude/ccanvil.json` / `ccanvil.local.json` is authoritative.
- Broadcast-time automatic idea migration across downstream nodes. Migration is per-node by design (each node's Linear auth, each node's project scope); broadcast only surfaces the *need* for migration.

## Implementation Notes

- Title summarization lives in the skill (stochastic Claude step), not in the script — same pattern as `/spec` title derivation. The script receives both `title` and `body` already separated.
- `linear_mcp_adapter` emits resolution JSON for `idea.*` operations; the skill dispatches MCP calls directly (same two-step pattern as `backlog.list` today). Keep the adapter pure — it returns tool name + params; actual MCP invocation happens in the skill.
- The pending-log format mirrors `.ccanvil/events.log` — JSONL, append-only, one line per intent. Reuse the logger helper if one exists; otherwise a 3-line append.
- Push-guard placement: first operation in `cmd_activate`, before worktree-dirty check, so there's no risk of side-effecting a worktree that'll then be rejected.
- Bats MCP stub: a tiny shell shim that intercepts `mcp__claude_ai_Linear__*` calls and returns canned JSON from a fixture directory. Keeps tests hermetic and fast.
- Provider selection precedence: explicit `routing.idea` wins → defaults to `"local"` when unset. The `local` adapter is the zero-config escape hatch; every downstream node works out of the box even without Linear setup.
- `ideas.log` schema (JSONL, one entry per line): `{"uid": "<4-hex>", "created": <epoch>, "status": "new|promoted|parked|dismissed|merged", "title": "<summary>", "body": "<raw-text>", "parent": "<BTS-XX>?"}`. Mirrors Linear issue shape so a future local→Linear migration is trivial.
- `ideas-pending.log` is separate from `ideas.log`: pending is for failed Linear writes awaiting retry; `ideas.log` is the canonical store when `routing.idea = "local"`. The two never interact.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
