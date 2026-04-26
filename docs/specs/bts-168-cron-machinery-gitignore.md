# Feature: gitignore Claude Code scheduled-task artifacts

> Feature: bts-168-cron-machinery-gitignore
> Work: linear:BTS-168
> Created: 1777164729
> Status: Complete

## Summary

Claude Code's `/loop` and `/schedule` features emit ephemeral `.claude/scheduled_tasks*` artifacts inside the project root. These are session-local — they don't survive `/compact` reliably and don't represent committable state — yet they pollute git status across multiple stases. Gitignore them and document the boundary so operators (and future automation) understand: ccanvil does not provide a durable cron substrate; Claude Code's scheduled-task feature is session-scoped, and recurring work that needs to survive boundaries should be tracked in Linear/the backlog instead.

## Job To Be Done

**When** Claude Code creates `.claude/scheduled_tasks*` artifacts during a session,
**I want to** have them automatically excluded from git status and never committed,
**So that** they don't appear in `/stasis` snapshots, /pr cleanup checks, or commit drafts as untracked-file noise.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.gitignore` (and the project template equivalent if one exists) contains a `.claude/scheduled_tasks*` entry that excludes both `.claude/scheduled_tasks` (file) and `.claude/scheduled_tasks/` (directory) and any `.claude/scheduled_tasks_*` variants Claude Code may emit.
- [ ] **AC-2:** A bats test simulates the artifact (creates `.claude/scheduled_tasks/sentinel`) and confirms `git status --porcelain` does not list it.
- [ ] **AC-3:** Running `bash .ccanvil/scripts/security-audit.sh --files-only` after creating the artifact still passes (no untracked-file complaint, no PII/secret findings since the artifact is git-ignored).
- [ ] **AC-4 (docs):** `.ccanvil/guide/command-reference.md` (or whichever guide section covers Claude Code integration) documents the boundary: Claude Code's scheduled-tasks are session-scoped and gitignored; ccanvil does not provide a durable cron substrate; recurring work that must survive sessions belongs in Linear/the idea queue.
- [ ] **AC-5 (template propagation):** If `.ccanvil/templates/.gitignore` (or equivalent project-init template) exists and serves as the source-of-truth for downstream node `.gitignore` files, the same entry is added there so new `/init`'d projects pick it up.

## Affected Files

| File | Change |
|------|--------|
| `.gitignore` | Modified — add `.claude/scheduled_tasks*` (or appropriate glob). |
| `.ccanvil/templates/.gitignore` (if present) | Modified — same entry for template propagation. |
| `hub/tests/<existing>.bats` | Modified or new — bats test asserting the gitignore entry suppresses the artifact from `git status`. |
| `.ccanvil/guide/command-reference.md` | Modified — short note on the boundary. |

## Dependencies

- **Requires:** none.
- **Blocked by:** none.

## Out of Scope

- Building a durable cron substrate inside ccanvil (would need a real scheduler — out of scope; flag if it surfaces as a real need rather than a noted gap).
- Migrating any pre-existing scheduled-task artifacts that may exist in downstream nodes — operator's choice; the gitignore takes effect from now on.
- Documenting Claude Code's `/loop` / `/schedule` features themselves (not ccanvil's surface).

## Implementation Notes

- **Gitignore glob:** `.claude/scheduled_tasks*` matches both `scheduled_tasks` (bare file/dir) and `scheduled_tasks_*` variants. Use a single line to keep the pattern simple. Trailing slash NOT needed — git's gitignore matches both files and directories with the same pattern when no trailing `/`.
- **Test pattern:** mirror the existing `.gitignore` tests (e.g., the ones that assert `.ccanvil/ideas.log` is ignored). Create the artifact in a tmp git repo, run `git status --porcelain`, assert empty (or assert `scheduled_tasks` not in the output).
- **Template propagation:** if `.ccanvil/templates/.gitignore` doesn't exist as a template source, this is a single-file change; if it does, the entry needs to be in both. Verify at implementation time.
- **Documentation tone:** terse — one line in the guide noting the boundary. Don't expand into explaining Claude Code's scheduled-task semantics.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
