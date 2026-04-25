# Feature: Interactive Permissions Review at Session Boundaries

> Feature: bts-149-interactive-permissions-review
> Work: linear:BTS-149
> Created: 1777090148
> Status: Complete

## Summary

BTS-143 (`accept_danger` override) and BTS-144 (`promote-review` classifier) shipped the deterministic substrate for permissions review but stopped short of the interactive layer. The classifier outputs are silent — they never reach the user unless they manually run the script — and there is no agent-reachable path to mutate `settings.json` / `settings.local.json` from the recommendations. BTS-149 closes the loop with four additions: surface pending review state at `/stasis` + `/recall`, a new `/permissions-review` skill that walks the user through per-row Q&A, a `permissions-audit.sh apply --decisions <jsonl>` substrate that performs the actual mutations atomically, AND refines BTS-148's pre-enqueue pattern to enqueue-on-failure-only (eliminates write+ack churn on every activate).

Same shape as `/idea triage` + `idea-update`: skill orchestrates the agentic Q&A, script performs deterministic mutations from a decisions JSONL.

## Job To Be Done

**When** I finish a session and broad wildcards have accumulated in `settings.local.json` or DANGER entries lack rationales,
**I want to** be prompted at session boundaries with the candidate list and walked through per-row decisions interactively,
**So that** stale staging entries get cleaned up deterministically, broad wildcards get reviewed and either promoted with rationale or dropped, and no permission ever mutates without my explicit confirmation.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Substrate (script-level — bats)

- [ ] **AC-1:** `permissions-audit.sh apply --decisions <jsonl-file>` accepts a JSONL stream of decision records and mutates `settings.json` + `settings.local.json` per the decisions. Exits 0 on success with a JSON summary of `{applied: N, skipped: N, errors: []}`.
- [ ] **AC-2:** Decision contract: each line is `{permission: string, decision: "delete|promote|keep-local|accept-danger", rationale?: string, risk?: string, efficiency_justification?: string, reviewer?: string}`. Unknown decision values cause apply to fail with exit 2 and a clear error envelope; no partial mutation.
- [ ] **AC-3:** `delete` removes the entry from `settings.local.json` allow list. `promote` appends to `settings.json` allow list AND removes from `settings.local.json`. `keep-local` is a no-op (counted as `skipped`). `accept-danger` writes the log entry to `.claude/permissions-audit.log.json` with `accept_danger:true` + the four required fields (`risk`, `rationale`, `efficiency_justification`, `reviewer`).
- [ ] **AC-4:** Atomicity — apply backs up both settings files (`.bak` suffix) before any write. If any mutation fails mid-stream, both files are restored from backup and exit code is 3. On full success, backups are removed.
- [ ] **AC-5:** `accept-danger` decision validates that all four required fields (`risk`, `rationale`, `efficiency_justification`, `reviewer`) are non-empty and not `"TODO"`. Missing fields → exit 2 (validation error), no mutation.

### Session-boundary surfacing (skill-prose)

- [ ] **AC-6:** `/stasis` synthesis includes a `## Permissions Review Pending` section when EITHER `permissions-audit.sh promote-review --json | .counts.total > 0` OR `permissions-audit.sh check --json | .danger > 0`. Section lists candidates and recommended decisions. When both counts are 0, the section is omitted (no noise).
- [ ] **AC-7:** `/recall` orientation includes a one-line nudge `N permissions-review candidates pending — run /permissions-review` when `total + danger > 0`. Silent when 0.

### Interactive skill

- [ ] **AC-8:** `.claude/commands/permissions-review.md` exists. Skill prose: (1) calls `permissions-audit.sh promote-review --json` + `permissions-audit.sh check --json`, (2) for each promote-review candidate prompts user with permission, recommendation, reason and asks for `approve | keep-local | triage` decision; (3) for each DANGER entry without `accept_danger:true` prompts user to write the four required fields or skip; (4) collects all decisions into a JSONL string; (5) dispatches `permissions-audit.sh apply --decisions <tmpfile>`; (6) reports `{applied, skipped, errors}` summary.
- [ ] **AC-9:** When called with no candidates (both counts 0), `/permissions-review` exits silently with `No candidates to review.` Idempotent — running twice in a row is a no-op.

### BTS-148 substrate refinement (enqueue-on-failure-only)

