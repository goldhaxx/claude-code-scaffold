# Feature: Atomic cmd_index write under --parallel

> Feature: bts-510-atomic-cmd-index-write
> Work: linear:BTS-510
> Created: 1779146173
> Subject: Atomic cmd_index write under --parallel
> Status: In Progress

## Summary

`cmd_index` in `.ccanvil/scripts/module-manifest.sh` regenerates `.ccanvil/state/manifests.json` from source-dir walks. It writes to a fixed intermediate filename `$out.tmp` then `mv`s to `$out`. Under `bats --jobs 12`, multiple test workers invoke `cmd_index` concurrently (transitively, via `cmd_graph` and `cmd_validate`). All workers race on the SAME `$out.tmp` filename — one's partial write clobbers another's, and the surviving `mv` propagates corrupted JSON. A reader (`cmd_graph`'s downstream lookups) sees zero cross-cluster edges instead of the expected ≥1, producing the BTS-510 flake (1 in \~2462 tests, observed at BTS-508 pre-merge gate).

Fix: replace the fixed `$out.tmp` filename with a per-invocation `mktemp "$out.XXXXXX"`. Each writer produces its own complete tmp; the final `mv` is atomic per writer; readers see either the pre-state or a complete post-state — never a partial write.

## Job To Be Done

**When** a parallel bats run invokes `cmd_index` (directly or transitively via `cmd_graph` / `cmd_validate`) from multiple workers,
**I want to** see deterministic, complete manifests.json content,
**So that** downstream consumers (graph emitter, drift detector) never observe a partial-write artifact and the test suite is flake-free.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_index` writes to a per-invocation unique intermediate via `mktemp "$out.XXXXXX"` before the final `mv "$tmp" "$out"`. The fixed-filename `$out.tmp` pattern is gone — `grep -n '"\$out\.tmp"' .ccanvil/scripts/module-manifest.sh` returns no matches in `cmd_index`.
- [ ] **AC-2: Given** 12 concurrent `cmd_index` invocations against a shared `.ccanvil/state/manifests.json` and a populated source-dir set, **when** a reader interleaves 100 iterations of `jq -e . < .ccanvil/state/manifests.json` against the writers, **then** every snapshot parses as valid JSON (zero parse failures across 1200 reads). Content-correctness under concurrent writes is established separately by AC-3's 100-run pass of the existing `.cross_cluster_edges` assertion; this AC isolates the partial-write failure mode.
- [ ] **AC-3 (regression guard):** Elimination is established structurally by AC-1: per-invocation unique intermediates remove the shared-filename race entirely — concurrent writers cannot clobber each other's intermediates, and `rename(2)` is atomic per the kernel, so readers see either pre-state or a complete post-state. As empirical verification of the structural property, `hub/tests/module-manifest-graph.bats` line 31 (`tiny allowlist with command→agent edge → 1 cross_cluster_edge`) fails zero times across 100 consecutive `bats-report.sh --parallel` runs. Binary pass/fail: any failure within the window — same race or otherwise — fails this AC.
- [ ] **AC-4 (error path):** Every `mktemp` call in `cmd_index` is guarded. There are two post-fix: the existing accumulator `tmp=$(mktemp)` (line 1278) and the new atomic-write intermediate `out_tmp=$(mktemp "$out.XXXXXX")`. If either fails (e.g., `/tmp` full or unwritable), `cmd_index` exits non-zero with a distinct stderr error identifying *which* `mktemp` failed (accumulator vs. final-write). No silent fallthrough — neither an unwritten `$out.tmp` rename nor an empty-accumulator `{}` shall reach `$out`.
- [ ] **AC-5 (edge):** The full module-manifest test suite (`bats hub/tests/module-manifest*.bats`) passes with zero regressions.
- [ ] **AC-6:** The `cmd_index` manifest block contains the literal contract line `# contract: atomic-write-via-mktemp-and-mv` and no longer contains `# contract: atomic-write-via-mv`. Verifiable by `grep -F '# contract: atomic-write-via-mktemp-and-mv' .ccanvil/scripts/module-manifest.sh` returning exactly 1 match within the `cmd_index` block, and `grep -F '# contract: atomic-write-via-mv' .ccanvil/scripts/module-manifest.sh` returning 0 matches in that block. Manifest-validate stays clean.
- [ ] **AC-7:** Existing `mkdir -p "$(dirname "$out")"` is preserved (state dir may not exist on fresh clones).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified — `cmd_index` uses `mktemp` for intermediate; manifest contract anchor updated |
| `hub/tests/module-manifest-parallel.bats` | New — parallel-stress test exercising AC-2/AC-3 |

## Dependencies

* **Requires:** Nothing. `mktemp` is POSIX, available everywhere bats runs.
* **Blocked by:** Nothing. Pre-existing substrate bug, independent ship.

## Out of Scope

* Auditing other `cmd_*` functions in `module-manifest.sh` for the same shared-tmp pattern. The drift surfaced once in `cmd_index`; broader sweep is a separate ticket if more flakes appear.
* Refactoring `cmd_index` further (e.g., dedup writers via filelock). The mktemp fix is sufficient because writers are deterministic — concurrent overwrites converge on identical content.
* Adding instrumentation to confirm the hypothesis (the original DIAGNOSE first-ship). AC-2 + AC-3 verification under parallel-stress doubles as the diagnostic confirmation: if the fix eliminates the flake, the hypothesis was correct.

## Implementation Notes

* Same shape as the BTS-508 state writers (`bats-report.sh` and `module-manifest.sh validate` writers): `tmp=$(mktemp "$out.XXXXXX") || return <rc>; … > "$tmp"; mv "$tmp" "$out"`. Keep the existing `mkdir -p "$(dirname "$out")"` line above the mktemp.
* The existing `RETURN` trap that cleans up `$tmp` (line 1280) needs to expand to cover the new intermediate too — either add it to the trap list or rely on the new mktemp variable being captured before any `return` paths.
* `mktemp` on macOS creates the file with mode 0600; not a concern (state dir is operator-private).
* Parallel-stress test pattern: spawn N background `cmd_index` calls in setup; in main test phase, repeatedly read `$out` and `jq -e .` each snapshot; assert zero parse failures. Keep N≤12 to match the production bats jobslot.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
