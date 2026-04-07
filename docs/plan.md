# Implementation Plan: Eradicate "scaffold" terminology

> Feature: scaffold-terminology-eradication
> Created: 1775491798
> Spec hash: 7e97bfa6
> Based on: docs/spec.md

## Objective

Remove every remaining use of "scaffold" from the ccanvil hub, preset, and downstream projects — replacing with clear, consistent terminology (hub, preset, node) — so the system is self-documenting and free of legacy naming confusion.

## Scope Summary

~815 occurrences across 81+ files. Four risk tiers:
- **High risk:** Lockfile schema, jq queries, function names in ccanvil-sync.sh (runtime behavior)
- **Medium risk:** Config file renames (scaffold.json → ccanvil.json), TRACKED_PATTERNS, supporting scripts
- **Low risk:** Guide/template file renames, documentation content
- **Trivial:** Comments, help text, hub meta docs, downstream sweep

## Sequence

### Step 1: Lockfile key renames in ccanvil-sync.sh (AC-4, AC-5)
- **Test:** Update `scaffold-sync.bats` assertions — change `scaffold_source` → `hub_source`, `scaffold_version` → `hub_version`, `scaffold_hash` → `hub_hash`, status `scaffold-only` → `hub-only`, origin `"scaffold"` → `"hub"`. Confirm tests fail.
- **Implement:** Update all jq queries in `ccanvil-sync.sh` that read/write these lockfile keys. Key functions: `cmd_init`, `cmd_status`, `cmd_pull_plan`, `cmd_pull_apply`, `cmd_lock_add`, `cmd_lock_set_version`, `get_scaffold_source_raw`, `get_scaffold_source_display`. ~30 jq query edits.
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/scaffold-sync.bats`
- **Verify:** `bats hub/tests/scaffold-sync.bats` — all passing. Run `ccanvil-sync.sh init` in a temp dir and verify lockfile has new keys.

### Step 2: Function renames in ccanvil-sync.sh (AC-6)
- **Test:** Update any test helpers or assertions that reference old function names (if tests call functions directly via `source`). Confirm failures.
- **Implement:** Rename all 6 scaffold-named functions:
  - `get_scaffold_source_raw()` → `get_hub_source_raw()`
  - `get_scaffold_source()` → `get_hub_source()`
  - `get_scaffold_source_display()` → `get_hub_source_display()`
  - `scaffold_dist_root()` → `hub_dist_root()`
  - `scan_scaffold_files()` → `scan_hub_files()`
  - `merge_scaffold_config()` → `merge_config()` (if defined here; otherwise AC-8)
  - Update all call sites within the same file.
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/scaffold-sync.bats`
- **Verify:** `bats hub/tests/scaffold-sync.bats`

### Step 3: Variable renames in ccanvil-sync.sh (AC-7)
- **Test:** Tests should already pass after step 2 since variables are internal. This step is refactor-only (green→green).
- **Implement:** Rename all 12 scaffold-prefixed variable names:
  - `$scaffold_source` → `$hub_source`, `$scaffold_hub` → `$hub_root`, `$scaffold_version` → `$hub_version`, `$scaffold_file` → `$hub_file`, `$scaffold_path` → `$hub_path`, `$scaffold_h` → `$hub_h`, `$scaffold_hash` → `$hub_hash`, `$scaffold_changed` → `$hub_changed`, `$new_scaffold_hash` → `$new_hub_hash`, `$new_scaffold_h` → `$new_hub_h`, `$scaffold_only` (count var) → `$hub_only`
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** `bats hub/tests/scaffold-sync.bats`

