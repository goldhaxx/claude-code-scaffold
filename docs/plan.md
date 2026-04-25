# Implementation Plan: Interactive Permissions Review at Session Boundaries

> Feature: bts-149-interactive-permissions-review
> Work: linear:BTS-149
> Created: 1777091544
> Spec hash: 4cacafe7
> Based on: docs/spec.md

## Objective

Close the autonomy-first permissions design loop with: (a) `permissions-audit.sh apply --decisions` substrate for atomic mutations, (b) `/permissions-review` skill orchestrating per-row Q&A, (c) session-boundary surfacing in `/stasis` + `/recall`, AND (d) refine BTS-148's pre-enqueue pattern to enqueue-on-failure-only — eliminating success-path write+ack churn.

## Sequence

### Step 1: AC-10/12 — Remove pre-enqueue from `cmd_auto_transition_emit`
- **Test:** Update `hub/tests/auto-transition-emit.bats` cases that assert pending-log entry creation. Flip them to assert NO entry is added. Add new regression: direct `docs-check.sh activate` produces marker but writes nothing to pending log.
- **Implement:** Delete the `cmd_idea_pending_append --op ticket.transition ...` call from `cmd_auto_transition_emit` (`.ccanvil/scripts/docs-check.sh:1198`). Replace the BTS-148 comment block with a BTS-149 comment explaining failure-only enqueue.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/auto-transition-emit.bats`.
- **Verify:** `bats hub/tests/auto-transition-emit.bats` green; full suite green.

### Step 2: AC-11 — Update `/activate` skill prose
- **Test:** Manual review of skill prose for: (a) no ack-with-jq-pipeline section; (b) on success no further action; (c) on failure call `idea-pending-append`.
- **Implement:** Edit `.claude/commands/activate.md` to remove the "Acking the right entry" section and step 7's ack flow. Replace step 8 with: on MCP failure, `bash .ccanvil/scripts/docs-check.sh idea-pending-append --op ticket.transition --id <id> --role <role>` then echo `PENDING: ...`.
- **Files:** `.claude/commands/activate.md`.
- **Verify:** Walk through the skill mentally with both success and failure paths — no jq pipeline, no ack call.

### Step 3: AC-1/2/4 — Apply scaffolding with atomicity
- **Test:** New bats cases in `hub/tests/permissions-audit.bats`: (a) `apply --decisions <empty-file>` exits 0 with `{applied:0, skipped:0, errors:[]}`; (b) malformed JSONL → exit 2; (c) unknown decision verb → exit 2; (d) `.bak` files created before any mutation and removed on success; (e) simulated mid-stream failure restores from `.bak` and exits 3.
- **Implement:** Add `cmd_apply` function to `.ccanvil/scripts/permissions-audit.sh`. JSONL line-by-line parsing via `while read`. Validate `.decision` against known set (`delete|promote|keep-local|accept-danger`) — unknown → emit error envelope, exit 2. Backup `settings.json` and `settings.local.json` to `.bak` BEFORE any iteration. Trap on ERR to restore from `.bak` and exit 3. On success, `rm` the `.bak` files. Output `{applied, skipped, errors}` JSON envelope. Add `apply)` to dispatch case.
- **Files:** `.ccanvil/scripts/permissions-audit.sh`, `hub/tests/permissions-audit.bats`.
- **Verify:** Empty/malformed/unknown-decision tests green; backup/restore behavior correct under simulated failure.

### Step 4: AC-3 (delete) — Implement `delete` decision
- **Test:** New bats cases: (a) decision `{permission: "Bash(rm:*)", decision: "delete"}` removes that entry from `settings.local.json` allow list; (b) decision targeting an entry NOT in `settings.local.json` is a no-op (counted in `skipped`); (c) `applied` counter increments correctly.
- **Implement:** In `cmd_apply`'s decision dispatch, `delete` case: `jq --arg p "$perm" '.permissions.allow |= map(select(. != $p))' settings.local.json > tmp && mv tmp settings.local.json`. Increment counter.
- **Files:** `.ccanvil/scripts/permissions-audit.sh`, `hub/tests/permissions-audit.bats`.
- **Verify:** Bats cases green; running `apply` against the real two `ALLOW_OUTSIDE_WORKSPACE=1` settings.local.json entries (in test fixture form) yields a clean settings.local.json.

### Step 5: AC-3 (promote + keep-local) — Implement remaining mutation verbs
- **Test:** New bats cases: (a) `promote` of a permission appends to `settings.json` allow list AND removes from `settings.local.json` (atomic across both files); (b) `promote` is idempotent if already in `settings.json` (no double-append); (c) `keep-local` is a no-op, increments `skipped` counter, leaves both files untouched.
- **Implement:** Two new dispatch branches: `promote` (jq append to settings.json + remove from settings.local.json), `keep-local` (no file ops, skipped++).
- **Files:** `.ccanvil/scripts/permissions-audit.sh`, `hub/tests/permissions-audit.bats`.
- **Verify:** Bats cases green; cross-file mutation atomicity holds (both files restored together on simulated failure).

### Step 6: AC-3 (accept-danger) + AC-5 — Implement log-entry write decision
- **Test:** New bats cases: (a) `accept-danger` with all 4 fields (`risk`, `rationale`, `efficiency_justification`, `reviewer`) populated writes log entry with `accept_danger:true` to `.claude/permissions-audit.log.json`; (b) any missing/empty/`"TODO"` field → exit 2 with clear error, no mutation; (c) subsequent `permissions-audit.sh check` reclassifies the entry as REVIEWED (risk-accepted), validating end-to-end roundtrip.
- **Implement:** `accept-danger` branch validates 4 fields via jq; on success, jq-merges `{[$perm]: {risk, rationale, efficiency_justification, reviewer, accept_danger: true}}` into `.entries` of the log file. Validation failure emits error envelope with field name, exit 2.
- **Files:** `.ccanvil/scripts/permissions-audit.sh`, `hub/tests/permissions-audit.bats`.
- **Verify:** Bats green; integration test: write log entry, run `check`, observe REVIEWED with `risk_accepted:true`.

### Step 7: AC-6 — `/stasis` synthesis surfacing
- **Test:** Manual: re-read updated `.claude/skills/stasis/SKILL.md`. Verify (a) data gathering step calls both `check` and `promote-review`; (b) synthesis includes `## Permissions Review Pending` block conditional on `total + danger > 0`; (c) when 0, section omitted.
- **Implement:** Edit `.claude/skills/stasis/SKILL.md` step 7 to add `permissions-audit.sh promote-review --json` alongside the existing check call. Add a synthesis section template after `## Cross-Session Patterns` documenting the conditional `## Permissions Review Pending`. Wording: lists candidates with recommendation + reason, points to `/permissions-review`.
- **Files:** `.claude/skills/stasis/SKILL.md`.
- **Verify:** Skill prose review; if running `/stasis` post-implementation, verify the section appears (real settings.local.json carryover gives 2 candidates).

