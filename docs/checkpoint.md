# Checkpoint

> Feature: multi-feature-session (node-uuid-registry → clean-init-commits → global-commands-sync)
> Last updated: 1776398755
> Plan hash: n/a (three sequential features, each plan archived on its merged PR)
> Session objective: ship tech-stack-distribution, then address the registry/init gaps surfaced during rollout, then modernize all downstream nodes — including whoop-toolbox.

## Accomplished

- **PR #27: tech-stack-distribution** — hub/stacks/<id>/ profile system; `stack-list` + `stack-apply` subcommands; init-preflight/init-apply extended with `--stack` flag; first profile `fastapi-sqlite` with protect-db.sh hook.
- **PR #28: node-uuid-registry** — stable UUIDs generated at init, stored in `.claude/ccanvil.local.json` (canonical, gitignored) + mirrored in lockfile. Registry keyed by UUID; paths portable (`~`-form). Automatic migration of legacy path-keyed entries; `STALE` detection for missing paths.
- **PR #29: clean-init-commits** — `cmd_register`, `migrate_registry`, and broadcast batch-update all auto-commit hub registry changes (`chore(registry): ...`). Bootstrap commits in nodes tolerate gitignored lockfiles (skip via `git check-ignore`). Failure-tolerant — hook failures print warnings, don't abort.
- **PR #30: global-commands-sync** — renamed hub `global-commands/init.md` → `ccanvil-init.md`; new `pull-globals` subcommand propagates hub's `ccanvil-*.md` files to `~/.claude/commands/` with conflict-safe diff reporting + `--force` opt-in. New skill `/ccanvil-pull-globals`. User-owned namespace is sacrosanct.
- **Registry migrated live** — all 4 nodes converted path→UUID; taxes registered (`24f2fe5a`); all registry mutations committed in hub.
- **All downstream nodes modernized to hub `45a971d`** — whoop-toolbox, luxlook, fucina synced and carrying the new skill. taxes + fieldnation-toolbox skipped (active work in progress on both).
- **2 bugs flagged + fixed** — migration couldn't bootstrap ccanvil.local.json in legacy nodes (fixed in `c3617ac`); `~/.claude/commands/init.md` path stale after BTS-67 flatten (motivated PR #30).

## Current State

- **Branch:** main
- **Tests:** 511/511 passing
- **Uncommitted changes:** none
- **Build status:** clean; hub repo tracking origin/main

## Blocked On

- **taxes** and **fieldnation-toolbox** still on older hub versions (both have active in-progress work). Next broadcast for each will catch them up once their current branches land.

## Next Steps

1. **Dark code idea (8ef0)** is still untriaged — run `/idea triage` to evaluate Nate B Jones' Three-Layer Solution for ccanvil integration (spec-driven dev, self-describing systems, comprehension gate). Could influence the module-manifest direction.
2. **Backlog continuation** — BTS-22 (docs directory strategy), checkpoint evolution (`/compact` + auto-memory may obsolete checkpoint format), BTS-20 (workflow engine).
3. **Run a broadcast + stack-apply for fieldnation-toolbox** once its WIP lands — that's the urgent API-first case (unguarded SQL mutations).
4. **Run `/radar`** at next session start for full strategic briefing.

## Context Notes

- **Design decision (node_uuid storage):** spec said `.claude/ccanvil.json`; implementation moved to `.claude/ccanvil.local.json`. Reason: `ccanvil.json` is hub-tracked, so adding per-node state to it makes the file always locally-modified, breaking sync. `ccanvil.local.json` was designed for exactly this purpose. PR body documents the deviation.
- **Design decision (auto-commit hub registry):** uses `ALLOW_MAIN=1` to bypass protect-main hook; legitimate because these are deterministic sync-lifecycle commits. Failure-tolerant (warns + continues).
- **Known limitation (`pull-globals` requires a lockfile):** can't be run from the hub itself (hub has no self-pointing lockfile). Workaround: run from any node. Not worth fixing now given the niche.
- **Whoop-toolbox was initialized before PR #28-30 landed.** Broadcast brought it to current state; this validates the UUID migration + clean-init-commits work on a real node that predates both features.
- **fucina and luxlook were "Already up to date" on the first post-merge broadcast** — UUIDs propagated via the migration-in-broadcast path, not a per-node init re-run.

## Determinism Review

- **operations_reviewed:** ~15 (registry mutations, node file bootstrap, merge/land cycles, cross-node commits)
- **candidates_found:** 2

- **Cross-node commit loops:** Claude ran `for node in whoop-toolbox luxlook fucina; do cd $node && git add ... && git commit ...; done` twice this session (once for UUID bootstrap files, once for the new skill). Should be a broadcast phase or a `ccanvil-sync.sh adopt-new-all <file>` subcommand. Impact: medium — these happen whenever a non-auto-mergeable new file reaches multiple nodes.

- **Post-merge local main reset:** Claude ran `ALLOW_DESTRUCTIVE=1 git reset --hard origin/main` three times (once per PR merge) to reconcile the diverged local main after squash. This is actually what `docs-check.sh land` is for, but `land` refuses to run "when already on main" — so the natural flow of `/pr` → merge → reset gets manual. Should be: `land` handles the on-main case by just resetting to origin/main if we're clean. Impact: medium — happens every PR.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
