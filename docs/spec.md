# Feature: Guide Directory Restructuring

> Feature: guide-restructuring
> Created: 1774505200
> Status: In Progress

## Summary

Split the monolithic GUIDE.md (45.5k chars) into a `docs/guide/` directory with separate section files, remove the duplicate Appendix, and relocate SCAFFOLD_FRAMEWORK.md into `docs/guide/`. This eliminates the file size hook block, enables progressive disclosure (only relevant sections loaded), and organizes all scaffold reference material under one directory.

## Job To Be Done

**When** I need to read or edit scaffold documentation,
**I want to** access only the relevant section without loading 45k chars,
**So that** context budget is preserved and the file size hook no longer blocks edits.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `GUIDE.md` no longer exists at repository root
- [ ] **AC-2:** `docs/guide/index.md` exists with a table linking to all section files, and is under 4k chars
- [ ] **AC-3:** Each section from the original GUIDE.md exists as a separate file in `docs/guide/` with its full content preserved (minus Appendix)
- [ ] **AC-4:** The Appendix ("Why Each Practice Exists") section is not present in any `docs/guide/` file — it duplicates SCAFFOLD_FRAMEWORK.md
- [ ] **AC-5:** `SCAFFOLD_FRAMEWORK.md` no longer exists at repository root; `docs/guide/scaffold-framework.md` contains identical content
- [ ] **AC-6:** `CLAUDE.md` references `docs/guide/index.md` (not `@GUIDE.md`) in its Reference Documents section
- [ ] **AC-7:** `scripts/scaffold-sync.sh` TRACKED_PATTERNS references `docs/guide/*.md` instead of `GUIDE.md` and `SCAFFOLD_FRAMEWORK.md`
- [ ] **AC-8:** `.claude/hooks/lint-on-write.sh` ALWAYS_LOADED_PATTERNS includes `docs/guide/index.md` instead of `GUIDE.md`
- [ ] **AC-9:** `.claude/hooks/protect-files.sh` blocks writes to `docs/guide/scaffold-framework.md` (not root `SCAFFOLD_FRAMEWORK.md`)
- [ ] **AC-10:** `scripts/security-audit.sh` whitelist references `docs/guide/scaffold-framework.md`
- [ ] **AC-11:** Each `docs/guide/*.md` file (except scaffold-framework.md) has a `<!-- NODE-SPECIFIC-START -->` delimiter
- [ ] **AC-12:** All existing tests pass (updated for new paths where needed)
- [ ] **AC-13:** `.claude/rules/*.md`, `.claude/commands/plan.md`, `global-commands/init.md`, and `docs/templates/hooks-reference.md` reference the new paths

## Affected Files

| File | Change |
|------|--------|
| `GUIDE.md` | Deleted — content split into docs/guide/ |
| `SCAFFOLD_FRAMEWORK.md` | Moved to `docs/guide/scaffold-framework.md` |
| `docs/guide/index.md` | New — TOC + system overview |
| `docs/guide/getting-started.md` | New — first-time setup |
| `docs/guide/core-workflow.md` | New — spec/plan/build/review + TDD cycle |
| `docs/guide/session-management.md` | New — catchup/checkpoint/clear |
| `docs/guide/scaffold-sync.md` | New — hub/node architecture, pull/push flows |
| `docs/guide/command-reference.md` | New — all command tables |
| `docs/guide/configuration.md` | New — config layers, what goes where |
| `docs/guide/hooks.md` | New — hooks system, deterministic-first, adding hooks |
| `docs/guide/decision-guide.md` | New — when to use what |
| `docs/guide/parallel-sessions.md` | New — worktree usage |
| `docs/guide/scaffold-framework.md` | New (moved from root) |
| `CLAUDE.md` | Modified — update reference |
| `scripts/scaffold-sync.sh` | Modified — update TRACKED_PATTERNS |
| `.claude/hooks/lint-on-write.sh` | Modified — update ALWAYS_LOADED_PATTERNS |
| `.claude/hooks/protect-files.sh` | Modified — update blocked path |
| `scripts/security-audit.sh` | Modified — update whitelist |
| `.claude/rules/workflow.md` | Modified — update GUIDE.md reference |
| `.claude/rules/code-quality.md` | Modified — update SCAFFOLD_FRAMEWORK.md reference |
| `.claude/rules/deterministic-first.md` | Modified — update reference if present |
| `.claude/commands/plan.md` | Modified — update GUIDE.md references |
| `global-commands/init.md` | Modified — update file list |
| `docs/templates/hooks-reference.md` | Modified — update SCAFFOLD_FRAMEWORK.md reference |
| `.claude/manifest.lock` | Modified — update entries |
| `tests/scaffold-sync.bats` | Modified — update test fixtures |
| `tests/operations.bats` | Modified — update path references |
| `tests/docs-check.bats` | Modified — update GUIDE variable |

## Dependencies

- **Requires:** None
- **Blocked by:** None

## Out of Scope

- Converting GUIDE.md content to a skill (wrong abstraction — it's reference, not a workflow)
- Changing scaffold-sync.sh to support directory-level merge (per-file tracking with existing glob patterns is sufficient)
- Rewriting GUIDE.md content (preserve as-is, just split)
- Changing the `@` import semantics in Claude Code itself

## Implementation Notes

- Split boundaries follow existing `##` headings — each top-level section becomes its own file
- `docs/guide/index.md` should contain the intro paragraph, system overview diagram, and a table of sections with file paths and "when to read" guidance
- scaffold-sync.sh change is minimal: replace two literal entries in TRACKED_PATTERNS with one glob `"docs/guide/*.md"`
- SCAFFOLD_FRAMEWORK.md keeps its existing protection (hook block) — just update the path match
- The `<!-- NODE-SPECIFIC-START -->` delimiter goes at the end of each section file, same pattern as rules/commands/agents
- scaffold-framework.md does NOT get a delimiter (it's whole-file auto-update, read-only research)
- Tests that create GUIDE.md in temp directories need path updates but logic stays the same

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
