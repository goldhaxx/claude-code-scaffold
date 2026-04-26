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

### Step 0 — extract capture flags (BTS-162 + BTS-172, optional)

Before generating the title, scan the raw input for capture-time flags and extract each into a separate variable, removing the flag + value from the body:

- **`--parent <ref>`** (BTS-162) — capture-time parentId link. Extract into `$PARENT`. Validate non-empty + no-whitespace. Passed through verbatim; provider validates at dispatch.
- **`--source-skill <name>`** (BTS-172) — anchors the body with `Captured during /<name> walk-through.` Extract into `$SOURCE_SKILL`.
- **`--context <text>`** (BTS-172) — anchors the body with `Surfaced at <text>.` Extract into `$CONTEXT`.
- **`--family <BTS-A,BTS-B>`** (BTS-172) — prepends a `## Family` section listing each ref. Extract into `$FAMILY` (comma-separated string passed through to substrate).

When ANY of `--source-skill` / `--context` / `--family` is set, call `docs-check.sh idea-template-body` with the original body and the present flags to compose the final templated body, then use that templated body as the input to title generation and capture dispatch:

```bash
TEMPLATE_ARGS=()
[[ -n "$SOURCE_SKILL" ]] && TEMPLATE_ARGS+=(--source-skill "$SOURCE_SKILL")
[[ -n "$CONTEXT" ]] && TEMPLATE_ARGS+=(--context "$CONTEXT")
[[ -n "$FAMILY" ]] && TEMPLATE_ARGS+=(--family "$FAMILY")
if [[ ${#TEMPLATE_ARGS[@]} -gt 0 ]]; then
  BODY=$(bash .ccanvil/scripts/docs-check.sh idea-template-body --body "$BODY" "${TEMPLATE_ARGS[@]}")
fi
```

Bare `/idea <text>` (no flags) is unchanged — body forwarded verbatim. The templating sub-command is deterministic and side-effect-free; testable in isolation.

### Step 1 — generate a title

- If the raw text is ≤80 chars and single-line, the title = the raw text (short-text fast path; no Claude round-trip).
- Otherwise, generate a concise summary title (≤80 chars, intent-preserving) from the raw text.

### Step 2 — resolve the provider

```bash
bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .
```

### Step 3a — Linear path (`mechanism == "http"`)

BTS-166: capture rides the http substrate. The resolver returns `.invocation.command` carrying a complete `linear-query.sh save-issue` invocation with `--team`, `--project`, `--labels`, and (when `state_ids.triage` is configured) `--state`. Title and description are passed via stdin-JSON so embedded newlines, quotes, backticks, `$VAR`, and `$(cmd)` round-trip without shell interpretation.

```bash
RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .)
cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
# BTS-162: capture-time parent link. Append --parent-id when --parent was
# extracted in Step 0. Quote via jq -Rr @sh so refs round-trip safely.
if [[ -n "$PARENT" ]]; then
  cmd="$cmd --parent-id $(printf '%s' "$PARENT" | jq -Rr @sh)"
fi
jq -n --arg title "$TITLE" --arg description "$BODY" \
  '{title:$title, description:$description}' \
  | eval "$cmd --input-json -"
```

On success: parse the resolver's output (`{id, title}` from the GraphQL `issueCreate` response — `linear-query.sh` reshapes it) and echo `Captured: <identifier> — <title>`.

**On failure** (non-zero exit from `eval`: network, missing `LINEAR_API_KEY`, GraphQL error): append to pending log via the deterministic helper (BTS-123 — never hand-roll JSON via `echo` + interpolation):

```bash
# BTS-162: forward --parent so the replay path re-dispatches with --parent-id.
PARENT_ARGS=()
[[ -n "$PARENT" ]] && PARENT_ARGS=(--parent "$PARENT")
bash .ccanvil/scripts/docs-check.sh idea-pending-append \
  --op add --title "$TITLE" --body "$BODY" "${PARENT_ARGS[@]}"
```

Then count entries via the validator (NEVER `wc -l` — physical lines ≠ JSON entries):

