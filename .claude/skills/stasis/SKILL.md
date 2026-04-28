---
name: stasis
description: End-of-session strategic review — freeze a snapshot of session/project state before /compact so cross-session context survives compaction.
---

Run at the end of a session, immediately before `/compact`. Writes `docs/stasis.md` — the strategic microscope/macroscope that captures determinism review, security review, cross-session patterns, and memory candidates that compaction would otherwise lose.

`/stasis` is the counterpart to `/recall`: stasis writes, recall reads.

## Pre-flight halt check

1. **BTS-20: lifecycle-state pre-flight.** Run `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` and read `.state` from the envelope.
   - **Benign states — continue:** `no-active-spec`, `spec-activated`, `plan-written`, `implementing`, `session-wrap`. (Stasis is legal across all in-flight feature states; on `session-wrap` it's mid-stasis, idempotent.)
   - **Corruption state — STOP and surface the failure:** `blocked`. The envelope's `.blockers[]` array carries the specific causes (`stale-plan`, `mismatched`, `unlinked`, etc — the validate detail strings the primitive composes from). Report the blockers verbatim and ask the user to fix the lifecycle state first.
   - **Edge state — STOP:** `uninitialized` (not a ccanvil tree).
   - Do not write a clean stasis snapshot on top of a broken lifecycle. The envelope's blockers ARE the recovery checklist.

## Data gathering (deterministic)

Collect these inputs via scripts — all deterministic, all cheap:

2. `bash .ccanvil/scripts/docs-check.sh status` — feature_id, plan_hash, content hashes for spec/plan/stasis.
2a. `bash .ccanvil/scripts/docs-check.sh session-info --project-dir .` (BTS-206) — session counter + ISO-8601 local boundary. Capture `.counter` and `.iso`; when `.counter > 0` substitute into `> Session: N` and `> Boundary: <iso>` metadata lines; when `.counter == 0` (fresh node, hook hasn't fired yet), omit both lines from the rendered stasis.
3. `bash .ccanvil/scripts/docs-check.sh radar-gather` — active spec, completed specs, idea counts, roadmap theme, git activity, backlog.
4. `bash .ccanvil/scripts/docs-check.sh idea-count` — untriaged idea count for the Next Steps section.
5. `bash .ccanvil/scripts/docs-check.sh audit-session --since <last-stasis-commit>` — scan git diffs for stochastic patterns (fallback to last 20 commits if no prior stasis).
6. `bash .ccanvil/scripts/docs-check.sh legacy-refs-scan --respect-allowlist hub/tests/legacy-refs-allowlist.txt` — check for stale references to legacy verbs/artifacts, pre-filtered by the allowlist (BTS-132) so only REAL drift surfaces in Cross-Session Patterns. On downstream nodes without `hub/tests/`, omit the flag — the raw output is fine.
7. `bash .ccanvil/scripts/permissions-audit.sh check --json` (if available) — classify any DANGER or UNREVIEWED permissions. Read `.danger` count.
8. `bash .ccanvil/scripts/permissions-audit.sh promote-review --json` (BTS-149, if available) — list `settings.local.json` delta candidates classified as DELETE/TRIAGE. Read `.counts.total`.
9. `bash .ccanvil/scripts/context-budget.sh check` (if available) — context budget HEALTHY/WARNING/CRITICAL.
10. `git log --oneline -20` — recent commit history.
11. `git show HEAD~1:docs/stasis.md 2>/dev/null || true` — the prior stasis snapshot, if any. If the command fails (no prior), proceed and note "First stasis — no prior state to compare" in the Cross-Session Patterns section.
12. `bash .ccanvil/scripts/module-manifest.sh validate --json 2>/dev/null` (BTS-239, if `.ccanvil/manifest-allowlist.txt` exists) — capture `{coverage: {covered, total}, drift: [...], status}` for the Manifest Coverage section. When the allowlist is missing or empty, the substrate emits `{coverage:{covered:0,total:0}, drift:[], status:"ok"}` — surface the literal `Manifest coverage: N/A (no allowlist yet).` instead.

## Determine stasis kind — feature vs session

Before synthesizing, pick the stasis kind from the lifecycle state:

- **Feature-kind stasis** — write when `docs/spec.md` AND `docs/plan.md` both exist (mid-feature). Metadata carries:
  - `> Feature: <feature-id>` (from spec.md)
  - `> Work: <provider>:<id>` (inherited from spec.md's `> Work:` line; omit if spec is legacy/no Work:)
  - `> Kind: feature`
  - `> Plan hash: <plan-hash>`
- **Session-kind stasis** — write when NO active spec+plan on the current branch (typically at a session boundary on main, between features). Metadata carries:
  - `> Feature: session-YYYY-MM-DD-<short-slug>-ship`
  - `> Kind: session`
  - `> Last updated: <epoch>`
  - **NO `> Work:` field** — session-stasis is ambient state, not feature state
  - **NO `> Plan hash: <hash>`** — no plan to hash against

The validator excludes `Kind: session` stasis from feature alignment, so the old BTS-120 trap (session-stasis tripping `/pr` validate) is gone. Absence of `Kind:` defaults to feature-kind for backward-compat with pre-BTS-130 stasis files.

Inherit `> Work:` when feature-kind by reading `bash .ccanvil/scripts/docs-check.sh status` and copying `.spec.work` verbatim.

## Synthesis — write the stasis snapshot

**BTS-204: provider-aware write.** Compose the full stasis content from
`.ccanvil/templates/stasis.md` as the structural template, then write via
the routing-aware primitive:

```bash
# Feature-kind:
<rendered stasis content> | bash .ccanvil/scripts/docs-check.sh \
  artifact-write --kind stasis --stasis-kind feature --feature <BTS-N>

# Session-kind (no --feature; uses provider config's project_id):
<rendered stasis content> | bash .ccanvil/scripts/docs-check.sh \
  artifact-write --kind stasis --stasis-kind session
```

On local-routed nodes this writes `docs/stasis.md` (existing behavior).
On Linear-routed nodes (`integrations.routing.stasis=linear`) this upserts
the stasis Linear Document — issue-parented for feature-kind, project-parented
for session-kind. Cross-session history continues to live in `docs/sessions/`
archives via the BTS-22 archive substrate (unchanged).

Fill each section:

### ## Accomplished
What was completed this session. Use git log + file changes as the factual spine, your own session memory for the narrative.

### ## Current State
- **Branch:** current branch
- **Tests:** result of `bash .ccanvil/scripts/bats-report.sh --parallel` (single invocation — BTS-118)
- **Uncommitted changes:** summary from `git diff --stat`
- **Build status:** clean / errors (state any failing steps)

### ## Blocked On
Anything preventing progress. "Nothing" if clean.

### ## Next Steps
Explicit numbered next actions when resuming. Pull from radar-gather's roadmap "Up Next" + spec backlog state + untriaged idea count.

### ## Context Notes
Decisions made, alternatives considered, failed approaches. Anything the next session needs to know that isn't in git history or the code itself.

### ## Determinism Review
Follow `.claude/rules/self-review.md`. Review operations from this session; flag ones that should become scripts/hooks. Fill `operations_reviewed: <count>`, `candidates_found: <count>`, plus a bullet per candidate or "No candidates this session." **This section is mandatory** — validate will flag it as missing-determinism-review if empty.

**BTS-115: dual-capture each candidate as an idea.** After writing the section, for each candidate (skip entirely if `candidates_found == 0`):

1. **Derive a deterministic title:** `Determinism: <candidate-slug>` where `<candidate-slug>` is the bolded operation name from the bullet (markdown `**` markers stripped, trimmed, ≤80 chars). Stable across sessions — same input, same title.
2. **Dedup against existing ideas (Linear-routed only):**
   ```bash
   IDEA_LIST=$(bash .ccanvil/scripts/operations.sh resolve idea.list --project-dir .)
   provider=$(echo "$IDEA_LIST" | jq -r '.provider')
   if [[ "$provider" == "linear" ]]; then
     listing=$(eval "$(echo "$IDEA_LIST" | jq -r '.invocation.command')")
     match=$(echo "$listing" | jq -r --arg t "$TITLE" '[.[] | select(.title == $t)] | .[0].id // ""')
     if [[ -n "$match" ]]; then
       echo "dedup: skipped '$TITLE' — existing idea $match"
       continue
     fi
   fi
   ```
3. **Capture via the resolved provider (BTS-205: local-routed no longer skipped):**
   ```bash
   RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .)
   mechanism=$(echo "$RESOLUTION" | jq -r '.mechanism')
   cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
   captured=0
   case "$mechanism" in
     bash)
       # Local-routed: idea-add appends to .ccanvil/ideas.log
       if bash .ccanvil/scripts/docs-check.sh idea-add "$BODY" --title "$TITLE" --project-dir . >/dev/null 2>&1; then
         captured=1
       fi
       ;;
     http)
       # Linear-routed: dispatch the resolved http command
       if jq -n --arg title "$TITLE" --arg description "$BODY" \
            '{title:$title, description:$description}' \
            | eval "$cmd --input-json -" >/dev/null 2>&1; then
         captured=1
       fi
       ;;
   esac
   if (( captured == 1 )); then
     echo "Captured idea: $TITLE"
   else
     # Pending-log fallback. BTS-205: idea-pending-append now writes to
     # .ccanvil/dual-capture-emergency.log if its own primary log write
     # also fails — determinism candidates never evaporate silently.
     if bash .ccanvil/scripts/docs-check.sh idea-pending-append --op add --title "$TITLE" --body "$BODY"; then
       echo "PENDING: capture queued for /idea sync ($TITLE)"
     else
       echo "ERROR: dual-capture failed all paths (primary + pending + emergency) for $TITLE" >&2
     fi
   fi
   ```

The capture body is the bullet's full text (operation, what happened, deterministic replacement, impact). Capture failure NEVER aborts the stasis flow — the pending-log + emergency-log chain guarantees forward progress.

### ## Evidence Gaps (BTS-201)
**Always present** — never omitted. Surfaces session captures that look like bug reports but lack reproducible evidence (per `.claude/rules/evidence-required-for-captures.md`).

Run the substrate primitive:

```bash
SCAN=$(bash .ccanvil/scripts/docs-check.sh evidence-scan-session \
  --since "$LAST_STASIS_COMMIT" --project-dir .)
GAPS=$(echo "$SCAN" | jq -r '.evidence_gaps')
SCANNED=$(echo "$SCAN" | jq -r '.scanned')
```

Where `$LAST_STASIS_COMMIT` is the commit where the prior `docs/stasis.md` was written (extract from `git log -1 --format=%H -- docs/stasis.md` on the parent commit, or empty for first stasis — the substrate falls back to a 24h scan automatically).

**When `evidence_gaps` is empty**, write the literal:

```
No evidence gaps this session.
```

**When non-empty**, render one bullet per gap:

```
- BTS-X — <title> — <reason>
```

The empty-state literal is parseable by `/recall`'s briefing renderer — it determines whether to surface the carry-forward heading or stay silent. Never mutate the literal phrasing.

This section closes the BTS-198 failure mode: a "Likely root cause" capture that slipped through prior stasis review and almost shipped a regex carve-out for a phantom rule. The protocol is documented in `.claude/rules/evidence-required-for-captures.md`.

### ## Manifest Coverage (BTS-239)
Surfaces Layer 2 (Self-Describing Systems) coverage. Required section.

When step 12 returned a populated envelope (allowlist exists), render the populated form:

```
<covered> / <total> (allowlist), drift incidents: <N>
```

Compose via:

```bash
echo "$VALIDATE_JSON" | jq -r '"\(.coverage.covered) / \(.coverage.total) (allowlist), drift incidents: \(.drift | length)"'
```

When the allowlist is missing or `total == 0`, render the literal `Manifest coverage: N/A (no allowlist yet).` Substrate spec at `.ccanvil/templates/manifest.md`.

### ## Permissions Review Pending (BTS-149)
Conditional section — include ONLY when `(promote-review.counts.total + check.danger) > 0`. When both counts are 0, OMIT this section entirely (no noise).

When present, structure:
- One-line summary: `N DELETE/TRIAGE candidates from settings.local.json + M DANGER entries lacking accept_danger rationale.`
- Bullet list of promote-review candidates with permission + recommended decision (`DELETE one-shot`, `DELETE redundant`, `TRIAGE`).
- Bullet list of DANGER entries needing rationale (truncate at 5 with "+ N more" if >5).
- Always end with: `Run \`/permissions-review\` to triage interactively.`

### ## Cross-Session Patterns
Compare this session to the prior stasis (from step 10):
- Any determinism-review candidate that appeared last session AND this session → flag as a recurring pattern.
- Any audit-session finding that also appeared last time → flag.
- Surface any matches from `legacy-refs-scan` (step 6). Split by scope: `hub-owned` (fix at the hub) vs `node-specific` (fix in the node). If all matches are hub-owned, note "Next /ccanvil-pull will resolve."
- If `git show HEAD~1:docs/stasis.md` failed in step 10, state: "First stasis — no prior state to compare."
- If no recurring patterns found, state: "No recurring patterns."

### ## Security Review
Prefer the `security-audit` skill if available — invoke it and summarize the finding.
Fallback: grep the session's diff for secret/PII patterns (tokens, private keys, emails in non-.example files, etc.). Report `PASS` or a bullet list of findings.

### ## Memory Candidates
List insights that meet auto-memory criteria:
- Non-obvious feedback the user gave.
- Surprising project facts you learned.
- External references (Linear tickets, Slack channels, dashboards, docs).
- Patterns the user validated explicitly ("yes, exactly that").

If none: "No candidates this session."

## Commit the snapshot

12. **Commit the live snapshot.** On local-routed nodes, stage and commit
    `docs/stasis.md`. On Linear-routed nodes (`integrations.routing.stasis=linear`),
    the canonical write went to Linear at the artifact-write step above —
    skip the `git add docs/stasis.md` (file does not exist) and commit only
    the `docs/sessions/` archive at step 12a. Detect via:
    `route=$(jq -r '.integrations.routing.stasis // "local"' .claude/ccanvil.json .claude/ccanvil.local.json 2>/dev/null | grep -v '^$' | tail -1)`
    ```bash
    ALLOW_MAIN=1 git add docs/stasis.md
    ALLOW_MAIN=1 git -c commit.gpgsign=false commit -m "docs: stasis <feature-id>"
    ```
    The `ALLOW_MAIN=1` bypass is required because `protect-main.sh` otherwise blocks direct commits to main — and stasis commits are a deliberate exception (they capture state at a boundary, not feature work).

## Archive into the session history (BTS-22)

12a. After committing the live `docs/stasis.md`, persist a copy into `docs/sessions/<epoch>-<feature_id>.md` so `/recall` can read recent sessions without git archeology:
    ```bash
    bash .ccanvil/scripts/docs-check.sh archive-stasis --project-dir .
    ALLOW_MAIN=1 git add docs/sessions/
    ALLOW_MAIN=1 git -c commit.gpgsign=false commit -m "chore(stasis-archive): persist <feature-id>"
    ```
    `archive-stasis` is idempotent — running it twice on byte-identical content emits `{archived: false, reason: "already-archived"}` and exits 0. On collision with non-identical content (e.g., the live stasis was edited after a prior archive), it errors and the operator decides how to resolve. The archive is a forward-only history; `cmd_complete` and `cmd_land` never touch `docs/sessions/`.

## Close

13. Final output must end with a single explicit next-action directive:
    ```
    Run `/compact` to wrap session.
    ```

## Rules

- `/stasis` is a write command. It writes exactly one file (`docs/stasis.md`), commits it, and nothing else.
- Never write a stasis on top of a non-aligned lifecycle state — halt per the pre-flight check.
- Never run `/compact` as part of stasis. Compaction is the user's next explicit action.
- Keep the synthesis tight. The stasis is a briefing, not a novel — every section should survive a cold read in the next session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
