# Feature: Tech Stack Distribution

> Feature: tech-stack-distribution
> Created: 1776280386
> Status: Complete

## Summary

ccanvil distributes methodology (rules, hooks, commands) identically to every downstream node but has no mechanism for distributing tech-stack-specific patterns. When a stack enhancement (e.g., protect-db.sh) is proven in one project, other projects sharing that stack don't receive it — they drift silently. This feature adds stack profiles to the hub and two distribution flows: init-time provisioning (new projects) and patch-time application (existing projects missing newer guardrails).

## Job To Be Done

**When** a tech stack pattern (hooks, rules, CLAUDE.md sections) is proven in one downstream project,
**I want to** codify it as a hub stack profile and distribute it to all projects using that stack,
**So that** stack enhancements propagate automatically instead of requiring manual, ad-hoc copying that creates drift.

## Acceptance Criteria

- [ ] **AC-1:** Stack profiles live in `hub/stacks/<stack-id>/` with a `manifest.json` describing the profile contents (files, CLAUDE.md sections, settings.json hook entries, lint.json formatters)
- [ ] **AC-2:** `ccanvil-sync.sh stack-list` outputs available stack profiles as JSON array of `{id, description, files}`
- [ ] **AC-3:** `ccanvil-sync.sh stack-apply <stack-id>` provisions stack files to the current project — copies hook scripts, merges CLAUDE.md section, updates settings.json hooks, updates lint.json formatters — and records the stack in `ccanvil.json` under `stacks: ["<stack-id>"]`
- [ ] **AC-4:** `stack-apply` on a project that already has the stack (patch flow) adds only missing/updated files and sections — does not duplicate or clobber existing content
- [ ] **AC-5:** `init-preflight` includes stack-specific files in its plan when `ccanvil.json` declares stacks or when a `--stack <id>` flag is passed
- [ ] **AC-6:** `init-apply` provisions stack files alongside hub-universal files using the same copy/merge mechanics
- [ ] **AC-7:** Stack-applied files are tracked in the lockfile with `origin: "stack:<stack-id>"` so sync can distinguish hub-universal from stack-specific files
- [ ] **AC-8:** `stack-apply` with an invalid or nonexistent stack ID returns a clear error and exits non-zero
- [ ] **AC-9:** First stack profile `fastapi-sqlite` exists with: protect-db.sh hook, API-first CLAUDE.md section template, settings.json hook entry, lint.json python formatter entry
- [ ] **AC-10:** Existing tests pass — no regressions in the test suite

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `stack-list`, `stack-apply` subcommands; extend `init-preflight`/`init-apply` for stack files |
| `hub/stacks/fastapi-sqlite/manifest.json` | New — first stack profile manifest |
| `hub/stacks/fastapi-sqlite/hooks/protect-db.sh` | New — database mutation gating hook |
| `hub/stacks/fastapi-sqlite/claudemd-section.md` | New — API-first CLAUDE.md section template |
| `hub/stacks/fastapi-sqlite/settings-hooks.json` | New — hook entries to merge into settings.json |
| `hub/stacks/fastapi-sqlite/lint.json` | New — python formatter config to merge into lint.json |
| `hub/tests/tech-stack-distribution.bats` | New — test suite for stack distribution |

## Dependencies

- **Requires:** Existing sync infrastructure (`ccanvil-sync.sh`, lockfile, `ccanvil.json`)
- **Blocked by:** Nothing

## Out of Scope

- Patching specific downstream projects (fieldnation-toolbox, taxes) — that happens after this ships via `stack-apply`
- Stack removal/downgrade (`stack-remove` command)
- Stack versioning (stack profiles evolve with the hub; no independent version tracking yet)
- Multiple stacks on one project (data model supports it via array, but interaction testing deferred)
- Auto-applying stacks during `broadcast` (manual `stack-apply` per node for now)

## Implementation Notes

- **manifest.json schema:** `{id, description, files: [{source, target, action}], claudemd_section: "<file>", settings_hooks: "<file>", lint_config: "<file>"}`. Actions: `copy` (new file), `merge` (append/merge into existing).
- **CLAUDE.md section insertion:** Insert stack section into the node-specific area (above `<!-- HUB-MANAGED-START -->`). Use a `<!-- STACK:<id>-START -->` / `<!-- STACK:<id>-END -->` delimiter pair so patch flow can detect existing sections and update them idempotently.
- **settings.json merge:** `jq` merge of hook entries from `settings-hooks.json` into the project's `.claude/settings.json`. Must not duplicate existing entries.
- **Lockfile tracking:** Stack files get `origin: "stack:fastapi-sqlite"` instead of `origin: "hub"`. This lets `pull-plan` skip stack files during normal hub pulls (they sync on `stack-apply` only).
- **protect-db.sh:** Adapt from taxes project's proven implementation. Parameterize DB_PATTERN for the stack profile (SQLite: `*.db`, `sqlite3`). Research at `hub/meta/api-first-research.md`.
- **Pattern:** Follow `cmd_init_preflight`/`cmd_init_apply` structure in `ccanvil-sync.sh` for the new subcommands.
