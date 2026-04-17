# Feature: Stable Node UUIDs for Registry

> Feature: node-uuid-registry
> Created: 1776383140
> Status: In Progress

## Summary

The hub registry is currently keyed by absolute filesystem path (e.g., `/Users/zach/projects/taxes`). This breaks when a node is renamed, moved, cloned to another machine, or used by a different user — all operations that happen often. Worse, the path keys embed `$HOME` into the hub's tracked git history, leaking usernames. This feature introduces stable node UUIDs generated at init time, stored in both the lockfile and `.claude/ccanvil.json`, and used as the registry primary key. Paths become mutable properties that self-update on each sync.

## Job To Be Done

**When** I rename, move, clone, or re-home a downstream project,
**I want to** keep its registration identity stable across environments,
**So that** broadcast, sync history, and status tracking survive filesystem reorganization without re-registration.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `ccanvil-sync.sh init` generates a UUID (v4) and writes it to both `.ccanvil/ccanvil.lock` (`node_uuid` field) and `.claude/ccanvil.json` (`node_uuid` field). If a UUID already exists in either file, it is preserved — never regenerated.
- [ ] **AC-2:** When `.ccanvil/ccanvil.lock` is regenerated (e.g., full re-init), the UUID is recovered from `.claude/ccanvil.json` if present. `.claude/ccanvil.json` is the canonical source; the lockfile mirrors it.
- [ ] **AC-3:** `ccanvil-sync.sh register` keys `.ccanvil/registry.json` by UUID. Schema: `{"nodes": {"<uuid>": {"name": "<basename>", "path": "~/projects/taxes", "registered_at": "<epoch>", "last_synced": "<epoch>", "last_synced_version": "<sha>"}}}`. Paths stored in `~`-relative form (not absolute with `$HOME` inline).
- [ ] **AC-4:** `register` called from a node whose UUID is already in the registry updates the existing entry's `path`, `name`, and `registered_at` — does NOT create a duplicate entry.
- [ ] **AC-5:** `broadcast` iterates nodes by UUID, resolves `$HOME` prefix at runtime (`~/projects/taxes` → `/Users/current-user/projects/taxes`), and validates the path exists before sync.
- [ ] **AC-6:** `broadcast` detects stale paths: when a registry UUID's resolved path does not exist, it prints `STALE: <name> (<uuid>) at <path>` and skips that node. It does not error-out the whole broadcast.
- [ ] **AC-7:** Migration: on first sync after this ships, any path-keyed registry entry is converted to UUID-keyed. If the node at that path has no UUID (legacy node), `broadcast` triggers the node to generate one, then rewrites the registry entry. Path-keyed entries are removed after successful migration.
- [ ] **AC-8:** Migration is idempotent — running it against an already-migrated registry is a no-op.
- [ ] **AC-9:** `ccanvil-sync.sh registry` (list command) includes UUID in its output so users can inspect what's registered.
- [ ] **AC-10:** Error case: `init` run in a directory where `.claude/ccanvil.json` exists but has a malformed UUID (not a valid v4) fails with a clear error and does not silently regenerate.
- [ ] **AC-11:** All existing tests pass — no regressions. New tests cover UUID generation, dual storage, path normalization, stale detection, and migration.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — `cmd_init`, `cmd_register`, `cmd_broadcast`, `cmd_registry`; new `generate_uuid`, `get_node_uuid`, `normalize_path`, `expand_path` helpers; migration logic in `cmd_broadcast` |
| `.ccanvil/registry.json` | Schema change — keys move from path to UUID; `path` becomes a property |
| `.ccanvil/ccanvil.lock` | New top-level field: `node_uuid` |
| `.claude/ccanvil.json` | New top-level field: `node_uuid` (canonical source) |
| `hub/tests/node-uuid-registry.bats` | New — test suite |

## Dependencies

- **Requires:** `uuidgen` (macOS stock) or equivalent. Bash fallback: `cat /proc/sys/kernel/random/uuid` or Python-based generator for portability.
- **Blocked by:** Nothing.

## Out of Scope

- Cross-machine registry sync (the registry still lives in the hub repo; it's just now portable in schema). True multi-machine hub sharing is a separate concern.
- UUID rotation/reset (no command to regenerate a UUID intentionally — if needed, user manually deletes and re-inits).
- Automatic re-linking when a stale path is detected — user must manually re-register from the new location (broadcast only reports staleness).
- Renaming/path changes propagated to registry without a sync event (registry updates only happen on `register`, `pre-check`, or `broadcast`).

## Implementation Notes

- **UUID format:** v4 (random). macOS `uuidgen` produces uppercase; normalize to lowercase for consistency.
- **Dual-storage rationale:** `.claude/ccanvil.json` is the human-editable canonical source (survives lockfile regen, visible in `/ccanvil-status`). `.ccanvil/ccanvil.lock` mirrors it for fast access during sync operations (avoids reading two files on every operation).
- **Path normalization:** Use `${path/#$HOME/~}` to convert absolute → portable. Use `${path/#\~/$HOME}` to expand back at runtime. Same pattern already used for `hub_source` in lockfile (line 243 of `ccanvil-sync.sh`).
- **Migration trigger:** Put migration in `cmd_broadcast` prelude (runs once per broadcast invocation, before iterating nodes). This amortizes the cost — no separate migration command needed.
- **Pattern:** Follow existing `cmd_register` shape (lines 1756–1786 of `ccanvil-sync.sh`). Test fixtures follow `hub/tests/ccanvil-sync.bats` setup pattern (temp HUB + NODE, git init, lockfile bootstrap).
