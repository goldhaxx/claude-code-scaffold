# Implementation Plan: Guide Directory Restructuring

> Feature: guide-restructuring
> Created: 1774505400
> Spec hash: 8bf23e80
> Based on: docs/spec.md

## Objective

Split GUIDE.md into `docs/guide/` directory, remove the duplicate Appendix, and move SCAFFOLD_FRAMEWORK.md into `docs/guide/`. Update all references, hooks, scripts, and tests.

## Sequence

### Step 1: Create docs/guide/ directory and split GUIDE.md (AC-1, AC-2, AC-3, AC-4)
- **Test:** Verify `docs/guide/index.md` exists and is under 4k chars; verify each section file exists with correct content; verify Appendix is absent; verify `GUIDE.md` no longer exists at root
- **Implement:** Split GUIDE.md at `##` heading boundaries into separate files. Index gets the intro + system overview + TOC table. Appendix is dropped entirely. Each file gets `<!-- NODE-SPECIFIC-START -->` delimiter (AC-11).
- **Files:** `GUIDE.md` (delete), `docs/guide/index.md`, `docs/guide/getting-started.md`, `docs/guide/core-workflow.md`, `docs/guide/session-management.md`, `docs/guide/scaffold-sync.md`, `docs/guide/command-reference.md`, `docs/guide/configuration.md`, `docs/guide/hooks.md`, `docs/guide/decision-guide.md`, `docs/guide/parallel-sessions.md`
- **Verify:** `ls docs/guide/`, `wc -c docs/guide/index.md`, `! test -f GUIDE.md`

### Step 2: Move SCAFFOLD_FRAMEWORK.md (AC-5)
- **Test:** Verify `docs/guide/scaffold-framework.md` exists with identical content; verify root `SCAFFOLD_FRAMEWORK.md` is gone
- **Implement:** `git mv SCAFFOLD_FRAMEWORK.md docs/guide/scaffold-framework.md`
- **Files:** `SCAFFOLD_FRAMEWORK.md` (moved to `docs/guide/scaffold-framework.md`)
- **Verify:** `diff` original vs moved (should be identical), `! test -f SCAFFOLD_FRAMEWORK.md`

### Step 3: Update CLAUDE.md reference (AC-6)
- **Test:** Verify CLAUDE.md references `docs/guide/index.md` and does not reference `@GUIDE.md` or `SCAFFOLD_FRAMEWORK.md` (at root)
- **Implement:** Update Reference Documents section — change `@GUIDE.md` to `docs/guide/index.md`, update SCAFFOLD_FRAMEWORK.md reference to new path, update the "Do Not" section
- **Files:** `CLAUDE.md`
- **Verify:** `grep -c '@GUIDE.md' CLAUDE.md` returns 0

### Step 4: Update scaffold-sync.sh TRACKED_PATTERNS (AC-7)
- **Test:** Write bats test: given hub with `docs/guide/*.md` files and node with same, `pull-plan` correctly identifies them as tracked files
- **Implement:** Replace `"GUIDE.md"` and `"SCAFFOLD_FRAMEWORK.md"` entries in TRACKED_PATTERNS with `"docs/guide/*.md"`
- **Files:** `scripts/scaffold-sync.sh`
- **Verify:** `bats tests/scaffold-sync.bats`

### Step 5: Update hooks — lint-on-write.sh and protect-files.sh (AC-8, AC-9)
- **Test:** Write bats test: lint-on-write enforces 40k limit on `docs/guide/index.md`; protect-files blocks writes to `docs/guide/scaffold-framework.md`
- **Implement:** Update ALWAYS_LOADED_PATTERNS in `lint-on-write.sh` (replace `GUIDE.md` with `docs/guide/index.md`). Update case pattern in `protect-files.sh` (match `scaffold-framework.md` basename or full path).
- **Files:** `.claude/hooks/lint-on-write.sh`, `.claude/hooks/protect-files.sh`
- **Verify:** Echo test JSON through hooks, check exit codes

### Step 6: Update security-audit.sh whitelist (AC-10)
- **Test:** Verify `docs/guide/scaffold-framework.md` is in the whitelist
- **Implement:** Update WHITELIST entry from `SCAFFOLD_FRAMEWORK.md` to `docs/guide/scaffold-framework.md`
- **Files:** `scripts/security-audit.sh`
- **Verify:** `bats tests/security-audit.bats`

### Step 7: Update all remaining references (AC-13)
- **Implement:** Update references in:
  - `.claude/rules/workflow.md` — GUIDE.md → docs/guide/ references
  - `.claude/rules/code-quality.md` — SCAFFOLD_FRAMEWORK.md → new path
  - `.claude/rules/deterministic-first.md` — if references exist
  - `.claude/commands/plan.md` — GUIDE.md → docs/guide/ references
  - `global-commands/init.md` — update file list
  - `docs/templates/hooks-reference.md` — SCAFFOLD_FRAMEWORK.md → new path
- **Files:** All files listed above
- **Verify:** `grep -r 'GUIDE\.md' --include='*.md' .claude/ global-commands/` returns no hits for root GUIDE.md; `grep -r 'SCAFFOLD_FRAMEWORK\.md' --include='*.md' .claude/` returns no root-path hits

### Step 8: Update tests (AC-12)
- **Test:** All existing tests pass with new paths
- **Implement:** Update test fixtures in `tests/scaffold-sync.bats`, `tests/operations.bats`, `tests/docs-check.bats` to use `docs/guide/` paths instead of root `GUIDE.md` / `SCAFFOLD_FRAMEWORK.md`
- **Files:** `tests/scaffold-sync.bats`, `tests/operations.bats`, `tests/docs-check.bats`
- **Verify:** `bats tests/`

### Step 9: Update manifest.lock
- **Implement:** Remove old `GUIDE.md` entry, run `manifest-check.sh verify` on new paths
- **Files:** `.claude/manifest.lock`
- **Verify:** `bash scripts/manifest-check.sh hash-check`

## Risks

- **Cross-references within GUIDE.md sections:** Internal anchor links (`#section-name`) will break across files. Mitigation: replace with file-path references in the index.
- **Test fixture complexity:** scaffold-sync.bats creates mock hub/node structures. Changing from single file to directory requires updating multiple test helpers. Mitigation: update systematically, run after each change.
- **Self-referential content in GUIDE.md:** The Scaffold Sync section documents GUIDE.md's own sync behavior. After the split, `docs/guide/scaffold-sync.md` must document its own sync behavior (docs/guide/*.md). Update the diagrams and tables.

## Definition of Done

- [ ] All 13 acceptance criteria from spec pass
- [ ] All existing tests still pass
- [ ] No type errors
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