### Step 4: Action value and string literals in ccanvil-sync.sh (AC-5 partial)
- **Test:** Update `scaffold-sync.bats` assertions for action name `take-scaffold` → `take-hub` and any output-matching assertions (e.g., "took scaffold" → "took hub", "Scaffold:" → "Hub:" in status output).
- **Implement:** Update action values, output strings, help text, and commit message templates in ccanvil-sync.sh:
  - Action: `take-scaffold` → `take-hub`
  - Output: "Scaffold: ..." → "Hub: ...", "Scaffold-only:" → "Hub-only:"
  - Help: "SCAFFOLD-ONLY=not yet pulled" → "HUB-ONLY=not yet pulled"
  - Commit messages: `chore(scaffold): pull from hub` → `chore(sync): pull from hub`
  - Comments: ~80 occurrences — bulk update "scaffold" → "hub"/"preset" depending on context
- **Files:** `preset/.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/scaffold-sync.bats`
- **Verify:** `bats hub/tests/scaffold-sync.bats`

### Step 5: Config file rename — scaffold.json → ccanvil.json (AC-1, AC-2, AC-3)
- **Test:** Update `scaffold-json-override.bats` to reference `ccanvil.json` / `ccanvil.local.json`. Update `feature-lifecycle.bats` (`scaffold-config` function refs). Update `operations.bats`. Confirm failures.
- **Implement:**
  - Rename `preset/.claude/scaffold.json` → `preset/.claude/ccanvil.json`
  - Update `TRACKED_PATTERNS` in ccanvil-sync.sh: `.claude/scaffold.json` → `.claude/ccanvil.json`
  - Update `operations.sh`: rename `merge_scaffold_config()` → `merge_config()`, update all `.claude/scaffold.json` and `.claude/scaffold.local.json` path references (AC-8)
  - Update `docs-check.sh`: rename `merge_scaffold_config()` → `merge_config()`, update path refs (AC-9)
  - Rename template `preset/.ccanvil/templates/scaffold.json.md` → `ccanvil.json.md` (AC-3)
  - Update `.claudeignore` (preset + hub root): `scaffold.local.json` → `ccanvil.local.json`, `scaffold.lock` → `ccanvil.lock`
  - Update `.gitignore` if applicable
- **Files:** `preset/.claude/scaffold.json`, `preset/.ccanvil/scripts/ccanvil-sync.sh`, `preset/.ccanvil/scripts/operations.sh`, `preset/.ccanvil/scripts/docs-check.sh`, `preset/.ccanvil/templates/scaffold.json.md`, `preset/.claudeignore`, `.claudeignore`, `hub/tests/scaffold-json-override.bats`, `hub/tests/operations.bats`, `hub/tests/feature-lifecycle.bats`
- **Verify:** `bats hub/tests/` — full suite

### Step 6: security-audit.sh + context-budget.sh (AC-10, AC-11)
- **Test:** Run `bats hub/tests/security-audit.bats` as baseline. If tests reference `scaffold-framework.md`, update.
- **Implement:**
  - `security-audit.sh` line 63: update allowlist entry `scaffold-framework.md` → `foundations.md`
  - `context-budget.sh`: update header comment if it mentions "scaffold files" → "preset files"
- **Files:** `preset/.ccanvil/scripts/security-audit.sh`, `preset/.ccanvil/scripts/context-budget.sh`
- **Verify:** `bats hub/tests/security-audit.bats` and `bats hub/tests/context-budget.bats`

### Step 7: Test file renames (AC-20, AC-21)
- **Test:** Verify `bats hub/tests/` still discovers renamed files.
- **Implement:**
  - `git mv hub/tests/scaffold-sync.bats hub/tests/ccanvil-sync.bats`
  - `git mv hub/tests/scaffold-json-override.bats hub/tests/ccanvil-json-override.bats`
  - Update any cross-references between test files (e.g., if one sources helpers from another by name)
  - Update hub `CLAUDE.md` test commands section if it lists these filenames
- **Files:** `hub/tests/scaffold-sync.bats`, `hub/tests/scaffold-json-override.bats`, `CLAUDE.md`
- **Verify:** `bats hub/tests/` — full suite

