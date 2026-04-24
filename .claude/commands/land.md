Return the working tree to main after a PR merge, then auto-close the linked Linear issue.

`/land` is the canonical post-merge step. It wraps `docs-check.sh land` (git mechanics) and follows up by dispatching the AUTO-CLOSE intent the script emits for the just-landed spec — transitioning the linked Linear issue to `Done` via the BTS-128 `ticket.transition` primitive. On MCP failure, the transition is queued to `.ccanvil/ideas-pending.log` for `/idea sync` to replay — auto-close NEVER blocks the merge cleanup.

## Steps

1. Run `bash .ccanvil/scripts/docs-check.sh land` and capture its stdout.
2. Grep the captured stdout for a line matching `^AUTO-CLOSE: `. If none, you're done — just print the script's output and exit.
3. If a marker line is present, extract the JSON payload (everything after `AUTO-CLOSE: `). Parse `provider`, `id`, and `role`.
4. If `provider != "linear"`: this should not happen (the script only emits the marker for `linear:`), but be defensive — log `auto-close: unexpected provider '<p>' — skipping` and exit 0 without dispatching.
5. Resolve the transition intent:
   ```bash
   bash .ccanvil/scripts/operations.sh resolve ticket.transition <id> <role> --project-dir .
   ```
   The resolver returns `.invocation.tool` (`mcp__claude_ai_Linear__save_issue`) and `.invocation.params` (`{id, stateId}`).
6. Dispatch the MCP call with the resolved params. The tool is `mcp__claude_ai_Linear__save_issue`; pass `id` and `stateId` from `.invocation.params`.
7. **On MCP success:** echo `Auto-closed <id> → Done`. Done.
8. **On MCP failure** (network/auth/server error): append one JSONL line to `.ccanvil/ideas-pending.log`:
   ```bash
   echo '{"op":"ticket.transition","args":{"id":"<id>","role":"<role>"},"ts":'"$(date +%s)"'}' \
     >> .ccanvil/ideas-pending.log
   ```
   Echo `PENDING: auto-close queued for /idea sync`. Exit 0 — auto-close failure NEVER blocks the post-merge cleanup.

## Idempotency

If the Linear issue is already in `Done` (e.g. manually transitioned, or replayed from an earlier pending-log entry), Linear's `save_issue` accepts the transition without error. No duplicate handling needed on the client side.

## Rules

- `/land` is the post-merge canonical flow. Users who run `docs-check.sh land` directly bypass the MCP dispatch — the `AUTO-CLOSE: {...}` marker prints on stdout, but nothing parses it, nothing writes to the pending log, and nothing transitions the issue. In that case the Linear issue stays open and must be closed manually (via `/idea triage`, direct `ticket.transition <id> done`, or the Linear UI).
- `/land` NEVER fails the land step because of MCP/Linear errors — the pending-log fallback guarantees forward progress.
- When no AUTO-CLOSE marker is emitted (legacy spec, local provider, non-claude branch, etc.), `/land` is a transparent passthrough over `docs-check.sh land`.
- **Known gap:** if the user has already switched to main (e.g. after `gh pr merge --squash --delete-branch` which switches + deletes in one step) before invoking `/land`, `cmd_land`'s "already on main" early-return path runs the fast-forward but skips the branch-regex safety net, so no AUTO-CLOSE marker is emitted and no auto-close fires. Workaround: run `/land` from the feature branch BEFORE `gh pr merge` switches you to main. A future ship can add squash-commit-subject parsing to recover the feature-id on the already-on-main path.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
