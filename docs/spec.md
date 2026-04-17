# Feature: Global Commands Sync

> Feature: global-commands-sync
> Created: 1776388358
> Status: In Progress

## Summary

ccanvil distributes one global command (`~/.claude/commands/init.md`) but has no mechanism to propagate updates from the hub's `global-commands/` source of truth. When the hub's version changed after the BTS-67 flatten, the user's active copy kept pointing at the old `preset/` path and silently failed. ccanvil is a bolt-on to Claude Code, not a replacement — it must respect user-owned global files. This feature adopts namespaced ownership (`ccanvil-*` prefix = hub-owned, all else = user's) and adds an opt-in pull command so users can refresh hub-owned globals without risk to their own additions.

## Job To Be Done

**When** the hub's global command files change (new subcommand, path fix, message tweak),
**I want to** pull those updates into `~/.claude/commands/` on demand without touching my personal non-ccanvil commands,
**So that** my global Claude Code setup stays in sync with the hub without forcing a replacement-style install.

## Acceptance Criteria

- [ ] **AC-1:** Rename `global-commands/init.md` → `global-commands/ccanvil-init.md` in the hub. The file's first line is updated to reference the new command name.
- [ ] **AC-2:** Rename `~/.claude/commands/init.md` → `~/.claude/commands/ccanvil-init.md` so the global command is immediately discoverable as `/ccanvil-init` and `/init` is available for other uses.
- [ ] **AC-3:** New subcommand `ccanvil-sync.sh pull-globals` scans the hub's `global-commands/` directory and, for each `ccanvil-*.md` file, copies it to `~/.claude/commands/`. Prints a summary JSON: `{copied: N, skipped: N, conflicts: N}`.
- [ ] **AC-4:** When a hub-owned file exists locally AND its hash differs from the hub version, `pull-globals` does NOT overwrite — it marks the file as a conflict and prints the diff. Exit code 0 (conflicts are reportable, not fatal).
- [ ] **AC-5:** `pull-globals` accepts `--force` to overwrite conflicts (explicit opt-in). With `--force`, conflicted files are replaced by the hub version.
- [ ] **AC-6:** `pull-globals` NEVER touches files in `~/.claude/commands/` that don't match `ccanvil-*.md` — even if a hub file shares the bare name. User-owned namespace is sacrosanct.
- [ ] **AC-7:** New skill `.claude/skills/ccanvil-pull-globals/SKILL.md` calls `ccanvil-sync.sh pull-globals`, formats the JSON output as a user-friendly summary, and surfaces diffs for any conflicts.
- [ ] **AC-8:** Error case: `pull-globals` run in a context where `$HOME/.claude/commands/` does not exist creates the directory. If `$HOME` is not set, exits non-zero with clear error.
- [ ] **AC-9:** All existing tests pass — no regressions. New tests in `hub/tests/pull-globals.bats` cover copy, conflict detection, `--force`, untouched non-ccanvil files, and the missing-directory case.

## Affected Files

| File | Change |
|------|--------|
| `global-commands/init.md` | Renamed → `global-commands/ccanvil-init.md`; first-line command reference updated |
| `~/.claude/commands/init.md` | Renamed → `~/.claude/commands/ccanvil-init.md` (one-time manual step documented in the PR) |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `cmd_pull_globals`, dispatch entry, usage help line |
| `.claude/skills/ccanvil-pull-globals/SKILL.md` | New — skill wrapper that formats the script output |
| `hub/tests/pull-globals.bats` | New — test suite |

## Dependencies

- **Requires:** Existing `ccanvil-sync.sh` infrastructure (file_hash, die)
- **Blocked by:** Nothing

## Out of Scope

- Preflight/interactive resolution flow for globals (like `init-preflight` for projects). With one file today it's overkill; revisit when there are 5+ global commands.
- Automatic `pull-globals` on broadcast or init. Stays strictly opt-in per the "bolt-on" framing.
- Push direction (project-level promoted commands going back to hub's `global-commands/`). Existing `ccanvil-push` + `promote` flow covers project files only; globals are hub-authored for now.
- Cross-machine sync of `~/.claude/commands/`. Out of scope for this project.

## Implementation Notes

- **File matching:** Shell glob `global-commands/ccanvil-*.md`. Use `compgen -G` or direct iteration with `nullglob`. Script must handle empty directory case.
- **Hash comparison:** Reuse existing `file_hash()` helper (line ~110 of `ccanvil-sync.sh`). Identical hashes → skip. Different hashes → conflict unless `--force`.
- **JSON output pattern:** Follow `cmd_stack_list` shape (lines ~2107+) — build JSON with `jq -n` at the end.
- **Skill wrapper:** Follow existing skill pattern — frontmatter + body that invokes the script and interprets results. See `.claude/skills/radar/SKILL.md` for structure.
- **Test fixtures:** Mock `$HOME` in bats by exporting a temp dir as `HOME` for the test subshell. Follow `hub/tests/clean-init-commits.bats` setup pattern.
- **The rename of `~/.claude/commands/init.md`:** Done manually as part of this PR (two shell commands — `mv` + delete stale `init.md` if needed). Can't be automated because the file lives outside the repo; document in the PR body as a one-time post-merge step.
