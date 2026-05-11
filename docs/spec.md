# Feature: pull-globals staleness gate

> Feature: bts-315-pull-globals-staleness-gate
> Work: linear:BTS-315
> Created: 1778516248
> Subject: pull-globals staleness gate
> Status: In Progress

## Summary

`/ccanvil-init` currently never checks whether `~/.claude/commands/ccanvil-*.md` files are stale against the hub's canonical `global-commands/`. Stale user-level skill prose has caused operator-visible breakage (microsoft365-toolbox init 2026-05-05: instructions told operator to copy `.ccanvil/templates/checkpoint.md` — a path that never existed in the hub). This feature adds a deterministic staleness probe (`ccanvil-sync.sh pull-globals --check`) and wires it into `/ccanvil-init` so operators see drift surfaced at init time, with `/ccanvil-pull-globals` recommended for repair. The check is non-mutating; auto-pull is intentionally out of scope (user-level files stay opt-in).

## Job To Be Done

**When** I run `/ccanvil-init` on a fresh or existing project,
**I want to** be told if my user-level `ccanvil-*` global commands have drifted from the hub canonical,
**So that** I don't blindly follow stale skill prose that references paths or steps that no longer exist.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `bash .ccanvil/scripts/ccanvil-sync.sh pull-globals --check` exits 0 and emits a JSON envelope of shape `{stale_count, stale:[{name, hub_hash, local_hash}], missing_count, missing:[{name}], up_to_date_count}`. No filesystem writes. Two consecutive invocations produce byte-identical stdout (idempotent).

- [ ] **AC-2: Given** at least one `~/.claude/commands/ccanvil-*.md` file whose hash differs from the hub's `global-commands/<same-name>` file, **when** `pull-globals --check` runs, **then** that file appears in `stale[]` with both `hub_hash` and `local_hash` populated, AND `stale_count` reflects the count, AND it does NOT appear in `up_to_date_count` or `missing[]`.

- [ ] **AC-3: Given** a hub `global-commands/ccanvil-*.md` file with NO corresponding `~/.claude/commands/<same-name>` file, **when** `pull-globals --check` runs, **then** that file appears in `missing[]` with `name` set, AND `missing_count` reflects the count, AND it does NOT appear in `stale[]`.

- [ ] **AC-4: Given** `/ccanvil-init` is invoked in any of its branches (already-initialized / fresh / mature-repo / partial-ccanvil — every path), **when** the skill begins (the first action of Step 1, before the project-mode detection and before the already-initialized interactive options block), **then** it invokes `pull-globals --check` and parses the envelope. **When** `stale_count + missing_count > 0`, the skill prints a warning block listing up to 5 drifted file names (with `+ N more` suffix when truncated) followed by the literal recommendation line `Run /ccanvil-pull-globals to refresh, then re-run /ccanvil-init.` — both written to stderr. Init proceeds regardless of the count — the gate is informational, never blocking, never prompts the user, fires on every invocation regardless of project_mode.

- [ ] **AC-8: Edge: When** the hub's `global-commands/` directory contains zero `ccanvil-*.md` files (degenerate case — empty allowlist), `pull-globals --check` exits 0 and emits `{stale_count:0, stale:[], missing_count:0, missing:[], up_to_date_count:0}`. No error, no warning. `/ccanvil-init`'s Step 1 probe treats `stale_count + missing_count == 0` as silent — no warning block, no recommendation line.

- [ ] **AC-5: Error: When** `$HOME` is unset, `pull-globals --check` exits non-zero with stderr `\$HOME is not set` (mirrors existing `cmd_pull_globals` failure mode). **When** the hub lockfile is missing, exits non-zero with the existing `require_lockfile` error.

- [ ] **AC-6:** `pull-globals --check` enumerates ONLY files matching `ccanvil-*.md` glob in the hub's `global-commands/`. User-owned (non-`ccanvil-*`) files in `~/.claude/commands/` are never read, never hashed, never reported. Mirrors existing `pull-globals` namespace scope.

- [ ] **AC-7:** Re-running `pull-globals` (without `--check`) after `pull-globals --check` produces the existing `{copied, skipped, conflicts}` envelope unchanged — `--check` is read-only and does not perturb existing behavior.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — extend `cmd_pull_globals` to accept `--check` flag; new read-only branch emitting the staleness envelope. |
| `global-commands/ccanvil-init.md` | Modified — add entry-time staleness probe step before the existing bootstrap-and-preflight section. This is the canonical (and only) `/ccanvil-init` skill location. |
| `hub/tests/pull-globals.bats` | Modified — add tests for AC-1, AC-2, AC-3, AC-5, AC-6, AC-7, AC-8 (substrate behavior + degenerate empty-hub case); existing pull-globals fixtures already provide the `FAKE_HOME` + temp-hub pattern to reuse. |
| `hub/tests/ccanvil-init-skill.bats` | Modified — add test for AC-4 (skill prose invokes the probe at the first action of Step 1 and emits the warning literal when drift > 0). |

## Dependencies

- **Requires:** Existing `cmd_pull_globals` substrate, `file_hash` helper, `get_hub_source`, `require_lockfile`. All already shipped.
- **Blocked by:** Nothing.

## Out of Scope

- Auto-pull-on-stale (the ticket's "Auto-pull is faster but mutates user-level files" open question — defer; user-level files stay strictly opt-in).
- Probes from `/recall` or `/radar` — this spec scopes only `/ccanvil-init` integration. Ambient nudges can be a follow-up if the init-time gate proves insufficient.
- Version-pin or mtime-based staleness detection — hash-compare matches existing `cmd_pull_globals` semantics exactly; no need for a parallel mechanism.
- Hub-side `global-commands/` changes (renames, deletions) — `--check` reports state, not migrations.
- Fleet-wide staleness sweep (across all registered downstream nodes) — out of scope; this is per-machine user-level state, not per-node.

## Implementation Notes

- **Substrate shape:** mirror `cmd_pull_globals`'s existing loop. Same `ccanvil-*.md` glob in `$hub_path/global-commands`. For each file, compute both hashes via the existing `file_hash` helper. Classify into one of three buckets: `missing` (no local file), `up_to_date` (hashes match), `stale` (hashes differ). Emit single `jq -n` envelope at the end. No diff output (that's `pull-globals` non-check mode's job).
- **Skill integration shape:** the `/ccanvil-init` skill (at `global-commands/ccanvil-init.md`, the canonical hub location — there is no `.claude/skills/ccanvil-init/`) gains a Step 0 that calls `pull-globals --check`, parses stale + missing counts via `jq`, and on `count > 0` prints the warning block. Treat as a probe — no exit, no halt.
- **Manifest update:** `cmd_pull_globals`'s existing `@manifest`/`# caller:` comments stay as-is; the new `--check` branch is internal. Update the SKILL.md manifest's `failure-mode:` block to document the `--check` success/no-warning case (or leave for the implementer to decide if `failure-mode` needs an entry for the probe variant). Plan-time decision.
- **Hash helper:** reuse `file_hash` from `ccanvil-sync.sh`. Do not introduce a separate hashing path.
- **Test pattern:** follow the same fixture pattern as existing `pull-globals` bats — synthesize a temp `~/.claude/commands/` via `HOME` env override + temp hub fixture. Existing bats already exercises this; new tests slot into the same file.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
