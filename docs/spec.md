# Feature: Eradicate "scaffold" terminology

> Feature: scaffold-terminology-eradication
> Created: 1775450355
> Status: Draft

## Summary

Remove every remaining use of the word "scaffold" from the ccanvil project (hub, preset, and downstream projects), replacing it with clear, consistent terminology. The word "scaffold" is a legacy holdover from when the project was named "claude-code-scaffold." It no longer describes what ccanvil does — it's a configuration preset system with bi-directional sync, not a code scaffolding tool. The ambiguity causes confusion: is "scaffold" the project name, the hub, the sync concept, or the config file?

## Job To Be Done

**When** I read any ccanvil file — code, docs, configs, or lockfiles,
**I want** every term to clearly refer to the correct concept (hub, preset, node, sync),
**So that** the system is self-documenting and new users don't confuse ccanvil with code scaffolding.

## Terminology Map

Every "scaffold" usage falls into one of these categories. Each gets a specific replacement:

| Old term | New term | Rationale |
|----------|----------|-----------|
| `scaffold.json` | `ccanvil.json` | Consistent with `ccanvil.lock` |
| `scaffold.local.json` | `ccanvil.local.json` | Consistent |
| `scaffold.json.md` (template) | `ccanvil.json.md` | Consistent |
| `scaffold_source` (lockfile key) | `hub_source` | It's the hub path |
| `scaffold_version` (lockfile key) | `hub_version` | It's the hub's git version |
| `scaffold_hash` (lockfile key) | `hub_hash` | Hash from the hub side |
| `scaffold-only` (status) | `hub-only` | Describes where the file exists |
| `get_scaffold_source()` | `get_hub_source()` | |
| `get_scaffold_source_raw()` | `get_hub_source_raw()` | |
| `get_scaffold_source_display()` | `get_hub_source_display()` | |
| `scaffold_dist_root()` | `hub_dist_root()` | |
| `scan_scaffold_files()` | `scan_hub_files()` | |
| `merge_scaffold_config()` | `merge_config()` | Already the subcommand name |
| `$scaffold_hash` (variable) | `$hub_hash` | |
| `$scaffold_path` / `$scaffold_file` | `$hub_path` / `$hub_file` | |
| `$scaffold_changed` | `$hub_changed` | |
| `$scaffold_hub` | `$hub_root` | |
| "scaffold hub" (in docs) | "hub" | Already the dominant shorter form |
| "from the scaffold" | "from the hub" | |
| "take scaffold" (conflict) | "take hub" | Conflict resolution option |
| "scaffold changed" | "hub changed" | |
| "scaffold automation" | "preset automation" | |
| "scaffold configuration" | "preset configuration" | |
| `scaffold-differ` (agent name field) | `ccanvil-differ` | Filename already renamed |
| `scaffold-sync.md` (guide file) | `sync.md` | The sync concept doesn't need a prefix |
| `scaffold-framework.md` | **KEEP** | Research doc — "scaffold" is a CS term there |
| `/scaffold-pull` in delimiters | `/ccanvil-pull` | May already be partially done |
| `scaffold-sync.bats` (test file) | `ccanvil-sync.bats` | Mirrors the script name |
| `scaffold-json-override.bats` | `ccanvil-json-override.bats` | Mirrors the config file |

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Config files renamed

- [ ] **AC-1:** `.claude/scaffold.json` is renamed to `.claude/ccanvil.json` in the preset and all downstream projects. `operations.sh` and `docs-check.sh` reference the new filename.
- [ ] **AC-2:** `.claude/scaffold.local.json` is renamed to `.claude/ccanvil.local.json` in all ignore files, documentation, and script references. The deep-merge logic in `operations.sh` uses the new name.
- [ ] **AC-3:** `.ccanvil/templates/scaffold.json.md` is renamed to `.ccanvil/templates/ccanvil.json.md` with updated content.

### Lockfile keys renamed

