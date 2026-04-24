# Feature: Deterministic spec-epoch stamping

> Feature: bts-141-stamp-spec-epoch
> Work: linear:BTS-141
> Created: 1777072738
> Status: Complete

## Summary

The `/spec` skill currently instructs Claude to run `date +%s` and substitute the epoch into a placeholder `> Created:` line via shell-variable interpolation. This pattern silently failed once already (mid-BTS-134, the literal string `$stamp` landed in the spec frontmatter because the variable didn't expand). Per `.claude/rules/deterministic-first.md`, computable operations belong in scripts, not skill prose. Add a `stamp-spec` subcommand to `docs-check.sh` that takes a feature_id and replaces a sentinel `> Created:` line with the current epoch atomically. Update `/spec` skill step 8 to call this primitive instead of orchestrating sed.

## Job To Be Done

**When** I (Claude) write a spec via `/spec`,
**I want to** delegate the `> Created:` epoch stamping to a deterministic script call,
**So that** shell-variable interpolation footguns can never silently corrupt spec frontmatter.

## Acceptance Criteria

- [ ] **AC-1:** `docs-check.sh stamp-spec <feature_id>` exits 0 and replaces the spec's `> Created: <anything>` line with `> Created: <current epoch>`. The stamped epoch is within ±5 seconds of `date +%s` at invocation time.
- [ ] **AC-2:** When the spec file at `docs/specs/<feature_id>.md` does NOT exist, exit non-zero with a clear `ERROR: spec not found` message on stderr.
- [ ] **AC-3:** When the spec file exists but lacks any `> Created:` line, exit non-zero with `ERROR: no Created: line in <path>` — do NOT silently insert (forces the skill to write the placeholder first).
- [ ] **AC-4:** Idempotent — running twice within the same second leaves an unchanged epoch; running again seconds later updates to the new epoch (`> Created:` accepts current time, never historical).
- [ ] **AC-5:** Other metadata lines (`> Feature:`, `> Work:`, `> Status:`) are not modified by the stamp.
- [ ] **AC-6:** The stamped value is always a positive integer Unix epoch (no `$stamp` literals, no empty strings, no zero).
- [ ] **AC-7:** JSON output (default for non-TTY): `{"feature_id":"<id>","stamped_epoch":<num>,"file":"docs/specs/<id>.md"}` on success.
- [ ] **AC-8:** `/spec` skill prose (`.claude/skills/spec/SKILL.md`) step 8 explicitly references `docs-check.sh stamp-spec <feature_id>` and removes the `date +%s` mention from the metadata-write instruction.
- [ ] **AC-9:** Hub test asserts the skill prose contains the new subcommand reference (drift guard).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `cmd_stamp_spec` and dispatch entry |
| `.claude/skills/spec/SKILL.md` | Modified — step 8 references `stamp-spec` instead of `date +%s` |
| `hub/tests/stamp-spec.bats` | New — 7 cases asserting AC-1..AC-7 |
| `hub/tests/skills-prose.bats` (or stasis-recall.bats) | Add 1 case for AC-9 (drift guard) |

## Dependencies

- **Requires:** Existing `docs-check.sh` infrastructure (`cmd_activate`, `cmd_complete` patterns).
- **Blocked by:** Nothing.

## Out of Scope

- Auto-detecting `> Created:` line absence and inserting (would mask skill-prose drift; AC-3 explicitly errors instead).
- Stamping the entire metadata block (Feature/Work/Status); spec author writes those, only Created is auto-derived.
- Updating downstream skills (`/plan`, `/stasis`) — those use their own `> Created:` paths handled separately if needed.

## Implementation Notes

- Bug origin: `/spec` skill step 8 (current text): "Set metadata: ... `> Created: <epoch>` (via `date +%s`) ...". The skill leaves orchestration to Claude, which sometimes succeeds (BTS-133) and sometimes fails silently (BTS-134).
- Helper shape: `cmd_stamp_spec()` — takes feature_id, computes `epoch=$(date +%s)`, sed-replaces `> Created:` line, emits JSON envelope on stdout.
- Use `sed -i ''` (BSD/macOS); script is bash 3.2 compat already.
- AC-3's strict no-insert behavior makes the skill's contract explicit: skill prose must write a `> Created:` placeholder first, then call stamp-spec. This forces the skill update.
- Strict-mode `set -e` per `.claude/rules/tdd.md`.
