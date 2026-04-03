# Implementation Plan: ccanvil Rename and Reorganization

> Feature: ccanvil-reorg
> Created: 1775250270
> Spec hash: 67c5d912
> Based on: docs/spec.md

## Objective

Reorganize the hub repo into `preset/` (distributable) and `hub/` (development-only) directories, namespace preset infrastructure under `.ccanvil/`, rename all scaffold terminology to ccanvil, and strip framework-specific opinions from distributed config.

## Design Decision: Hub Path Mapping

The core challenge is that the hub needs to *use* the same scripts it *distributes*. After the reorg:
- Hub stores distributable scripts at `preset/.ccanvil/scripts/`
- Downstream projects have them at `.ccanvil/scripts/`

**Solution: symlink at hub root.** The hub gets `.ccanvil/ → preset/.ccanvil/` so that `.ccanvil/scripts/ccanvil-sync.sh` resolves in both hub and downstream. All `.claude/` commands/hooks reference `.ccanvil/scripts/` paths — works everywhere.

**Two .claude/ directories:**
- `preset/.claude/` — framework-agnostic (distributed to projects, no bats/tls)
- Root `.claude/` — hub-specific (has bats permissions, tls rule, hub-only hooks)

**Sync script change:** The sync engine compares `preset/.claude/` and `preset/.ccanvil/` in the hub against `.claude/` and `.ccanvil/` in downstream. The lockfile records the hub's `preset/` prefix; the sync script strips it when comparing.

## Sequence

### Step 1: Create hub/ directory — isolate hub-only artifacts (AC-4)

- **Test:** Write bats test: `hub/ directory exists and contains tests/, specs/, research/, meta/`. Verify `tests/scaffold-sync.bats` still loadable from new location.
- **Implement:** `mkdir -p hub/{tests,specs,research,meta}`. Move:
  - `tests/*.bats` → `hub/tests/`
  - `docs/specs/*.md` → `hub/specs/`
  - `docs/research/*.md` → `hub/research/`
  - `INIT_PROMPT.md`, `HOW_TO_USE.md`, `SCAFFOLD_SYSTEM_PROMPT.md`, `GLOBAL_CLAUDE.md` → `hub/meta/`