```bash
N=$(bash .ccanvil/scripts/docs-check.sh idea-pending-validate | jq -r .count)
```

Echo `PENDING: <title> ($N total pending)`. Exit 0 — capture MUST succeed from the user's perspective.

### Step 3b — local path (`mechanism == "bash"`)

Run the resolved command. BTS-162: forward `--parent "$PARENT"` when set so the local JSONL entry carries `parent_id`:

```bash
PARENT_FLAG=()
[[ -n "$PARENT" ]] && PARENT_FLAG=(--parent "$PARENT")
bash .ccanvil/scripts/docs-check.sh idea-add "<body>" --title "<title>" "${PARENT_FLAG[@]}" .
```

The script appends one JSONL line with `status:"triage"` (and `parent_id` when `--parent` is supplied).

### Step 4 — return

Echo a one-line confirmation. Return to whatever was in progress.

## List: `/idea list`

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.list --project-dir .`
2. Run the resolved command:
   ```bash
   eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"
   ```
   Both mechanisms (`http` for Linear-routed, `bash` for local) return a JSON array shaped `[{id, title, status, createdAt}, ...]`. No mechanism-specific branching needed at the consumer layer.
3. Render as a table: `ID | Created | Title | Status`.

Default view excludes terminal (Canceled, Duplicate) and deferred (Icebox) states. Pass `--status icebox` / `--status canceled` / etc. to surface them explicitly.

## Triage: `/idea triage`

Batched review of items in Triage state. **Fully agentic** — every outcome is a programmatic state-ID transition via http (Linear) or local bash (log rewrite). No Linear UI interaction.

1. **Resolve:** `bash .ccanvil/scripts/operations.sh resolve idea.triage --project-dir .`
2. **List Triage items:** eval the resolved command. Both mechanisms (`http` for Linear, `bash` for local) return a JSON array of issues — no branching at the consumer layer.
   ```bash
   eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"
   ```
3. **Load context:** read `docs/roadmap.md` (if present); run `bash .ccanvil/scripts/operations.sh exec backlog.list` for existing backlog.
4. **Present a table of recommendations.** One row per item. Ask for approval.
5. **For each approved outcome, resolve via `ticket.transition` and dispatch:**

| Outcome | `operations.sh resolve` | Linear dispatch (eval + extra flags) | Local dispatch |
|---------|-------------------------|--------------------------------------|----------------|
| **promote** | `ticket.transition <id> backlog` | `eval "$cmd --priority <1-4>"` | `idea-update <uid> backlog` |
| **defer**   | `ticket.transition <id> icebox`  | `eval "$cmd"`                  | `idea-update <uid> icebox` |
| **dismiss** | `ticket.transition <id> canceled` | `eval "$cmd"`                 | `idea-update <uid> canceled` |
| **merge**   | `ticket.transition <id> duplicate` | `eval "$cmd --duplicate-of <target>"` | `idea-update <uid> duplicate` |

BTS-164 migrated `ticket.transition` to `mechanism: http` — the resolver now returns `.invocation.command` carrying a complete `linear-query.sh save-issue --id <id> --state <state-id>` invocation. The skill stores that command in `$cmd` and appends outcome-specific flags (`--priority` for promote, `--duplicate-of` for merge) before eval'ing. The wrapper handles auth via `LINEAR_API_KEY` and surfaces GraphQL errors as exit 3.

```bash
# Per-row dispatcher pattern. Quote variable values via jq @sh before
# appending to the eval string — protects against any future case where
# input bleeds in (priority is numeric and target IDs are ticket keys
# today, but the pattern shouldn't teach unsafe append).
RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve ticket.transition "$ID" "$ROLE" --project-dir .)
cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
case "$OUTCOME" in
  promote)
    p=$(printf '%s' "$PRIORITY" | jq -R @sh)
    eval "$cmd --priority $p"
    ;;
  merge)
    t=$(printf '%s' "$TARGET_ID" | jq -R @sh)
    eval "$cmd --duplicate-of $t"
    ;;
  *)
    eval "$cmd"
    ;;
