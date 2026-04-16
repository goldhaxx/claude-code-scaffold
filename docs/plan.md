# Implementation Plan: Tech Stack Distribution

> Feature: tech-stack-distribution
> Created: 1776301372
> Spec hash: e96eb36d
> Based on: docs/spec.md

## Objective

Add stack profiles to the hub and two distribution flows (init-time and patch-time) so tech-stack-specific patterns propagate from hub to nodes without drift.

## Sequence

### Step 1: Create the fastapi-sqlite stack profile (AC-9)
- **Test:** Validate manifest.json schema — required fields (`id`, `description`, `files`, `claudemd_section`, `settings_hooks`, `lint_config`), file entries have `source`/`target`/`action`, all referenced files exist on disk.
- **Implement:** Create `hub/stacks/fastapi-sqlite/` directory with:
  - `manifest.json` — profile metadata and file manifest
  - `hooks/protect-db.sh` — adapted from taxes project (parameterize DB_PATTERN)
  - `claudemd-section.md` — API-first CLAUDE.md section template with `<!-- STACK:fastapi-sqlite-START/END -->` delimiters
  - `settings-hooks.json` — PreToolUse hook entry for protect-db.sh
  - `lint.json` — python formatter config
- **Files:** `hub/stacks/fastapi-sqlite/*` (5 new files)
- **Verify:** `bats hub/tests/tech-stack-distribution.bats` — manifest schema tests pass

### Step 2: Implement `stack-list` subcommand (AC-2)
- **Test:** `stack-list` outputs JSON array with `{id, description, files}` for each profile in `hub/stacks/`. Empty array when no stacks exist.
- **Implement:** Add `cmd_stack_list()` to `ccanvil-sync.sh` — scan `hub/stacks/*/manifest.json`, extract fields with `jq`, output JSON array. Add dispatch entry in case statement.
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. Manual: `bash .ccanvil/scripts/ccanvil-sync.sh stack-list` returns fastapi-sqlite.

### Step 3: Implement `stack-apply` — file copy flow (AC-3, AC-7, AC-8)
- **Test:** `stack-apply fastapi-sqlite` in a test node: copies hook script to target path, creates lockfile entry with `origin: "stack:fastapi-sqlite"`, records stack in `ccanvil.json` under `stacks: ["fastapi-sqlite"]`. Invalid stack ID exits non-zero with error message.
- **Implement:** Add `cmd_stack_apply()` to `ccanvil-sync.sh`:
  1. Validate stack ID — check `hub/stacks/<id>/manifest.json` exists, exit 2 if not (AC-8)
  2. Read manifest, iterate `files[]` entries
  3. For `action: "copy"` — `cp` source to target, `mkdir -p` parent dir
  4. Update lockfile: each file gets `origin: "stack:<stack-id>"` (AC-7)
  5. Update `ccanvil.json`: add stack-id to `stacks` array (create array if absent)
  Add dispatch entry in case statement.
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. Lockfile entries show correct origin. `ccanvil.json` updated.

### Step 4: Implement `stack-apply` — CLAUDE.md section merge (AC-3)
- **Test:** `stack-apply` inserts the claudemd-section between `<!-- STACK:<id>-START -->` / `<!-- STACK:<id>-END -->` delimiters. Section placed above `<!-- HUB-MANAGED-START -->` if that delimiter exists, otherwise appended.
- **Implement:** Extend `cmd_stack_apply()`:
  1. Read `claudemd_section` from manifest, read the template file
  2. If CLAUDE.md has `<!-- STACK:<id>-START -->` — replace content between delimiters (idempotent update)
  3. If CLAUDE.md has no stack delimiters — insert above `<!-- HUB-MANAGED-START -->` (or append)
  4. Wrap inserted content in `<!-- STACK:<id>-START -->` / `<!-- STACK:<id>-END -->`
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. CLAUDE.md has delimited section. Re-running doesn't duplicate.

### Step 5: Implement `stack-apply` — settings.json and lint.json merge (AC-3)
- **Test:** `stack-apply` merges hook entries into `.claude/settings.json` without duplicating existing entries. Merges lint config into `lint.json`.
- **Implement:** Extend `cmd_stack_apply()`:
  1. Read `settings_hooks` from manifest, `jq` merge into `.claude/settings.json` — deduplicate by comparing `command` strings
  2. Read `lint_config` from manifest, `jq` merge into `lint.json` — deduplicate by tool name
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. settings.json has new hook entry. Running twice doesn't duplicate.

### Step 6: Implement `stack-apply` patch flow (AC-4)
- **Test:** `stack-apply` on a node that already has the stack: adds only missing files, updates changed files, doesn't clobber node-customized files. CLAUDE.md section updates in-place via delimiters.
- **Implement:** Extend `cmd_stack_apply()`:
  1. Check if stack already in `ccanvil.json` stacks array
  2. For each file: compare hashes — skip if local matches hub, copy if missing or hub-updated
  3. CLAUDE.md: delimiter-based replacement (already idempotent from Step 4)
  4. settings.json/lint.json: dedup merge (already idempotent from Step 5)
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. Existing customizations preserved. New files added.

### Step 7: Extend init-preflight for stack files (AC-5)
- **Test:** `init-preflight` with `--stack fastapi-sqlite` flag includes stack files in plan output with `source: "stack:fastapi-sqlite"`. Also reads stacks from `ccanvil.json` if present.
- **Implement:** Extend `cmd_init_preflight()`:
  1. Parse `--stack <id>` flag(s) from args
  2. Also read `stacks` array from target project's `ccanvil.json` if it exists
  3. For each stack: read manifest, add file entries to the plan with source classification
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. Preflight JSON includes stack file entries.

### Step 8: Extend init-apply for stack files (AC-6)
- **Test:** `init-apply` processes stack file entries from preflight plan — copies files, merges CLAUDE.md section, updates settings.json, updates lockfile with stack origin.
- **Implement:** Extend `cmd_init_apply()`:
  1. Detect stack entries in plan (entries with `source: "stack:*"`)
  2. Resolve source files from hub stack directory
  3. Apply using same mechanics as `stack-apply` (copy, section-merge, settings merge)
- **Files:** `.ccanvil/scripts/ccanvil-sync.sh`
- **Verify:** Tests pass. Full init + stack provisioning works end-to-end.

### Step 9: Regression sweep (AC-10)
- **Test:** Run full test suite `bats hub/tests/`
- **Implement:** Fix any regressions from changes to init-preflight/init-apply or lockfile handling
- **Files:** Any affected files
- **Verify:** All tests pass (448+ existing + new stack distribution tests)

### Step 10: Update documentation
- **Implement:** Update `.ccanvil/guide/command-reference.md` with `stack-list` and `stack-apply` subcommands. Update `CLAUDE.md` hub section if commands list changed.
- **Files:** `.ccanvil/guide/command-reference.md`, `CLAUDE.md` (if needed)
- **Verify:** `docs-check.sh validate` passes

## Risks

- **settings.json merge complexity** — `jq` merge of nested arrays (PreToolUse hooks) must deduplicate by command string, not by position. Mitigate: test with existing hooks present, test idempotency.
- **CLAUDE.md insertion point** — projects may not have `<!-- HUB-MANAGED-START -->` delimiter yet. Mitigate: fallback to append, test both cases.
- **protect-db.sh portability** — taxes version references `src/app.py` in error messages. Stack template should use a placeholder or parameterize. Mitigate: use generic message in hub version, let nodes customize via section-merge pattern.

## Definition of Done

- [ ] All acceptance criteria from spec pass
- [ ] All existing tests still pass
- [ ] No type errors
- [ ] Code reviewed (run /review)