- [ ] **AC-4:** Lockfile JSON uses `hub_source`, `hub_version`, `hub_hash` instead of `scaffold_source`, `scaffold_version`, `scaffold_hash`. The `cmd_init` and all functions reading these keys are updated.
- [ ] **AC-5:** Status value `scaffold-only` is replaced with `hub-only` in `cmd_init`, `cmd_status`, `cmd_pull_plan`, and all tests.

### Script internals renamed

- [ ] **AC-6:** All function names in `ccanvil-sync.sh` use `hub_` prefix instead of `scaffold_` (see terminology map). No function contains "scaffold" in its name.
- [ ] **AC-7:** All variable names in `ccanvil-sync.sh` use `hub_` instead of `scaffold_` where referring to the hub side. Local-side variables remain unchanged.
- [ ] **AC-8:** `operations.sh` function `merge_scaffold_config()` is renamed to `merge_config()`. All callers updated.
- [ ] **AC-9:** `docs-check.sh` function `merge_scaffold_config()` is renamed to `merge_config()`. `cmd_config_get` references updated.
- [ ] **AC-10:** `context-budget.sh` header comment updated ("scaffold files" -> "preset files").
- [ ] **AC-11:** `security-audit.sh` allowlist entry for `scaffold-framework.md` is preserved (research doc keeps its name).

### Guide and documentation

- [ ] **AC-12:** `.ccanvil/guide/scaffold-sync.md` is renamed to `.ccanvil/guide/sync.md`. All internal links and index references updated.
- [ ] **AC-13:** Every `.ccanvil/guide/*.md` file (except `scaffold-framework.md`) uses "hub" instead of "scaffold" when referring to the source of sync data.
- [ ] **AC-14:** Every `.ccanvil/templates/*.md` file uses `/ccanvil-pull` in delimiter comments instead of `/scaffold-pull`.
- [ ] **AC-15:** `CLAUDE.md` (preset template) uses "hub" terminology and references `ccanvil.json` / `ccanvil.local.json`.

### Commands, agents, rules

- [ ] **AC-16:** `ccanvil-differ.md` agent has `name: ccanvil-differ` (not `scaffold-differ`). All internal references say "hub" not "scaffold".
- [ ] **AC-17:** All `/ccanvil-*` command files use "hub" terminology (e.g., "Pull updates from the hub" not "from the scaffold hub").
- [ ] **AC-18:** All `.claude/rules/*.md` files use "hub" or "preset" instead of "scaffold" where applicable. `scaffold-framework.md` filename references are preserved.
- [ ] **AC-19:** `pr.md` command references `ccanvil.json` (not `scaffold.json`) for feature toggle checks.

### Hub-specific files

- [ ] **AC-20:** `hub/tests/scaffold-sync.bats` is renamed to `hub/tests/ccanvil-sync.bats`. All test assertions use new lockfile keys (`hub_source`, `hub_hash`, `hub-only`).
- [ ] **AC-21:** `hub/tests/scaffold-json-override.bats` is renamed to `hub/tests/ccanvil-json-override.bats`. Tests reference `ccanvil.json` / `ccanvil.local.json`.
- [ ] **AC-22:** Hub `README.md` contains zero instances of "scaffold" as a project/system name (research term in `scaffold-framework.md` reference is acceptable).
- [ ] **AC-23:** Hub root `CLAUDE.md` uses "hub" terminology consistently.

### Downstream projects

- [ ] **AC-24:** After migration, `grep -ri scaffold ~/projects/fucina` returns zero hits outside of `scaffold-framework.md`.
- [ ] **AC-25:** After migration, `grep -ri scaffold ~/projects/luxlook` returns zero hits outside of `scaffold-framework.md`.

### Tests pass

- [ ] **AC-26:** All hub bats tests pass (352+ tests) after all renames.
- [ ] **AC-27:** `ccanvil-sync.sh init` produces a lockfile with new key names (`hub_source`, `hub_version`, `hub_hash`).