esac
```

**On dispatch failure for any outcome** (network, missing `LINEAR_API_KEY`, GraphQL error), append to pending log via the deterministic helper (BTS-123):

```bash
# promote
bash .ccanvil/scripts/docs-check.sh idea-pending-append --op promote --id BTS-X --priority 3
# defer / dismiss
bash .ccanvil/scripts/docs-check.sh idea-pending-append --op defer --id BTS-X
bash .ccanvil/scripts/docs-check.sh idea-pending-append --op dismiss --id BTS-X
# merge
bash .ccanvil/scripts/docs-check.sh idea-pending-append --op merge --id BTS-X --duplicate-of BTS-Y
# ticket.transition (queued by /land on auto-close MCP failure)
bash .ccanvil/scripts/docs-check.sh idea-pending-append --op ticket.transition --id BTS-X --role done
```

Exit 0 per item. `/idea sync` replays these later.

## Review Icebox: `/idea review-icebox`

Re-evaluate Icebox items older than 60d. Prevents graveyard drift.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.review-icebox --project-dir .`
2. Pull stale items: eval the resolved command. http path filters by `--state icebox` (or the configured icebox state-id) on Linear; local path runs `docs-check.sh idea-review-icebox`. Filter locally by `createdAt <= now - 60d`.
   ```bash
   eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"
   ```
3. Present a table. For each, ask: **promote back to Backlog**, **keep in Icebox** (re-stamp review timestamp — future), **dismiss** (canceled), or **merge** into another issue.
4. Dispatch outcomes using the same rubric as `/idea triage` above.

## Sync: `/idea sync`

Only meaningful when the Linear provider is configured and `.ccanvil/ideas-pending.log` has entries.

1. Resolve: `bash .ccanvil/scripts/operations.sh resolve idea.sync --project-dir .`
2. Run the returned command (always local bash: `docs-check.sh idea-sync`) to enumerate pending entries.
3. For each entry, dispatch by `op` via the http substrate (BTS-166):
   - `add` → re-resolve `idea.add` via `operations.sh`; if the pending entry has `args.parent_id`, append `--parent-id $(printf '%s' "$parent_id" | jq -Rr @sh)` to `$cmd` before `eval` (BTS-162). Pipe `{title, description}` JSON to `eval "$cmd --input-json -"`. Idempotency caveat: Linear creates aren't deduped server-side, so a replayed `add` could double-capture if the original earlier-replay actually succeeded but the `--ack` failed. Acceptable risk for capture (rare); operator can dismiss the dup via `/idea triage`.
   - `promote` → re-resolve `ticket.transition <args.id> backlog`; eval `"$cmd --priority $priority"`.
   - `defer` / `dismiss` → re-resolve `ticket.transition <args.id> {icebox|canceled}`; eval `"$cmd"`.
   - `merge` → re-resolve `ticket.transition <args.id> duplicate`; eval `"$cmd --duplicate-of $target"`.
   - `ticket.transition` → re-resolve `ticket.transition <args.id> <args.role>`; eval the returned command. Queued by `/land` (BTS-119) when auto-close fails. Idempotent — Linear's API accepts transitions to the current state without error.
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

## Safe-markdown for Linear-bound bodies

Linear's server-side normalizer silently mutates one specific markdown shape on save: numbered-list items whose leading bold STARTS with a backticked code-span (`**` followed immediately by `` ` ``) get the bold markers stripped on round-trip, leaving only the code-span and the trailing text. Items where bold contains backticks NOT at the start are preserved.

To avoid the silent rewrite when composing idea bodies bound for Linear, prefer one of these shapes:

- **Codespan-then-text:** `` `code` — text. `` — clean, no bold needed.
- **Bold-with-late-codespan:** `**Text with `code` later.**` — bold survives because backticks are not at the start.
- **Avoid:** `**`code` text.**` — bold gets stripped.

Anchored on BTS-125 (repro on 2026-04-26 in test ticket BTS-174). Other normalizations exist (e.g., `-` bullets become `*`) but are cosmetic-only and don't affect rendered output. Round-trip-validation tooling is out of scope; this is a documentation-level guard.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
