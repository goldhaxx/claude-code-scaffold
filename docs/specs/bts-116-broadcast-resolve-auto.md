# Feature: ccanvil-sync.sh broadcast-resolve-auto for ccanvil.json conflicts

> Feature: bts-116-broadcast-resolve-auto
> Work: linear:BTS-116
> Created: 1777174532
> Status: In Progress

## Summary

When `ccanvil-sync.sh broadcast` surfaces a `.claude/ccanvil.json` conflict on a downstream node, today the operator manually reads both sides, jq-diffs against the hub, classifies (content-identical vs. local-has-extras vs. real-divergence), chooses `take-hub` or `keep-local`, runs `pull-apply`, and commits the lockfile. The classification step is mechanical: hash-compare → take-hub if identical; jq-superset-check → keep-local if local strictly extends hub; otherwise leave for manual review. Add a `ccanvil-sync.sh broadcast-resolve-auto` subcommand that performs the algorithmic part deterministically on the node where broadcast surfaced the conflict, leaving only genuinely-ambiguous divergences for human judgment.

## Job To Be Done

**When** `ccanvil-sync.sh broadcast` reports a `.claude/ccanvil.json` conflict on a downstream node,
**I want** to run one command that algorithmically resolves the deterministic cases (identical content → take-hub; local-superset-of-hub → keep-local) and clearly reports any remaining ambiguous divergence for manual review,
**So that** the recurring stochastic dance (read both, jq-diff, classify, dispatch, commit lockfile) collapses to a single substrate call and the operator only spends judgment cycles on real semantic divergences.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `ccanvil-sync.sh broadcast-resolve-auto` invoked in a node directory (containing `.ccanvil/ccanvil.lock`) where local and hub `.claude/ccanvil.json` are byte-identical resolves the conflict via `take-hub` semantics. Output JSON: `{file: ".claude/ccanvil.json", resolution: "take-hub", hub_hash: "<sha>", local_hash: "<sha>", applied: true, reason: "content-identical"}`. Lockfile updated to record hub_hash.
- [ ] **AC-2:** Invoked where local has extra top-level keys beyond hub (e.g., local has `{"hub": {...}, "routing": {...}, "node_uuid": "..."}` and hub has `{"hub": {...}}` with all hub-side values matching local-side values for shared keys), resolves via `keep-local` semantics. Output JSON: `resolution: "keep-local"`, `reason: "local-superset-of-hub"`. Lockfile updated to record local as canonical (no file rewrite needed).
- [ ] **AC-3:** Invoked where local and hub disagree on a shared key's value (e.g., both have `hub.path` but with different strings), exits 3 (requires-review). Output JSON: `resolution: "requires-review"`, `reason: "value-divergence"`, `divergent_keys: ["hub.path"]`. No mutation. Operator handles manually.
- [ ] **AC-4:** Invoked where local removed a key that's present in hub (e.g., hub has `{"a": 1, "b": 2}`, local has `{"a": 1}`), exits 3 (requires-review). Output JSON: `resolution: "requires-review"`, `reason: "local-removed-keys"`, `removed_keys: ["b"]`. Could be intentional removal or accidental drift; human decides.
- [ ] **AC-5:** `--dry-run` flag outputs the same JSON envelope but does NOT modify any files (lockfile, ccanvil.json) and does NOT commit. The `applied` field is `false` even when the resolution is auto-applicable.
- [ ] **AC-6:** Invoked in a directory that is NOT a node (no `.ccanvil/ccanvil.lock`) exits 2 with stderr error: `broadcast-resolve-auto: not a ccanvil node (no .ccanvil/ccanvil.lock)`. No mutation.
- [ ] **AC-7:** Invoked when the node has no `.claude/ccanvil.json` conflict (the file matches hub or doesn't exist on either side), outputs JSON `resolution: "no-conflict"`, `applied: false`, exits 0. Idempotent — re-running after a successful resolution is a no-op.
- [ ] **AC-8:** Drift-guard: existing `pull-plan` and `pull-apply` behaviors are unchanged. The new subcommand reuses `pull-apply <file> take-hub` and `pull-apply <file> keep-local` for actual mutation; it doesn't reimplement file copy / lockfile-update logic.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `cmd_broadcast_resolve_auto` function and dispatch case |
| `hub/tests/broadcast-resolve-auto.bats` | New — tests for AC-1 through AC-8 with isolated fixture nodes |

## Dependencies

- **Requires:** `pull-plan` and `pull-apply` subcommands (already exist).
- **Blocked by:** none.

## Out of Scope

- **Generalizing to other file types.** This subcommand handles `.claude/ccanvil.json` only — it's the recurring case the ticket calls out. Other file conflicts (`.claude/settings.json`, hooks, scripts) often involve actual code changes where take-hub-vs-keep-local can't be hash-decided. Generalize only if a second concrete recurring file surfaces.
- **Hub-side `--all` iteration.** A `--all` flag that iterates every registered node from hub root and resolves their conflicts is a natural follow-up but expands the surface (subprocess management, registry walk, aggregated reporting). Ship the per-node single-target version first.
- **Top-level array additions.** The classifier is JSON-object-aware. If `ccanvil.json` ever contains top-level arrays (it doesn't currently), the superset-check semantics would need extension. Out of scope; capture as a follow-up if such a structure is ever introduced.
- **Auto-commit.** The subcommand applies the resolution and updates the lockfile via `pull-apply`, but does NOT git-commit. The caller (operator or a higher-level broadcast wrapper) decides when to commit. Consistent with `pull-apply`'s existing contract.

## Implementation Notes

- **Algorithm, in pseudocode:**
  ```
  if not in a node: exit 2
  hub_path = read lockfile.hub_path
  local_file = .claude/ccanvil.json
  hub_file = $hub_path/.claude/ccanvil.json
  if neither file exists: emit "no-conflict", exit 0
  if local_hash == hub_hash: emit "take-hub" (calls pull-apply <file> take-hub), exit 0
  hub_keys, local_keys = jq -S 'paths' on each
  if hub_keys is subset of local_keys AND for every k in hub: local[k] == hub[k]:
    emit "keep-local" (calls pull-apply <file> keep-local), exit 0
  if local removed keys hub has: emit "requires-review" with removed_keys, exit 3
  else: emit "requires-review" with divergent_keys, exit 3
  ```
- **Reuse existing primitives.** Compute hashes via `file_hash` helper (already in `ccanvil-sync.sh`). Apply via `cmd_pull_apply <file> take-hub` / `keep-local`. Don't re-implement file copy or lockfile mutation.
- **Test fixture pattern.** Tests create a tmpdir hub and a tmpdir node, both with stub `.claude/ccanvil.json` and matching lockfile entries. Each test runs `broadcast-resolve-auto` in the node and asserts on stdout JSON + file state.
- **JSON output schema (terse for grep-ability):**
  ```json
  {
    "file": ".claude/ccanvil.json",
    "resolution": "take-hub|keep-local|requires-review|no-conflict",
    "applied": true|false,
    "reason": "content-identical|local-superset-of-hub|value-divergence|local-removed-keys|no-conflict",
    "hub_hash": "<sha>",
    "local_hash": "<sha>",
    "divergent_keys": ["..."]   // only when requires-review with value-divergence
    "removed_keys": ["..."]     // only when requires-review with local-removed-keys
  }
  ```

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