### Step 8: AC-7 — `/recall` orientation nudge
- **Test:** Manual: re-read `.claude/skills/recall/SKILL.md`. Verify the orientation block adds the conditional one-liner.
- **Implement:** Edit `.claude/skills/recall/SKILL.md` data gathering to include `permissions-audit.sh check --json` and `promote-review --json`. In the briefing, add: when `(check.danger + promote-review.counts.total) > 0`, print `**Permissions Review:** N candidates pending — run /permissions-review`. Silent when 0.
- **Files:** `.claude/skills/recall/SKILL.md`.
- **Verify:** Skill prose review; running `/recall` shows the line when fixtures have candidates.

### Step 9: AC-8 + AC-9 — `/permissions-review` skill prose
- **Test:** Manual review of new skill file for: (a) gather phase calls both scripts and parses JSON; (b) for-each-candidate Q&A loop with terse 4-line presentation per row (permission, recommendation, reason, prompt); (c) DANGER-without-accept_danger branch prompts for 4 fields; (d) decisions accumulated as JSONL string then written to tmpfile; (e) dispatch via `apply --decisions`; (f) summary echo of `{applied, skipped, errors}`; (g) no-candidates path exits with `No candidates to review.`
- **Implement:** Create `.claude/commands/permissions-review.md` from scratch. Structure: data gathering, Q&A loop (per-row), decisions accumulation, dispatch, summary. Prose tone matches `/idea triage` (terse, agentic).
- **Files:** `.claude/commands/permissions-review.md` (new).
- **Verify:** Skill prose self-consistent with apply contract; manual walkthrough of empty/non-empty paths.

### Step 10: Documentation
- **Test:** Manual review of guide changes against the new surface area.
- **Implement:** Update `.ccanvil/guide/command-reference.md` (hub section above `<!-- NODE-SPECIFIC-START -->`): (a) add `apply --decisions <jsonl-file>` row to permissions-audit.sh table; (b) add `/permissions-review` row to skills table; (c) note BTS-149 in /activate's row about removed pre-enqueue. Per `.claude/rules/workflow.md`, this is hub-wide.
- **Files:** `.ccanvil/guide/command-reference.md`.
- **Verify:** Final `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green; `.ccanvil/scripts/docs-check.sh validate` — aligned.

## Risks

- **Atomicity edge case:** if `apply` is interrupted between writing settings.json and writing settings.local.json (a `promote` mid-stream crash with no backup yet), one file could persist a partial change. Mitigation: backup BOTH files before iterating; ERR trap restores BOTH from backup; the trap fires before any per-decision writes complete.
- **Backup file collision:** if a previous `apply` failed and left `.bak` files, a new `apply` would overwrite. Mitigation: detect existing `.bak` at start, refuse with clear error message ("recovery files present from previous failed apply — investigate or remove manually"). Belt-and-suspenders against silent corruption.
- **JSONL with embedded permissions containing newlines:** edge case where a permission string has `\n`. JSONL line-by-line read would split it. Mitigation: tests cover this; if found, fall back to `jq -c -s` array parse. Likely won't occur in practice (permissions are single-line strings).
- **`/permissions-review` invoked mid-feature with dirty working tree:** mutations to settings files would mix with feature commits. Mitigation: skill prose recommends running on `main` (post-/land) or asks for confirmation otherwise. Not enforced — this is judgment, not validation.
- **BTS-148 refinement breaks downstream nodes already running BTS-148:** post-pull, downstream `/activate` skills will skip the ack call. Mitigation: idempotency on Linear side handles already-transitioned states; pending log entries from old BTS-148 invocations drain via `/idea sync` regardless.

## Definition of Done

- [ ] All 12 acceptance criteria from spec pass
- [ ] All existing tests still pass (1080 → ~1095, +12-15 from new bats cases)
- [ ] `permissions-audit.sh apply --decisions` self-validated against the 2 stale `ALLOW_OUTSIDE_WORKSPACE=1` settings.local.json entries (delete decision)
- [ ] `/permissions-review` walked through end-to-end at least once on real fixtures
- [ ] `/activate` skill validated by next activate (BTS-149 itself, post-merge → next feature)
- [ ] Code reviewed (run `/review`)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
