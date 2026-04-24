---
name: idea
description: Capture, list, triage, review-icebox, or sync project ideas via the configured provider (Linear MCP native-Triage or gitignored local JSONL). Fully agentic — no Linear UI required.
---

Capture, list, triage, review-icebox, or sync project ideas. The skill resolves each operation through `.ccanvil/scripts/operations.sh`, which picks a provider based on `.claude/ccanvil.json` + `.claude/ccanvil.local.json`:

- **Linear provider** — projects whose `ccanvil.local.json` sets `integrations.routing.idea = "linear"` capture directly into Linear's Triage state via MCP. The resolver injects `state` from `state_ids.triage` when configured, routing captures into the Triage inbox deterministically. All mutations (promote, defer, dismiss, merge) transition issues by **state ID** — never by name — so no Linear UI interaction is ever required.
- **Local provider** (default) — everything else writes to `.ccanvil/ideas.log` (JSONL, gitignored, never committed). Same five-state vocabulary: triage / backlog / icebox / canceled / duplicate.

Either way, `/idea` never touches git. No commits. No branch creation. Capture works from any branch, including main.

## Lifecycle states

| State | Meaning |
|-------|---------|
| **Triage** | Captured, not yet reviewed. The inbox. |
| **Backlog** | Reviewed, will be worked. Has priority. |
| **Icebox** | Reviewed, deferred long-term. Re-evaluated on cadence via `/idea review-icebox` and `/radar`. |
| **Canceled** | Reviewed, dead. |
| **Duplicate** | Merged into another issue. |

## Usage

- `/idea <text>` — capture (default)
- `/idea list` — show non-terminal, non-deferred ideas (triage + backlog). Filter by status with `--status icebox`, etc.
- `/idea triage` — review items in Triage and take one of four outcomes per item (promote / defer / dismiss / merge).
- `/idea review-icebox` — surface Icebox items older than 60d for re-evaluation.
- `/idea sync` — replay any `.ccanvil/ideas-pending.log` entries (Linear users, after MCP downtime).

## Capture: `/idea <text>`

If the first arg is not `list`, `triage`, `review-icebox`, or `sync`, treat everything after `/idea` as the idea text.

### Step 1 — generate a title

- If the raw text is ≤80 chars and single-line, the title = the raw text (short-text fast path; no Claude round-trip).
- Otherwise, generate a concise summary title (≤80 chars, intent-preserving) from the raw text.

### Step 2 — resolve the provider

```bash
bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .
```

### Step 3a — Linear path (`mechanism == "mcp"`)

Extract `.invocation.tool`, `.invocation.params.project`, `.invocation.params.team`, `.invocation.params.labels`, and `.invocation.params.state` (present when `state_ids.triage` is configured) from the resolution. Pass `state` through to `save_issue` when present — this routes the capture into Linear's Triage state deterministically. When unconfigured, omit `state` entirely; Linear will fall through to the team's default state (usually Backlog, **not** Triage — the earlier "auto-routes API-created issues to Triage" assumption was falsified empirically).

Call the MCP tool directly:

```
mcp__claude_ai_Linear__save_issue
  team:        <params.team>
  project:     <params.project>
  labels:      <params.labels>      # typically ["idea"]
  state:     <params.state>     # only when present in resolver output
  title:       <generated title>
  description: <original raw text, verbatim>
```

On success: echo `Captured: <identifier> — <title>`.

**On failure** (network, auth, server error): append to pending log:

```bash
echo '{"op":"add","args":{"title":"<title>","body":"<body>"},"ts":'"$(date +%s)"'}' \
  >> .ccanvil/ideas-pending.log
```

Echo `PENDING: <title> (<N> total pending)`. Exit 0 — capture MUST succeed from the user's perspective.

### Step 3b — local path (`mechanism == "bash"`)

Run the resolved command:

```bash
bash .ccanvil/scripts/docs-check.sh idea-add "<body>" --title "<title>" .
```

The script appends one JSONL line with `status:"triage"`.

### Step 4 — return

Echo a one-line confirmation. Return to whatever was in progress.

