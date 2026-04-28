# Implementation Plan: [ccanvil-sync.sh](<http://ccanvil-sync.sh>) sync-core cluster manifests

> Feature: bts-243-ccanvil-sync-sync-core-manifests
> Work: linear:BTS-243
> Created: 1777416492
> Spec hash: 13b53163
> Based on: docs/spec.md

## Objective

Add `# @manifest` blocks + inline failure-mode/side-effect markers for 22 cmd\_\* in `.ccanvil/scripts/ccanvil-sync.sh` (sync-core cluster) across 5 batches; grow allowlist 59 → 81; drift 0 throughout.

## Sequence

Coverage-only ship — no new tests, no body edits. Each batch follows the BTS-241/242 cycle: read function → compose manifest + add inline markers → append allowlist entries → `module-manifest.sh validate --json` → fix any drift → commit.

### Step 1: Batch 1 — init + status (5 manifests)

* **Read:** `cmd_init` (392-538), `cmd_init_preflight` (539-735), `cmd_init_apply` (736-926), `cmd_retrofit_check` (927-932), `cmd_status` (933-1032).
* **Implement:** For each, declare 10-key manifest above the function. Add `# @failure-mode: <id>` markers at all `return N`/`exit N` lines where N != 0. Add `# @side-effect: <id>` markers at write/git/network mutation lines. Cross-reference callers via word-boundary grep against [ccanvil-sync.sh](<http://ccanvil-sync.sh>) + skill files.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh` (manifest + markers), `.ccanvil/manifest-allowlist.txt` (5 entries under `# Batch 1 — init + status.`).
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate --json | jq '.coverage, (.drift|length)'` — coverage 64/64, drift 0.
* **Commit:** `feat(bts-243): batch 1 — init + status manifests`.

### Step 2: Batch 2 — diff/hash/merge primitives (5 manifests)

* **Read:** `cmd_changelog` (1033-1080), `cmd_diff` (1081-1122), `cmd_hash` (1123-1127), `cmd_section_merge` (1193-1257), `cmd_node_only` (1258-1280).
* **Implement:** Same 10-key shape; small primitives (cmd_hash is 5 lines) get terse but complete manifests. Verify cross-callers (cmd_diff often consumed by cmd_pull_plan; cmd_hash by cmd_lock_update).
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`, `.ccanvil/manifest-allowlist.txt` (Batch 2 sub-header).
* **Verify:** validate — 69/69, drift 0.
* **Commit:** `feat(bts-243): batch 2 — diff/hash/merge manifests`.

### Step 3: Batch 3 — track/classify/pre-check (3 manifests)

* **Read:** `cmd_track` (1281-1304), `cmd_classify` (1305-1325), `cmd_pre_check` (1326-1389).
* **Implement:** track + classify operate on the lockfile + classification-rules; pre-check is the hub-vs-node consistency gate. Manifest captures the routing semantics.
* **Files:** same.
* **Verify:** 72/72, drift 0.
* **Commit:** `feat(bts-243): batch 3 — track/classify/pre-check manifests`.

### Step 4: Batch 4 — pull cluster (4 manifests)

* **Read:** `cmd_pull_plan` (1390-1513), `cmd_pull_auto` (1514-1569), `cmd_pull_apply` (1570-1737), `cmd_pull_finalize` (1738-1820).
* **Implement:** Pull cluster has rich failure-mode (network failures, conflicts, stale refs). Each manifest enumerates the distinct exit semantics. Cross-caller chain: pull_plan → pull_apply → pull_finalize.
* **Files:** same.
* **Verify:** 76/76, drift 0.
* **Commit:** `feat(bts-243): batch 4 — pull cluster manifests`.

### Step 5: Batch 5 — push + promote/demote (5 manifests)

* **Read:** `cmd_push_candidates` (1821-1866), `cmd_push_apply` (1867-1924), `cmd_push_finalize` (1925-1977), `cmd_promote` (1978-2027), `cmd_demote` (2028-2053).
* **Implement:** Push has the classification gate (generalizable vs node-specific) — manifest captures the classification routes-by + the multi-shape failure modes. promote/demote have hub-side write side-effects.
* **Files:** same.
* **Verify:** 81/81, drift 0.
* **Commit:** `feat(bts-243): batch 5 — push + promote/demote manifests`.

### Step 6: Final validate + bats run

* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate --json` → `coverage: 81/81, drift: 0`.
* **Verify:** `bash .ccanvil/scripts/bats-report.sh --parallel` — all tests passing (no regression).

## Risks

* **AC-29 grep guard false-positive on manifest doc strings.** Mitigation: per `feedback_self_describing_doc_strings_avoid_pattern_literals`, scan composed `purpose:` lines for retired vocab (`/catchup`, `/checkpoint`, `docs/checkpoint.md`) before validate. Reword vocab-free if matched.
* **Phantom callers across mega-script boundaries.** [ccanvil-sync.sh](<http://ccanvil-sync.sh>) callers are mostly internal + skill files; verify each via word-boundary grep. Drift-guard catches anything missed.
* **Marker placement on inline returns.** Same-line case statements (e.g. `*) return 1`) require splitting onto separate lines so `# @failure-mode: <id>` marker becomes line-leading.
* **Subprocess tool dependencies.** Each manifest's `depends-on` line should grep the body for actual command invocations (jq, sed, awk, gh, git, curl). Don't declare what's not called.

## Definition of Done

- [ ] All 22 cmd\_\* in scope have complete `# @manifest` blocks (AC-1).
- [ ] All declared failure-modes have inline `# @failure-mode:` markers (AC-2).
- [ ] All declared side-effects have inline `# @side-effect:` markers (AC-3).
- [ ] Allowlist appended with 22 entries grouped under `# BTS-243 — Session 4` (AC-4).
- [ ] `module-manifest.sh validate --json` reports 81/81, drift 0 (AC-5).
- [ ] Bats suite passes — no regression (AC-6).
- [ ] PR title set to `feat(bts-243-ccanvil-sync-sync-core-manifests): ccanvil-sync.sh sync-core cluster manifests` at /pr time (AC-7).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