- [ ] **AC-10:** `cmd_auto_transition_emit` in `.ccanvil/scripts/docs-check.sh` no longer enqueues to `.ccanvil/ideas-pending.log`. Sole side effect is emitting the `AUTO-TRANSITION: {...}` marker on stdout.
- [ ] **AC-11:** `/activate` skill prose updated: on MCP success, no ack required (nothing to ack). On MCP failure, skill calls `bash .ccanvil/scripts/docs-check.sh idea-pending-append --op ticket.transition --id <id> --role <role>` to enqueue. The ack-with-jq-pipeline pattern is removed entirely.
- [ ] **AC-12:** Existing `auto-transition-emit.bats` cases updated to assert NO entry is written to pending log on emit (was: assert ONE entry). New regression case: direct `docs-check.sh activate` invocation produces marker but writes nothing to pending log.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Add `cmd_apply` function + `apply` dispatch case |
| `.ccanvil/scripts/docs-check.sh` | Remove `cmd_idea_pending_append` call from `cmd_auto_transition_emit` (AC-10) |
| `hub/tests/permissions-audit.bats` | New test cases (AC-1..AC-5) |
| `hub/tests/auto-transition-emit.bats` | Update existing cases for AC-10/12 |
| `.claude/commands/permissions-review.md` | New skill prose (AC-8, AC-9) |
| `.claude/commands/activate.md` | Remove ack-on-success path; add enqueue-on-failure path (AC-11) |
| `.claude/skills/stasis/SKILL.md` | Step 7 + synthesis section addition (AC-6) |
| `.claude/skills/recall/SKILL.md` | Orientation nudge addition (AC-7) |
| `.ccanvil/guide/command-reference.md` | Document `apply` subcommand + `/permissions-review` skill |

## Dependencies

- **Requires:** BTS-143 (accept_danger override path), BTS-144 (promote-review classifier) — both Complete.
- **Blocked by:** none.

## Out of Scope

- Auto-invocation of `/permissions-review` from `/stasis` or `/recall` — surfacing only; user opts in to the interactive walkthrough.
- Multi-file or per-project overlay rules — apply only mutates `settings.json` and `settings.local.json` in `.claude/`.
- Editing existing log entries — `apply` only appends new `accept_danger:true` entries; updating an existing rationale stays manual.
- TRIAGE-promoted entries with rationales added to `settings.json` — `promote` decision appends the bare permission only; rationale flows to log via separate `accept-danger` decision if needed.
- Applying the same enqueue-on-failure refinement to `/land`'s AUTO-CLOSE path (BTS-119). Same anti-pattern likely exists there but is out of scope for this ship — capture as a follow-up if confirmed.

## Implementation Notes

- Pattern: same shape as `cmd_promote_review` (deterministic substrate) + `/idea triage` skill (per-row Q&A + decisions dispatch). Apply is the third pillar — actual mutations from decisions.
- Backup mechanism: `cp settings.json settings.json.bak; cp settings.local.json settings.local.json.bak` before any write. On `set -e` trap or error path, `mv` the .bak back. On success, `rm` the .bak files.
- JSONL parsing: read line-by-line via `while IFS= read -r line`, parse with `jq -c -r '.permission'`, validate decision via `case` statement.
- Settings mutation: use `jq --arg p "$perm" '.permissions.allow |= map(select(. != $p))'` to remove; `jq --arg p "$perm" '.permissions.allow += [$p]'` to append. Write back atomically via tmpfile + `mv`.
- Skill prose tone: terse Q&A. For each row print 3 lines (permission, recommendation, reason) and one prompt line. No verbose preambles.
- Pending-log fallback: out of scope for this ship — apply runs locally on settings files, no MCP path. If apply fails partway, the user gets a clear restoration message and can re-run.
- Strict-mode bats tests (BTS-127): use `set -e` in any test with multiple `jq -e` assertions.
- BTS-148 refinement rationale: pre-enqueue + ack-on-success was belt-and-suspenders for crash safety + direct-script-bypass durability. In practice, ~99% success rate makes the success-path write+ack pure churn. Ack also forces an inline jq pipeline (Claude reconstructing predicate args) — a determinism anti-pattern. Failure-only enqueue uses the existing `idea-pending-append` helper (BTS-123) and is strictly cleaner. Idempotency on Linear's side means duplicate transitions aren't dangerous; pending entries surviving past direct invocation are not worth the everyday cost.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
