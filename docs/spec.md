# Feature: Sync subcommands — migrate, status --json, registry

> Feature: sync-subcommands
> Created: 1775603749
> Status: In Progress

## Summary

Three new capabilities for ccanvil-sync.sh, all sourced from determinism reviews:

1. **`migrate`** (BTS-65) — One-command downstream project migration: copy fresh preset files, handle renames, re-init lockfile.
2. **`status --json`** (BTS-66) — Machine-readable status output with optional filter, replacing manual jq/python lockfile inspection.
3. **`registry`** (BTS-63) — Hub tracks which downstream projects are linked and when they last synced.

## Job To Be Done

**When** I need to migrate a downstream project, inspect lockfile state programmatically, or find which projects use the preset,
**I want** single deterministic script calls,
**So that** Claude doesn't spend context on manual cp/jq/find sequences.

## Acceptance Criteria

### migrate (BTS-65)

- [ ] **AC-1:** `ccanvil-sync.sh migrate <hub-path>` copies all hub-managed files from the preset to the current project directory, handling section-merge for delimited files (CLAUDE.md).
- [ ] **AC-2:** `migrate` renames stale files if detected (scaffold-sync.md→sync.md, scaffold-framework.md→foundations.md, scaffold.json.md→ccanvil.json.md, scaffold.json→ccanvil.json).
- [ ] **AC-3:** `migrate` re-initializes the lockfile after copying (calls `cmd_init`).
- [ ] **AC-4:** `migrate` outputs a summary of what was copied/renamed/merged.
- [ ] **AC-5:** `migrate --dry-run` shows what would happen without modifying files.

### status --json (BTS-66)

- [ ] **AC-6:** `ccanvil-sync.sh status --json` outputs the full status as a JSON object with `hub_source`, `hub_version`, `synced_at`, and a `files` array of `{file, origin, status, sync, hub_hash, local_hash}`.
- [ ] **AC-7:** `ccanvil-sync.sh status --json --filter <status>` outputs only files matching the given status (e.g., `--filter modified`).
- [ ] **AC-8:** `ccanvil-sync.sh status --json --filter non-clean` is a convenience alias that shows all files NOT in "clean" status.

### registry (BTS-63)

- [ ] **AC-9:** `ccanvil-sync.sh register` (run from a downstream project) adds the project to the hub's `.ccanvil/registry.json` with project path, name, and last-synced timestamp.
- [ ] **AC-10:** `ccanvil-sync.sh registry` (run from the hub) lists all registered downstream projects with their sync state.
- [ ] **AC-11:** `init` automatically calls `register` after generating the lockfile, so new projects are tracked from the start.

### Tests

- [ ] **AC-12:** All existing tests pass (357+).
- [ ] **AC-13:** New tests cover migrate (dry-run + actual), status --json (full + filtered), and registry (register + list).

## Affected Files

| File | Change |
|------|--------|
| `preset/.ccanvil/scripts/ccanvil-sync.sh` | Add cmd_migrate, extend cmd_status, add cmd_register/cmd_registry |
| `hub/tests/ccanvil-sync.bats` | New tests for all three features |

## Implementation Notes

- `migrate` reuses existing primitives: `scan_hub_files`, `cmd_section_merge`, `cmd_init`.
- `status --json` reuses the same iteration as `cmd_status` but outputs JSON instead of tabular text.
- Registry is a JSON file in the hub (`.ccanvil/registry.json`). `register` writes to it via the hub path from the lockfile.
- `migrate` should detect the hub path from an existing lockfile OR accept it as an argument.

## Out of Scope

- Automatic pull after migrate (user runs `/ccanvil-pull` if needed).
- Registry-driven bulk operations (e.g., "push to all nodes").
