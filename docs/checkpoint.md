# Checkpoint

> Feature: sync-subcommands (and prior features)
> Last updated: 1775604693
> Plan hash: none (multi-feature session, plans were inline)
> Session objective: Clear the entire actionable backlog

## Accomplished

### Scaffold terminology eradication (PR #8, merged)
- 77+ files, ~815 occurrences across hub, preset, and downstream projects
- Lockfile keys: scaffold_source→hub_source, scaffold_version→hub_version, scaffold_hash→hub_hash
- 6 functions, 12 variables, all strings/comments renamed
- Config files: scaffold.json→ccanvil.json, template and guide renames
- Downstream: fucina and luxlook migrated and committed
- 352/352 tests

### CLAUDE.md context budget trim (BTS-23, PR #9, merged)
- CLAUDE.md: 87→58 lines, 1,234→767 tokens
- Budget: 90.5% CRITICAL → 84.7% WARNING
- Framework-specific conventions relocated to guide/getting-started.md
- Dangling reference pointers removed

### Bootstrap hash auto-update (BTS-27, PR #10, merged)
- Pre-check now updates lockfile hashes after bootstrap copy
- Removed dead-code pull-auto skip
- 354/354 tests (2 new)

### operations.sh exec subcommand (BTS-25, PR #11, merged)
- Resolve AND execute in one call for bash mechanisms
- MCP mechanisms output resolution JSON
- Fixed stale script paths in local adapter
- 357/357 tests (3 new)

### Sync subcommands (BTS-63, BTS-65, BTS-66, PR #12, open)
- **status --json** — machine-readable output with --filter support
- **migrate** — one-command downstream migration (copy, section-merge, rename stale files, re-init)
- **register/registry** — hub tracks linked downstream projects via .ccanvil/registry.json
- 367/367 tests (10 new)

### Backlog housekeeping
- BTS-28: verified already implemented, marked Done
- BTS-64: consolidated into BTS-65 (duplicate)
- BTS-23: marked Done in Linear (was stale)
- PR #6: closed (stale, old repo)
- manifest.lock: 21 stale scaffold entries removed

## Current State

- **Branch:** `claude/feat/sync-subcommands`
- **Hub tests:** 367/367 passing
- **Working tree:** clean
- **Open PR:** #12 (sync subcommands — ready to merge)
- **Backlog:** empty (actionable). Only BTS-20 and BTS-21 remain (needs-research/future)

## Next Steps

1. Merge PR #12
2. Update MEMORY.md backlog section (all items now Done)
3. Future: BTS-20 (workflow engine) and BTS-21 (GitHub agentic workflows) when ready

## Determinism Review

- **operations_reviewed:** 10
- **candidates_found:** 1

**AC-11 (init auto-registers):** The spec called for init to automatically call register (AC-11), but this was deferred to avoid changing init's behavior for projects that don't want registry tracking. Should be a follow-up: `init --register` flag or a post-init hook. Impact: **low** — register is a one-liner that can be run manually.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
