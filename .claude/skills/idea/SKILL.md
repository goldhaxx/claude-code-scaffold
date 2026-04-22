---
name: idea
description: Capture, list, or triage project ideas via the configured provider (Linear MCP or gitignored local JSONL).
---

Capture, list, triage, or sync project ideas. The skill resolves each operation through `.ccanvil/scripts/operations.sh`, which picks a provider based on `.claude/ccanvil.json` + `.claude/ccanvil.local.json`:

- **Linear provider** — projects whose `ccanvil.local.json` sets `integrations.routing.idea = "linear"` route captures to Linear Triage via MCP.
- **Local provider** (default) — everything else writes to `.ccanvil/ideas.log` (JSONL, gitignored, never committed).

Either way, `/idea` never touches git. No commits. No branch creation. Capture works from any branch, including main.

## Usage

- `/idea <text>` — capture (default)
- `/idea list` — show all ideas (Triage + Idea on Linear, or new/promoted/etc. locally)
- `/idea triage` — review untriaged ideas against roadmap + backlog
- `/idea sync` — replay any `.ccanvil/ideas-pending.log` entries (Linear users, after MCP downtime)

## Capture: `/idea <text>`

If the first arg is not `list`, `triage`, or `sync`, treat everything after `/idea` as the idea text.

### Step 1 — generate a title

- If the raw text is ≤80 chars and single-line, the title = the raw text (short-text fast path; no Claude round-trip needed).
- Otherwise, generate a concise summary title (≤80 chars, intent-preserving) from the raw text. Same stochastic step as `/spec` title derivation.

### Step 2 — resolve the provider

```bash
bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .
```

Read the JSON result's `.mechanism` field to pick the path.

### Step 3a — Linear path (`mechanism == "mcp"`)

Extract `.invocation.tool`, `.invocation.params.project`, `.invocation.params.team`, `.invocation.params.state`, `.invocation.params.labels` from the resolution.

Call the MCP tool directly:

```
mcp__claude_ai_Linear__save_issue
  team:        <params.team>
  project:     <params.project>
  state:       <params.state>            # typically "Idea"
  labels:      <params.labels>           # typically ["idea"]
  title:       <generated title>
  description: <original raw text, verbatim>
```

On success: echo `Captured: <identifier> — <title>` (e.g., `Captured: BTS-123 — add retrofit-check --json flag`). The `.identifier` / issue ID surfaces in the tool response.

**On failure** (network error, auth expired, Linear server issue): append to the pending log and fall through gracefully:

```bash
echo '{"op":"add","args":{"title":"<title>","body":"<body>"},"ts":'"$(date +%s)"'}' \
  >> .ccanvil/ideas-pending.log
```

Then echo `PENDING: <title> (<N> total pending)` where N = line count of `.ccanvil/ideas-pending.log`. Exit 0 — capture MUST succeed from the user's perspective.

### Step 3b — local path (`mechanism == "bash"`)

Run the resolved command, passing the body and the generated title explicitly:

```bash
bash .ccanvil/scripts/docs-check.sh idea-add "<body>" --title "<title>" .
```

The script appends one JSONL line to `.ccanvil/ideas.log`.

### Step 4 — return

Echo a one-line confirmation. Do NOT discuss the idea further unless asked. Return to whatever was in progress.

## List: `/idea list`

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.list --project-dir .`
2. If `.mechanism == "mcp"`: call `mcp__claude_ai_Linear__list_issues` with the returned params.
3. If `.mechanism == "bash"`: run the returned command (`docs-check.sh idea-list`).
4. Render as a table: `ID | Created | Title | Status`.

## Triage: `/idea triage`

Batched review of untriaged ideas.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.triage --project-dir .`
2. Pull untriaged ideas:
   - mcp: `mcp__claude_ai_Linear__list_issues` with the returned params (filtered to `state: Idea`).
   - bash: run the returned command (`docs-check.sh idea-list --status new`).
3. Load context: read `docs/roadmap.md` (if present); run `bash .ccanvil/scripts/operations.sh exec backlog.list` for existing backlog.
4. Present recommendations as a table. Ask for approval.
5. For each approved outcome, apply via MCP (Linear) or local bash:

| Outcome | Linear action (`save_issue`) | Local action |
|---------|------------------------------|--------------|
| **promote** | `{id, state: "Backlog", priority: <1-4>}` | `idea-update <uid> promoted` |
| **merge**   | `{id, duplicateOf: "<parent-id>"}` (Linear marks as Canceled/Duplicate) | `idea-update <uid> merged` |
| **park**    | `{id, state: "Icebox"}` | `idea-update <uid> parked` |
| **dismiss** | `{id, state: "Canceled"}` (optionally add a comment with the reason) | `idea-update <uid> dismissed` |

## Sync: `/idea sync`

Only meaningful when the Linear provider is configured and `.ccanvil/ideas-pending.log` has entries.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.sync --project-dir .`
2. Run the returned command (always local bash: `docs-check.sh idea-sync`). The command iterates the pending log, replays each entry via MCP, removes successes.
3. Report the summary line: `SYNCED: N / PENDING: M`.

## Rules

- `/idea` NEVER commits. NEVER creates a branch. The whole point is to avoid git-divergence from capture.
- On Linear failure, fall back to `.ccanvil/ideas-pending.log`. Never surface MCP errors to the user — pending is a successful capture outcome.
- Respect the provider resolution. Don't bypass `operations.sh` by calling MCP or local bash directly based on a hunch.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