### Step 8: Guide file renames + content (AC-12, AC-13)
- **Test:** No bats tests for guide content. Verify by grep sweep.
- **Implement:**
  - `git mv preset/.ccanvil/guide/scaffold-sync.md preset/.ccanvil/guide/sync.md` — update all internal links in `index.md` and cross-references in other guide files
  - `git mv preset/.ccanvil/guide/scaffold-framework.md preset/.ccanvil/guide/foundations.md` — careful content edit: "structured scaffolding" → "structured configuration", "scaffold system" → "preset system" / "ccanvil". This is a **judgment call** step — not blind find-replace. The practitioner quote and research citations need contextual rewording.
  - Sweep all 11 guide files: replace "scaffold hub" → "hub", "from the scaffold" → "from the hub", "scaffold automation" → "preset automation"
  - Update protection rules that reference `scaffold-framework.md`: `code-quality.md`, hooks config
- **Files:** All `preset/.ccanvil/guide/*.md` (12 files), `preset/.claude/rules/code-quality.md`, hook configs referencing the filename
- **Verify:** `grep -ri scaffold preset/.ccanvil/guide/` returns 0 hits. `bats hub/tests/` still passes.

### Step 9: Templates — delimiter comments + content (AC-14)
- **Test:** No bats tests for template content. Verify by grep.
- **Implement:**
  - All 6 template files: `/scaffold-pull` → `/ccanvil-pull` in delimiter comments
  - `ccanvil.json.md` (renamed in step 5): update internal content references
  - `hooks-reference.md` template: update `scaffold-framework.md` → `foundations.md`
- **Files:** All `preset/.ccanvil/templates/*.md`
- **Verify:** `grep -ri scaffold preset/.ccanvil/templates/` returns 0 hits

### Step 10: Commands, agents, rules, skills (AC-16, AC-17, AC-18, AC-19)
- **Test:** No bats tests for command content. Verify by grep.
- **Implement:**
  - `ccanvil-differ.md`: change `name: scaffold-differ` → `name: ccanvil-differ`, update all internal "scaffold" → "hub"
  - All 7 `/ccanvil-*` command files: "scaffold hub" → "hub", "from the scaffold" → "from the hub", "take scaffold" → "take hub"
  - `pr.md`: `scaffold.json` → `ccanvil.json`
  - `plan.md` command: update guide reference if it mentions `scaffold-sync.md`
  - Rules: `deterministic-first.md`, `workflow.md`, `code-quality.md`, `self-review.md` — update any remaining "scaffold" refs
  - Skills: `tdd/SKILL.md` — `/scaffold-pull` → `/ccanvil-pull` delimiter
- **Files:** `preset/.claude/agents/ccanvil-differ.md`, all `preset/.claude/commands/*.md`, all `preset/.claude/rules/*.md`, `preset/.claude/skills/tdd/SKILL.md`
- **Verify:** `grep -ri scaffold preset/.claude/` returns 0 hits (excluding `scaffold.lock` pattern if still in ignore files)

### Step 11: Preset CLAUDE.md + hub root files (AC-15, AC-22, AC-23)
- **Test:** No bats tests. Verify by grep.
- **Implement:**
  - `preset/CLAUDE.md`: update architecture diagram (`scaffold.json` → `ccanvil.json`, `scaffold.local.json` → `ccanvil.local.json`), update "Do Not" section (`scaffold-framework.md` → `foundations.md`)
  - Hub root `CLAUDE.md`: update test command filenames, any "scaffold" terminology
  - Hub root `README.md`: comprehensive sweep (~83 occurrences) — "scaffold" → "hub"/"preset"/"ccanvil" depending on context. This is a **judgment call** — README describes the system architecture, so replacements are contextual.
  - Hub root `.claudeignore`: update file references
- **Files:** `preset/CLAUDE.md`, `CLAUDE.md`, `README.md`, `.claudeignore`
- **Verify:** `grep -ri scaffold` at repo root (excluding `.git/`) returns 0 hits in these files