## Affected Files

| Area | Change |
|------|--------|
| `preset/.ccanvil/scripts/ccanvil-sync.sh` | Function renames, variable renames, lockfile key changes |
| `preset/.ccanvil/scripts/operations.sh` | `merge_scaffold_config()` -> `merge_config()`, file refs |
| `preset/.ccanvil/scripts/docs-check.sh` | `merge_scaffold_config()` -> `merge_config()`, file refs |
| `preset/.ccanvil/scripts/context-budget.sh` | Comment update |
| `preset/.ccanvil/guide/scaffold-sync.md` | Renamed to `sync.md`, content updated |
| `preset/.ccanvil/guide/*.md` (11 files) | "scaffold" -> "hub"/"preset" |
| `preset/.ccanvil/templates/*.md` (6 files) | Delimiter comments, scaffold.json refs |
| `preset/.ccanvil/templates/scaffold.json.md` | Renamed to `ccanvil.json.md` |
| `preset/.claude/scaffold.json` | Renamed to `ccanvil.json` |
| `preset/.claude/agents/ccanvil-differ.md` | Name field, internal references |
| `preset/.claude/commands/ccanvil-*.md` (7 files) | "scaffold" -> "hub" |
| `preset/.claude/commands/pr.md` | `scaffold.json` -> `ccanvil.json` |
| `preset/.claude/commands/plan.md` | Guide reference update |
| `preset/.claude/rules/*.md` (5 files) | "scaffold" -> "hub"/"preset" |
| `preset/.claude/skills/tdd/SKILL.md` | Delimiter comment |
| `preset/CLAUDE.md` | File references, architecture diagram |
| `preset/.claudeignore` | File references |
| `hub/tests/scaffold-sync.bats` | Renamed to `ccanvil-sync.bats`, assertions updated |
| `hub/tests/scaffold-json-override.bats` | Renamed to `ccanvil-json-override.bats`, file refs |
| `hub/tests/*.bats` (other test files) | Any scaffold refs in setup/assertions |
| `hub/meta/*.md` | Documentation references |
| `hub/specs/scaffold-json-override.md` | Title/content references |
| `CLAUDE.md` (hub root) | Terminology update |
| `README.md` (hub root) | Terminology update |
| `.claudeignore` (hub root) | File references |
| `.gitignore` (hub root) | File references |
| Downstream: fucina, luxlook | Full sweep after hub changes |

## Dependencies

- **Requires:** Luxlook must be migrated to new directory structure first (or done as part of this).
- **Blocked by:** Nothing.

## Out of Scope

- **`scaffold-framework.md`** — This is a research document where "scaffold" is used as a CS/academic term (like "Rails scaffolding"). It keeps its name and content. References TO this file (e.g., in protect-files.sh, code-quality.md) are preserved as-is.
- **Git history** — We won't rewrite commits. Old commit messages referencing "scaffold" are part of the historical record.
- **Linear issue descriptions** — Existing issues may reference "scaffold" terminology. Not worth updating retroactively.

## Implementation Notes

- Start with `ccanvil-sync.sh` since it's the most complex file and all lockfile key changes ripple from there.
- Update tests in lockstep with the script — change a function name, update its test, verify.
- The lockfile key change (`scaffold_source` -> `hub_source`) is a breaking change for existing lockfiles. Since we're actively migrating downstream projects, this is acceptable. Re-init lockfiles after the change.
- The `TRACKED_PATTERNS` array in ccanvil-sync.sh will need `.claude/ccanvil.json` instead of `.claude/scaffold.json`.
- Batch the downstream project updates: after hub changes are complete and tested, sweep fucina and luxlook.
- Consider a `sed` sweep as a starting point, but verify each change manually — not all "scaffold" -> "hub" replacements are appropriate (e.g., `scaffold-framework.md` must be preserved).
