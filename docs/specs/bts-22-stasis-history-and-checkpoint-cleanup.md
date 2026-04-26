# Feature: stasis history directory + checkpoint cleanup

> Feature: bts-22-stasis-history-and-checkpoint-cleanup
> Work: linear:BTS-22
> Created: 1777220407
> Status: Complete

## Summary

Persist per-session stasis files in `docs/sessions/<epoch>-<feature_id>.md` so `/recall` and `/stasis` can read recent N sessions without git archeology, and verify checkpoint legacy is fully archived (no active producers remain). The original BTS-22 framing (multi-file specs/plans/checkpoints) is largely superseded — `docs/specs/` already holds 100 archive files, Linear is the canonical backlog (BTS-164/166/175), and substrate primitives are densely coupled to single-file `docs/spec.md`. The residual real concern is stasis history: today every `/stasis` overwrites `docs/stasis.md` and prior sessions are accessible only via `git show HEAD~N:docs/stasis.md`.

## Job To Be Done

**When** I run `/stasis` or `/recall` and want to see cross-session patterns or review recent narrative,
**I want to** read recent stasis files directly from `docs/sessions/` without walking git history,
**So that** `/recall` cross-session pattern detection (BTS-115's neighbour) is fast, deterministic, and includes more than just the immediately-prior session.

## Acceptance Criteria

- [ ] **AC-1:** New `docs-check.sh archive-stasis` subcommand copies `docs/stasis.md` → `docs/sessions/<epoch>-<feature_id>.md` where `<epoch>` is the `> Last updated:` value (or `> Created:`) and `<feature_id>` is the `> Feature:` value from the live stasis. Emits `{archived: true, path: "docs/sessions/<file>"}` JSON. Idempotent: if the destination exists with byte-identical content, emits `{archived: false, path: "<file>", reason: "already-archived"}` and exits 0.
- [ ] **AC-2:** Filename collision with non-identical content → non-zero exit with `{error: "collision", existing: "<path>"}` JSON to stderr. Operator decides whether to manually resolve.
- [ ] **AC-3:** Missing `docs/stasis.md` or missing `> Feature:`/`> Last updated:` metadata → non-zero exit with a clear stderr error, no `docs/sessions/` write.
- [ ] **AC-4:** `/stasis` skill invokes `archive-stasis` automatically AFTER the live `docs/stasis.md` is committed, then commits the archived copy in a follow-up commit (or amends — pick one in plan; amending may run afoul of `feedback_*` rules, so prefer a follow-up commit). Drift-guard: bats test asserts the skill prose references `archive-stasis` after the stasis commit step.
- [ ] **AC-5:** `cmd_complete` and `cmd_land` do NOT touch `docs/sessions/` — those files are the persistent archive. Drift-guard: bats test asserts neither function references `docs/sessions/`.
- [ ] **AC-6:** `cmd_validate` ignores `docs/sessions/*.md` for alignment checks. Adding archived sessions never changes the validate result. Drift-guard: bats test creates a fixture `docs/sessions/` directory with stale-shaped files and asserts validate still emits `aligned`/`no-active-spec` based only on the live triplet.
- [ ] **AC-7:** New `docs-check.sh sessions-list [--limit N]` subcommand emits `[{path, epoch, feature_id, kind}, ...]` JSON sorted newest-first. Default limit 10. Reads frontmatter metadata from each file in `docs/sessions/`; skips malformed files with a stderr warning.
- [ ] **AC-8:** `/recall` skill is updated to read up to 3 most-recent `docs/sessions/*.md` files via `sessions-list --limit 3` for the cross-session-pattern step, replacing the `git show HEAD~1:docs/stasis.md` archeology. Falls back to git when `docs/sessions/` is empty (first stasis on a node).
- [ ] **AC-9 (checkpoint cleanup):** Drift-guard bats test asserts no active producer of `docs/checkpoint.md` exists in `.claude/skills/`, `.claude/commands/`, `.claude/rules/`, or `.ccanvil/scripts/` — excluding two intentional legacy guards: `cmd_legacy_refs_scan` pattern in `docs-check.sh` (defensive scan) and `cmd_migrate_stasis_artifact` in `ccanvil-sync.sh` (one-time downstream migration helper).
- [ ] **AC-10:** `CLAUDE.md` `## Architecture` section is updated to list `docs/sessions/` (one-line entry: `docs/sessions/             # Per-session stasis archive (committed history)`). Drift-guard: bats test grep-checks the line exists.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Add `cmd_archive_stasis`, `cmd_sessions_list`, dispatcher cases |
| `.claude/skills/stasis/SKILL.md` | Add archive-stasis step after the commit step |
| `.claude/skills/recall/SKILL.md` | Replace `git show HEAD~1` step with `sessions-list --limit 3` read |
| `CLAUDE.md` | Add `docs/sessions/` line under `## Architecture` |
| `hub/tests/stasis-history.bats` | New — covers AC-1..AC-3, AC-7, drift-guards for AC-4, AC-5, AC-9, AC-10 |
| `hub/tests/stasis-history-validate.bats` | New — covers AC-6 isolation guarantee |
| `docs/sessions/.gitkeep` | New — ensure the directory exists in fresh clones |

## Dependencies

- **Requires:** none. Builds on existing `cmd_status` metadata-reading, `cmd_validate` lifecycle checks, and the BTS-130 `> Feature:`/`> Last updated:` metadata convention.
- **Blocked by:** nothing.

## Out of Scope

- **Backfilling historical stases from git into `docs/sessions/`.** Forward-only ship: new sessions write to `docs/sessions/`; older history stays in `git log`. Backfill can ship as a separate ticket if `/recall` needs deeper coverage.
- **Multi-file specs / multi-file plans.** The original BTS-22 framing for these is superseded — `docs/specs/` already holds 100 archive files, specs are small (max 141 LOC), and substrate is densely coupled to single-file `docs/spec.md` (14 consumers, 18 references in `docs-check.sh` alone). Refactoring to multi-file would be a substrate-wide rewrite with no observed pain. Capture as a separate research ticket if pain emerges.
- **Removing `cmd_migrate_stasis_artifact` from `ccanvil-sync.sh`.** Downstream nodes may still rely on it. Defer to a separate cleanup ticket gated on a downstream survey.
- **Removing checkpoint references from `cmd_legacy_refs_scan` pattern.** The pattern is a positive defensive guard against backsliding — keeping it costs nothing and preserves the safety net.
- **Stasis-content schema evolution.** This ticket only changes the storage layout, not the document structure.

## Implementation Notes

- Filename: `docs/sessions/<epoch>-<feature_id>.md`. Example: `docs/sessions/1777218200-session-2026-04-26-determinism-trifecta-ship.md`. Sort order is naturally chronological (epoch prefix). Filename collision is impossible within one second on the same feature_id, so AC-2's collision case fires only on truly degenerate double-calls.
- `archive-stasis` reads metadata via the same `> Feature:` / `> Last updated:` regexes used by `cmd_status`. Reuse that path; do not re-parse.
- `sessions-list` should `find docs/sessions -name '*.md' -maxdepth 1` and parse metadata via the same helpers. Sort by epoch descending. Limit caps the output.
- Pattern to follow: same shape as `cmd_idea_pending_replay` (BTS-179) — small focused function, JSON envelope output, errors to stderr with non-zero exit.
- `/stasis` skill flow: after the `ALLOW_MAIN=1 git commit -m "docs: stasis ..."` step, run `archive-stasis`, stage the new file, commit in a follow-up `chore(stasis-archive): persist <feature_id>` commit. Two commits per stasis is acceptable — the second is mechanical and non-functional.
- `/recall` skill flow: replace step 11 (`git show HEAD~1:docs/stasis.md`) with `sessions-list --limit 3` and read each path. Pass them to the cross-session-pattern synthesis step (BTS-115's neighbour). Fallback: when `docs/sessions/` is empty, fall back to the git-show path so first-time users on fresh nodes don't break.
- Validate isolation (AC-6) is critical: any `find` / glob in `cmd_validate` must scope to the live triplet (`docs/spec.md`, `docs/plan.md`, `docs/stasis.md`) and ignore `docs/sessions/`. Easiest path: don't change validate at all — its current logic already references the triplet by exact path, not by directory scan. The drift-guard test verifies this assumption holds going forward.
- Live-validation gate (BTS-171): no live-API calls in this ship. All file operations are deterministic.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