### Step 12: Hub meta + specs (AC-22 continued)
- **Test:** No bats tests. Verify by grep.
- **Implement:**
  - `hub/meta/SCAFFOLD_SYSTEM_PROMPT.md`: rename file to `hub/meta/SYSTEM_PROMPT.md` (or `CCANVIL_SYSTEM_PROMPT.md`), update ~50 "scaffold" references — this is another **judgment call** (prompt rewriting)
  - `hub/meta/INIT_PROMPT.md`: ~5 references
  - `hub/meta/HOW_TO_USE.md`: ~10 references
  - `hub/specs/*.md`: update completed specs with new terminology (low priority, historical)
- **Files:** All `hub/meta/*.md`, `hub/specs/*.md`
- **Verify:** `grep -ri scaffold hub/` returns 0 hits (excluding git history)

### Step 13: Downstream projects (AC-24, AC-25)
- **Test:** After updates, `grep -ri scaffold ~/projects/fucina` and `grep -ri scaffold ~/projects/luxlook` return 0 hits.
- **Implement:**
  - For each project: rename `.claude/scaffold.json` → `.claude/ccanvil.json`, update `.claudeignore`, `.gitignore`, sweep all `.ccanvil/` and `.claude/` files for remaining "scaffold" refs
  - Re-init lockfiles with `ccanvil-sync.sh init` (new lockfile keys)
  - Commit in each downstream project
- **Files:** All scaffold-referencing files in `~/projects/fucina/` and `~/projects/luxlook/`
- **Verify:** Grep sweep returns 0 hits per project

### Step 14: Final verification (AC-26, AC-27)
- **Test:** Full test suite + comprehensive grep sweep.
- **Implement:** Fix any remaining occurrences found by sweep.
- **Files:** Any stragglers
- **Verify:**
  - `bats hub/tests/` — all 352+ tests pass
  - `grep -ri scaffold --include='*.sh' --include='*.bats' --include='*.md' --include='*.json' .` returns 0 hits (excluding `.git/`, this spec, and historical specs in `hub/specs/`)
  - `ccanvil-sync.sh init` in a temp dir produces lockfile with `hub_source`, `hub_version`, `hub_hash` keys

### Step 15: Update guide documentation
- **Test:** Read `.ccanvil/guide/index.md` and verify all links resolve, all diagrams are accurate.
- **Implement:** Final pass on guide index — ensure renamed files are linked correctly, diagrams reference new filenames, and no broken cross-references remain.
- **Files:** `preset/.ccanvil/guide/index.md`, any guide files with stale cross-refs
- **Verify:** All internal links valid. `bats hub/tests/` passes.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Lockfile breaking change** | Existing downstream lockfiles incompatible | Re-init lockfiles after hub changes (step 13). Both downstreams are under our control. |
| **Delimiter pattern breakage** | `cmd_section_merge` relies on `<!-- NODE-SPECIFIC-START -->` delimiter, not the `/scaffold-pull` comment | Verify delimiter detection logic is independent of the comment text. The comment is cosmetic. |
| **Missed occurrence** | Runtime error or confusing mixed terminology | Final grep sweep (step 14) catches stragglers. Tests cover all runtime paths. |
| **foundations.md protection rules** | Hooks/rules that protect `scaffold-framework.md` will break after rename | Update protection rules in step 8 before or alongside the file rename. |
| **README.md contextual rewording** | Blind find-replace would produce nonsensical text | Steps 8, 11, 12 are marked as judgment calls — require reading and contextual replacement, not sed. |

## Session Boundaries

This is a large feature. Recommended checkpoint points:
- **After step 4:** Core script complete — lockfile keys, functions, variables, actions all renamed. Tests green.
- **After step 7:** All script + test file changes done. Pure documentation remaining.
- **After step 12:** Hub fully clean. Only downstream sweep remaining.

## Definition of Done

- [ ] All 27 acceptance criteria from spec pass
- [ ] All existing tests still pass (352+)
- [ ] `grep -ri scaffold` across repo returns 0 hits (excluding `.git/` and historical spec files)
- [ ] Downstream projects (`fucina`, `luxlook`) return 0 hits
- [ ] Code reviewed (run /review)