## List: `/idea list`

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.list --project-dir .`
2. If `.mechanism == "mcp"`: call `mcp__claude_ai_Linear__list_issues` with the returned params.
3. If `.mechanism == "bash"`: run the returned command (`docs-check.sh idea-list`).
4. Render as a table: `ID | Created | Title | Status`.

Default view excludes terminal (Canceled, Duplicate) and deferred (Icebox) states. Pass `--status icebox` / `--status canceled` / etc. to surface them explicitly.

## Triage: `/idea triage`

Batched review of items in Triage state. **Fully agentic** — every outcome is a programmatic state-ID transition via MCP (Linear) or local bash (log rewrite). No Linear UI interaction.

1. **Resolve:** `bash .ccanvil/scripts/operations.sh resolve idea.triage --project-dir .`
2. **List Triage items:**
   - mcp: call `mcp__claude_ai_Linear__list_issues` with `.invocation.params` (includes `state` when configured — disambiguation-proof).
   - bash: run `docs-check.sh idea-list --status triage`.
3. **Load context:** read `docs/roadmap.md` (if present); run `bash .ccanvil/scripts/operations.sh exec backlog.list` for existing backlog.
4. **Present a table of recommendations.** One row per item. Ask for approval.
5. **For each approved outcome, resolve via `ticket.transition` and dispatch:**

| Outcome | `operations.sh resolve` | Linear dispatch (`save_issue`) | Local dispatch |
|---------|-------------------------|--------------------------------|----------------|
| **promote** | `ticket.transition <id> backlog` → params.{id, state} | `{...params, priority: <1-4>}` | `idea-update <uid> backlog` |
| **defer**   | `ticket.transition <id> icebox`  → params.{id, state} | `{...params}`                  | `idea-update <uid> icebox` |
| **dismiss** | `ticket.transition <id> canceled` → params.{id, state} | `{...params}`                 | `idea-update <uid> canceled` |
| **merge**   | `ticket.transition <id> duplicate` → params.{id, state} | `{...params, duplicateOf: <target>}` | `idea-update <uid> duplicate` |

The `ticket.transition` wrapper (BTS-128) returns both `id` and `state` pre-populated, collapsing the previous "resolve state → manually stitch id → dispatch" pattern into a single resolver call. Always pass `state` from the resolver — never pass `state: "<name>"`. State names collide with type names in Linear's workflow resolver and silently become no-ops.

**On MCP failure for any outcome**, append to pending log:

```bash
echo '{"op":"promote","args":{"id":"BTS-X","priority":3},"ts":'"$(date +%s)"'}' \
  >> .ccanvil/ideas-pending.log
```

Exit 0 per item. `/idea sync` replays these later.

## Review Icebox: `/idea review-icebox`

Re-evaluate Icebox items older than 60d. Prevents graveyard drift.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.review-icebox --project-dir .`
2. Pull stale items:
   - mcp: `mcp__claude_ai_Linear__list_issues` with `params.state` (icebox); filter locally by `createdAt <= now - 60d`.
   - bash: run `docs-check.sh idea-review-icebox`.
3. Present a table. For each, ask: **promote back to Backlog**, **keep in Icebox** (re-stamp review timestamp — future), **dismiss** (canceled), or **merge** into another issue.
4. Dispatch outcomes using the same rubric as `/idea triage` above.

## Sync: `/idea sync`

Only meaningful when the Linear provider is configured and `.ccanvil/ideas-pending.log` has entries.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.sync --project-dir .`
2. Run the returned command (always local bash: `docs-check.sh idea-sync`).
3. For each entry, dispatch by `op`:
   - `add` → `save_issue` with title/body/labels (capture).
   - `promote` → `save_issue` with id + state(backlog) + priority.
   - `defer` / `dismiss` → `save_issue` with id + target state.
   - `merge` → `save_issue` with id + state(duplicate) + duplicateOf.
   - `ticket.transition` → re-resolve `ticket.transition <args.id> <args.role>` via `operations.sh`; dispatch the returned `save_issue` with `id + state` from `.invocation.params`. Queued by `/land` (BTS-119) when auto-close MCP fails. Idempotent — Linear's API accepts transitions to the current state without error.
4. On success per entry: `docs-check.sh idea-sync --ack <ts>`.
5. Report: `SYNCED: N / PENDING: M`.

## Legacy migration (one-shot)

For projects that pre-date this change, items may still live in the deprecated custom "Idea" state (Linear) or legacy status values (local).

- **Local log:** `bash .ccanvil/scripts/docs-check.sh idea-migrate-state .` — rewrites legacy vocab in `.ccanvil/ideas.log`, timestamped backup preserved. Idempotent.
- **Linear workspace:** iterate issues in the deprecated custom Idea state, promote each to Backlog via `save_issue` with state. Then delete the custom state in Linear's workflow config (manual operator step — Linear may block deletion of states with historical refs).

## Rules

- `/idea` NEVER commits. NEVER creates a branch. Never touches git.
- On Linear failure, fall back to `.ccanvil/ideas-pending.log`. Never surface MCP errors as user errors — pending is a successful capture outcome.
- Always dispatch mutations by **state ID**, never by state name. Name-based dispatch silently no-ops when names collide with state types.
- Respect the provider resolution. Don't bypass `operations.sh` by calling MCP or local bash directly based on a hunch.
- The full workflow — capture, list, triage, review, dispatch — is agent-reachable. Never delegate a transition to the Linear UI.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
