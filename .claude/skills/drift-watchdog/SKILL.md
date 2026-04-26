Run the drift watchdog: detect drift between the hub and registered downstream nodes, then open a thoughtful, idempotent Linear issue per drifted node via the http substrate.

This skill is designed to be invoked autonomously via `claude -p "/drift-watchdog"` from a launchd entry. It runs end-to-end without operator interaction.

**Operator install / reload (BTS-199):** one idempotent command wraps plist generation, lint, optional unload, copy, load, and verify:

```bash
ALLOW_OUTSIDE_WORKSPACE=1 bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-launchd-install --reload
```

Without `--reload`, the install is idempotent for first-time setup. The `ALLOW_OUTSIDE_WORKSPACE=1` prefix is required because the wrapper writes to `~/Library/LaunchAgents/`. The legacy multi-step recipe (`drift-watchdog-launchd-print` + `plutil -lint` + `launchctl unload/cp/load -w` + verify) still works directly but is no longer the canonical path — use the wrapper.

## Steps

### 1. Pre-flight check

Run:
```bash
PREFLIGHT=$(bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-preflight)
echo "$PREFLIGHT" | jq -e '.claude_p_available == true and .linear_query_works == true' >/dev/null \
  || { echo "drift-watchdog: preflight failed"; echo "$PREFLIGHT"; exit 1; }
```

Both fields must be `true`. If either fails, abort — re-running on a broken substrate would just produce errors.

### 2. Enumerate drift

```bash
DRIFT=$(bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-list)
N=$(echo "$DRIFT" | jq 'length')
if (( N == 0 )); then
  echo "drift-watchdog: no drift detected"
  exit 0
fi
```

### 3. Fetch existing watchdog issues for idempotency

Resolve `idea.list` filtered by the `drift-watchdog` label and pull the current set:

```bash
RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve idea.list --project-dir .)
EXISTING=$(eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')" \
  | jq '[.[] | select(.labels | index("drift-watchdog"))]')
```

Each existing issue's title carries the `drift_key` — used to skip duplicate creation.

### 4. Per drifted node — synthesize + create

For each entry in `$DRIFT`:

```bash
DRIFT_KEY=$(echo "$drift" | jq -r '.drift_key')
NODE_NAME=$(echo "$drift" | jq -r '.node_name')

# Idempotency check: skip if a non-terminal issue with this drift_key already exists.
DUP=$(echo "$EXISTING" | jq --arg k "$DRIFT_KEY" \
  '[.[] | select(.title | contains($k)) | select(.statusType != "canceled" and .statusType != "duplicate" and .statusType != "completed")]')
if (( $(echo "$DUP" | jq 'length') > 0 )); then
  echo "drift-watchdog: skip — existing issue for $NODE_NAME ($DRIFT_KEY)"
  continue
fi
```

Spawn the `drift-analyst` sub-agent with the drift record + recent git context + a roadmap snippet. The agent returns the issue body.

Title: `[drift-watchdog] <node_name>: <drift_key>` — the `drift_key` in the title is the dedup key. Never compose with timestamps.

Dispatch the create via http. CRITICAL EXECUTION CONTRACT — you MUST run each Bash command literally and capture its actual exit status; do not summarize the work without running it. Echo the actual stderr+stdout from each step:

```bash
RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve idea.add --project-dir .)
cmd=$(echo "$RESOLUTION" | jq -r '.invocation.command')
TITLE="[drift-watchdog] $NODE_NAME: $DRIFT_KEY"
echo "drift-watchdog: dispatching create for $NODE_NAME ($DRIFT_KEY)"
# `--labels 'idea,drift-watchdog'` overrides the resolver's default `--labels idea`
# so BOTH labels stick. linear-query.sh's --labels flag accepts a comma-separated
# string; multiple --labels invocations have last-write-wins semantics.
RESULT=$(jq -n --arg title "$TITLE" --arg description "$BODY" \
  '{title:$title, description:$description}' \
  | eval "$cmd --labels 'idea,drift-watchdog' --input-json -" 2>&1)
RC=$?
echo "drift-watchdog: linear-query.sh exit=$RC output=$RESULT"
if [[ $RC -eq 0 ]]; then
  CREATED_ID=$(echo "$RESULT" | jq -r '.id // empty')
  echo "drift-watchdog: created $CREATED_ID for $NODE_NAME ($DRIFT_KEY)"
else
  echo "drift-watchdog: create FAILED for $NODE_NAME ($DRIFT_KEY) — queueing pending"
  bash .ccanvil/scripts/docs-check.sh idea-pending-append \
    --op add --title "$TITLE" --body "$BODY"
  PENDING_N=$(bash .ccanvil/scripts/docs-check.sh idea-pending-validate | jq -r .count)
  echo "drift-watchdog: PENDING — $TITLE queued ($PENDING_N total)"
fi
```

The `drift-watchdog` label is mandatory — every issue must carry it so future runs find them. The label MUST exist in Linear before any create succeeds (one-time operator setup; the skill assumes it exists). Pending-log fallback always counts entries via `idea-pending-validate`.

### 4a. Verify create landed (BTS-200)

**do NOT report success based on the save-issue stdout alone — verify externally** by re-querying the just-created issue. This closes the agent-hallucination class of bug surfaced during BTS-21 first-kickstart, where the parent model produced a `"Drift-watchdog complete"` log claiming 7 creates with ZERO actual creates landed. The save-issue exit code is necessary but not sufficient — only `linear-query.sh get-issue` proves the issue exists with the correct shape.

Immediately after a successful save, run:

```bash
if [[ -n "$CREATED_ID" ]]; then
  VERIFY=$(bash .ccanvil/scripts/linear-query.sh get-issue "$CREATED_ID" 2>&1)
  VERIFY_RC=$?
  if (( VERIFY_RC != 0 )); then
    # Network or auth error — treat as unverified, queue to pending log.
    echo "drift-watchdog: VERIFY ERROR for $CREATED_ID (rc=$VERIFY_RC) — queueing pending"
    bash .ccanvil/scripts/docs-check.sh idea-pending-append \
      --op add --title "$TITLE" --body "$BODY"
    continue
  fi
  if ! echo "$VERIFY" | jq -e '.labels | index("drift-watchdog")' >/dev/null 2>&1; then
    # Issue exists but lacks the drift-watchdog label — same outcome as a failed create.
    echo "drift-watchdog: VERIFY FAILED for $CREATED_ID — label missing — queueing pending"
    bash .ccanvil/scripts/docs-check.sh idea-pending-append \
      --op add --title "$TITLE" --body "$BODY"
    continue
  fi
  echo "drift-watchdog: VERIFIED $CREATED_ID has drift-watchdog label"
fi
```

The verification cost is one extra `get-issue` per drifted node — negligible compared to opus orchestration cost. Failures from this path converge into the same `idea-pending-append --op add` flow as save-issue failures, so `/idea sync` replays them uniformly.

Generalizes beyond drift-watchdog: any agent-driven substrate that mutates external state should verify the mutation actually landed, not trust the agent's narrative. Anchored on BTS-200 (this protocol) and BTS-21 (origin incident).

### 5. Substrate purity

This skill MUST use the http substrate (the resolver's `linear-query.sh save-issue` invocation) for issue creation. Direct MCP tool invocations are forbidden by the drift-guards; rely on the resolver-eval pattern above (`eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"`) — that's the established shape.

## Re-running

If Claude Code is upgraded, re-run `bash .ccanvil/scripts/ccanvil-sync.sh drift-watchdog-preflight` manually before relying on the next scheduled fire — substrate breakage is cheap to verify, expensive to discover at fire time.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