- **Files:** All files in `tests/`, `docs/specs/`, `docs/research/`, plus 4 meta-docs
- **Verify:** `bats hub/tests/` runs (may fail on path refs — that's expected, fixed in Step 9)

### Step 2: Create preset/ directory — distributable artifacts (AC-3, AC-5)

- **Test:** Write bats test: `preset/ exists with expected subdirectory structure`. Verify no file outside `preset/` is referenced by the init command.
- **Implement:** Create directory structure:
  ```
  preset/
  ├── .claude/          (copy from root .claude/, minus hub-specific files)
  ├── .ccanvil/
  │   ├── scripts/      (move from scripts/)
  │   ├── guide/        (move from docs/scaffold-guide/)
  │   └── templates/    (move from docs/templates/)
  ├── CLAUDE.md         (copy from root, will be made generic in Step 5)
  └── .claudeignore     (copy from root)
  ```
  Create symlink: `.ccanvil → preset/.ccanvil` at hub root.
- **Files:** All distributable artifacts
- **Verify:** `ls -la .ccanvil/scripts/` resolves via symlink

### Step 3: Rename scaffold-sync.sh → ccanvil-sync.sh (AC-2)

- **Test:** Write bats test: `.ccanvil/scripts/ccanvil-sync.sh` exists and is executable. Old path `scripts/scaffold-sync.sh` does not exist.
- **Implement:** Rename the script file. Update the shebang/header comments. Update internal self-references (e.g., usage strings, error messages that mention the script name).
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh` (was `scripts/scaffold-sync.sh`)
- **Verify:** `bash -n .ccanvil/scripts/ccanvil-sync.sh` passes syntax check

### Step 4: Rename /scaffold-* commands → /ccanvil-* (AC-1, AC-2)

- **Test:** Verify no `.claude/commands/scaffold-*.md` files exist. Verify all `/ccanvil-*` command files exist.
- **Implement:** Rename command files:
  - `scaffold-status.md` → `ccanvil-status.md`
  - `scaffold-pull.md` → `ccanvil-pull.md`
  - `scaffold-push.md` → `ccanvil-push.md`
  - `scaffold-promote.md` → `ccanvil-promote.md`
  - `scaffold-demote.md` → `ccanvil-demote.md`
  - `scaffold-audit.md` → `ccanvil-audit.md`
  - `scaffold-ignore.md` → `ccanvil-ignore.md`
  Update content in each to reference `ccanvil-sync.sh` and `.ccanvil/` paths. Do this in both `preset/.claude/commands/` (distributed) and root `.claude/commands/` (hub).
- **Files:** 7+ command files × 2 locations
- **Verify:** `ls preset/.claude/commands/ccanvil-*.md` shows all renamed files

### Step 5: Strip framework opinions from preset config (AC-11, AC-12, AC-13, AC-14, AC-15)

- **Test:** Write bats tests:
  - `preset/.claude/settings.json` does NOT contain `bats`
  - `preset/.claude/rules/tls-troubleshooting.md` does NOT exist
  - `preset/CLAUDE.md` does NOT mention `bats-core` in hub-managed sections
  - TDD rule and skill reference generic "project's test command"
- **Implement:**
  - Remove `Bash(bats:*)` from `preset/.claude/settings.json`
  - Delete `preset/.claude/rules/tls-troubleshooting.md`
  - Make `preset/CLAUDE.md` template's Tech Stack and Commands sections NODE-SPECIFIC placeholders
  - Verify `.claude/skills/tdd/SKILL.md` already uses `$TEST_COMMAND` (it does — no change needed)
  - Update CI template (`docs/templates/github/ci.yml` if it exists) to use generic test command placeholder
- **Files:** `preset/.claude/settings.json`, `preset/.claude/rules/`, `preset/CLAUDE.md`, CI template
- **Verify:** Bats tests for AC-11 through AC-15 pass

### Step 6: Update lockfile location and sync patterns (AC-16)

- **Test:** Write bats test: `ccanvil-sync.sh init` creates lockfile at `.ccanvil/ccanvil.lock` (not `.claude/scaffold.lock`). Tracked patterns include `.ccanvil/scripts/*.sh`, `.ccanvil/guide/*.md`, `.ccanvil/templates/*.md`.
- **Implement:** In `ccanvil-sync.sh`:
  - Change `LOCKFILE` path from `.claude/scaffold.lock` to `.ccanvil/ccanvil.lock`
  - Update `TRACKED_PATTERNS` array:
    ```
    .claude/rules/*.md
    .claude/commands/*.md
    .claude/agents/*.md
    .claude/skills/*/SKILL.md
    .claude/hooks/*.sh
    .claude/settings.json
    .claude/scaffold.json
    .ccanvil/templates/*.md
    .ccanvil/scripts/*.sh
    .ccanvil/guide/*.md
    CLAUDE.md
    ```
  - Update `EXCLUDED_FILES` to exclude `.ccanvil/ccanvil.lock`
  - Add hub-path mapping: when hub is detected (presence of `preset/`), prefix tracked patterns with `preset/` for hub-side comparison
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** `ccanvil-sync.sh init` in a test project creates `.ccanvil/ccanvil.lock`

### Step 7: Update hub path mapping in sync engine (AC-16, AC-17, AC-18)

- **Test:** Write bats test: `ccanvil-sync.sh pull-plan` correctly maps `preset/.claude/rules/tdd.md` in hub to `.claude/rules/tdd.md` in downstream. Test that `ccanvil-sync.sh status` shows correct provenance.
- **Implement:** Add `hub_to_local_path()` and `local_to_hub_path()` helper functions in `ccanvil-sync.sh`. The sync engine detects hub mode (the hub has `preset/` dir) and applies the mapping. Lockfile `scaffold_source` becomes `ccanvil_source`.
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Bats tests for sync path mapping pass

### Step 8: Update commands and hooks for new paths (AC-17, AC-18)

- **Test:** Grep all `.claude/commands/` and `.claude/hooks/` files for old paths (`scripts/scaffold-sync.sh`, `scripts/docs-check.sh`, `docs/scaffold-guide/`). Verify zero matches.
- **Implement:** Update all path references in:
  - `preset/.claude/commands/*.md` — script paths to `.ccanvil/scripts/`
  - `preset/.claude/hooks/*.sh` — script paths to `.ccanvil/scripts/`
  - Root `.claude/commands/*.md` — same (hub uses symlink)
  - Root `.claude/hooks/*.sh` — same
  - Root `.claude/settings.json` — update permission allowlists for new script paths, keep bats
  - `preset/.claude/settings.json` — update permission allowlists, no bats
- **Files:** All command, hook, and settings files in both locations
- **Verify:** `grep -r 'scripts/scaffold-sync' preset/.claude/ .claude/` returns nothing

### Step 9: Update init command (AC-3, AC-5, AC-6, AC-7, AC-8, AC-9, AC-10)

- **Test:** Write bats test simulating `/init` in a temp directory. Verify:
  - `.ccanvil/scripts/` exists with scripts
  - `.ccanvil/guide/` exists with guide docs
  - `.ccanvil/templates/` exists with templates
  - `docs/` contains zero preset artifacts
  - Project root has only `CLAUDE.md`, `.claudeignore`, `.claude/`, `.ccanvil/`
  - No file was copied from outside `preset/`
- **Implement:** Rewrite `global-commands/init.md` and `~/.claude/commands/init.md`:
  - Read `preset/` structure
  - Copy `preset/.claude/` → `.claude/`
  - Copy `preset/.ccanvil/` → `.ccanvil/`
  - Copy `preset/CLAUDE.md` → `CLAUDE.md`
  - Copy `preset/.claudeignore` → `.claudeignore`
  - Run `.ccanvil/scripts/ccanvil-sync.sh init ~/projects/ccanvil`
  - Create `docs/` with project-owned placeholders (spec.md, plan.md, checkpoint.md from templates)
- **Files:** `global-commands/init.md`, `~/.claude/commands/init.md`
- **Verify:** Init simulation test passes all AC-6 through AC-10 checks

### Step 10: Update hub's own CLAUDE.md and root config (AC-1, AC-20)

- **Test:** Verify root `CLAUDE.md` mentions `bats` in Tech Stack. Verify it describes the new repo layout (`preset/`, `hub/`, `.ccanvil/`). Verify it does NOT use "scaffold" as a project name.
- **Implement:**
  - Rewrite root `CLAUDE.md` Architecture section to describe `preset/`, `hub/`, `.ccanvil/` structure
  - Keep bats in Tech Stack and Commands
  - Update all test commands: `bats hub/tests/` instead of `bats tests/`
  - Rename remaining "scaffold" project-name references to "ccanvil" (preserve "scaffold" only as a technical verb for the syncing concept where appropriate)
  - Update `README.md` file manifest tables
- **Files:** Root `CLAUDE.md`, `README.md`
- **Verify:** `grep -c 'bats' CLAUDE.md` > 0; no "scaffold" as project name

### Step 11: Update all tests for new paths (AC-19)

- **Test:** `bats hub/tests/` — all tests pass.
- **Implement:** Update every `.bats` file in `hub/tests/`:
  - Script paths: `scripts/scaffold-sync.sh` → `.ccanvil/scripts/ccanvil-sync.sh`
  - Docs paths: `docs/scaffold-guide/` → `.ccanvil/guide/`
  - Template paths: `docs/templates/` → `.ccanvil/templates/`
  - Lockfile paths: `.claude/scaffold.lock` → `.ccanvil/ccanvil.lock`
  - Test helper setup functions that create temp directories need updated structure
  - `scripts/docs-check.sh` → `.ccanvil/scripts/docs-check.sh`
  - `scripts/operations.sh` → `.ccanvil/scripts/operations.sh`
  - Other script references
- **Files:** All 11 `.bats` files in `hub/tests/`
- **Verify:** `bats hub/tests/` exits 0

### Step 12: Update documentation (scaffold-guide → .ccanvil/guide)

- **Test:** Verify `preset/.ccanvil/guide/index.md` exists and references correct paths. Verify no guide file references old paths.
- **Implement:** Update all guide docs in `preset/.ccanvil/guide/`:
  - `index.md` — update table of contents, file paths, architecture diagrams
  - `scaffold-sync.md` → `ccanvil-sync.md` — update mermaid diagrams, command names, paths
  - `configuration.md` — update lockfile location, config paths
  - `hooks.md` — update hook script paths
  - All other guide files — search-and-replace path references
  - `scaffold-framework.md` — leave as-is (research source material, not a path reference doc)
- **Files:** All files in `preset/.ccanvil/guide/`
- **Verify:** `grep -r 'scripts/scaffold-sync' preset/.ccanvil/guide/` returns nothing

### Step 13: Clean up deprecated paths and full verification

- **Test:** Full verification sweep:
  - `bats hub/tests/` — all pass (AC-19)
  - No `scripts/` directory at root (moved to preset)
  - No `docs/scaffold-guide/` at root (moved to preset)
  - No `docs/templates/` at root (moved to preset)
  - No `.claude/scaffold.lock` at root (moved to .ccanvil/)
  - `.ccanvil` symlink resolves correctly
  - `grep -r 'scaffold-sync\.sh' .claude/ preset/.claude/` returns nothing
- **Implement:** Remove any leftover stubs, dead symlinks, or empty directories from the move operations. Verify `.claudeignore` excludes new paths appropriately (e.g., `hub/tests/` fixtures). Update `.gitignore` if needed.
- **Files:** Root directory cleanup
- **Verify:** `git status` shows only expected changes; `bats hub/tests/` all pass

## Risks

- **Path mapping complexity:** The hub-vs-downstream path divergence (`preset/.ccanvil/` vs `.ccanvil/`) is the highest-risk area. The symlink approach is simple but must be tested on both macOS and CI. Mitigation: Step 2 creates symlink early; if it causes issues, fall back to duplicating scripts.
- **Sync script self-bootstrapping:** `ccanvil-sync.sh pull-auto` may try to update itself during a pull. The existing `pre-check` command handles bootstrap sync — verify it works with the new path. Mitigation: Step 6 tests this explicitly.
- **Two .claude/ directories:** Hub developers must understand that root `.claude/` is hub-only and `preset/.claude/` is what gets distributed. Risk of editing the wrong one. Mitigation: Step 10 documents this clearly in root CLAUDE.md.
- **Test count regression:** With 352 tests, mass path updates in Step 11 could introduce typos. Mitigation: Use deterministic sed replacements and verify count matches before/after.
- **Downstream breakage:** fucina and luxlook still reference old paths. Out of scope, but note that the next sync attempt from those projects will fail until manually migrated.

## Definition of Done

- [ ] All acceptance criteria from spec pass (AC-1 through AC-20)
- [ ] All existing tests still pass (`bats hub/tests/`)
- [ ] Code reviewed (run /review)
- [ ] Hub root CLAUDE.md updated with new architecture
- [ ] README file manifest updated

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
