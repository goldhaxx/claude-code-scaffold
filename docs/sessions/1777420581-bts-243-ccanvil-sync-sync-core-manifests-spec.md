# Feature: [ccanvil-sync.sh](<http://ccanvil-sync.sh>) sync-core cluster manifests

> Feature: bts-243-ccanvil-sync-sync-core-manifests
> Work: linear:BTS-243
> Created: 1777416492
> Subject: [ccanvil-sync.sh](<http://ccanvil-sync.sh>) sync-core cluster manifests
> Status: In Progress

## Summary

Manifest rollout Session 4 per `docs/manifest-rollout.md`. Add `# @manifest` blocks (BTS-239 substrate, 10-key shape) for the 22 cmd\_\* in `.ccanvil/scripts/ccanvil-sync.sh` that comprise the sync-core cluster: init, status, diff/hash/merge primitives, track/classify/pre-check, pull cluster, push + promote/demote. Coverage-only ship; no function-body changes. Allowlist 59 → 81. Drift 0 throughout.

## Job To Be Done

**When** I extend Layer 2 (Self-Describing Systems) coverage to the sync substrate,
**I want to** declare 22 inline manifests + inline failure/side-effect markers across `ccanvil-sync.sh` and grow the allowlist to 81,
**So that** every sync-core primitive carries machine-readable purpose / contract / failure semantics, drift-guard catches future regressions structurally, and `/recall` reports `81 / 81, drift: 0`.

## Acceptance Criteria

- [ ] **AC-1:** All 22 cmd\_\* in scope declare a complete `# @manifest` block above the function definition. Required keys present: `purpose`, `input`, `output`, `side-effect`, `failure-mode`, `contract`, `anchor`. Conditional keys (`caller`, `depends-on`, `routes-by`) declared where applicable.
- [ ] **AC-2:** Every declared `failure-mode` line has a matching `# @failure-mode: <id>` source marker at the failing return/exit line.
- [ ] **AC-3:** Every declared `side-effect` line has a matching `# @side-effect: <id>` source marker at the mutating line.
- [ ] **AC-4:** `.ccanvil/manifest-allowlist.txt` appended with 22 entries grouped under `# BTS-243 — Session 4: ccanvil-sync.sh sync-core cluster.` plus per-batch sub-headers (init+status / diff-hash-merge / track-classify-pre-check / pull / push-promote-demote).
- [ ] **AC-5:** `bash .ccanvil/scripts/module-manifest.sh validate --json` reports `coverage: 81/81` and `(drift | length) == 0`.
- [ ] **AC-6:** Bats suite passes — no regression. No new tests this ship (coverage-only).
- [ ] **AC-7:** PR squash-merge title = `feat(bts-243-ccanvil-sync-sync-core-manifests): ccanvil-sync.sh sync-core cluster manifests`.
- [ ] **AC-8:** Edge — declared `caller` entries that don't word-boundary match in the target file produce a drift warning at validate; all such warnings resolved before commit.
- [ ] **AC-9:** Live-AC — next `/recall` after merge surfaces `Manifest coverage: 81 / 81 (allowlist), drift: 0`.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — 22 `# @manifest` blocks + inline failure-mode/side-effect markers added |
| `.ccanvil/manifest-allowlist.txt` | Modified — +22 entries with section headers |

## Dependencies

* **Requires:** BTS-239 (manifest substrate), BTS-240 (markdown parser, not used here but landed prior), BTS-241/242 (pattern reference for batched coverage shipping).
* **Blocked by:** none.

## Out of Scope

* Part 2 — stack + registry cluster (21 cmd\_\*). Ships as Session 5 in a separate ticket.
* Function-body changes. Coverage-only ship; no behavioral edits.
* New tests. The drift-guard structural check (existing) is the verification surface.
* Markdown manifests. Sessions 9–10 in the rollout.

## Implementation Notes

* *In-scope cmd\_* (22):\* Batch 1 init+status — cmd_init, cmd_init_preflight, cmd_init_apply, cmd_retrofit_check, cmd_status. Batch 2 diff/hash/merge — cmd_changelog, cmd_diff, cmd_hash, cmd_section_merge, cmd_node_only. Batch 3 track/classify/pre-check — cmd_track, cmd_classify, cmd_pre_check. Batch 4 pull — cmd_pull_plan, cmd_pull_auto, cmd_pull_apply, cmd_pull_finalize. Batch 5 push+promote/demote — cmd_push_candidates, cmd_push_apply, cmd_push_finalize, cmd_promote, cmd_demote.
* **Format:** Same as BTS-241/242. Manifest block uses 10-key shape; `failure-mode` line is `<id> | exit=N | visible=<phrase> | mitigation=<phrase>`. Markers are line-leading `# @failure-mode: <id>` / `# @side-effect: <id>`.
* **Quality gate:** Per-batch validate-fix-commit loop (drift-guard catches phantom callers, missing markers, wrong dep names). Pattern reference: `feedback_drift_guard_compounds_quality_across_sessions`.
* **Caller resolution:** Word-boundary grep against target files. Cross-file callers (e.g. cmd_pull_apply called from cmd_pull_finalize) verify by searching the body. Use `skill:/<name>` form for skill callers, path form for command files.
* **AC-29 grep guard awareness:** Per `feedback_self_describing_doc_strings_avoid_pattern_literals`, manifest doc strings must avoid literal patterns the legacy-refs scanner enforces. Reword if any `purpose:` line accidentally contains retired vocab.
* **Live-API gate:** none — all primitives operate on local files. No live-call validation needed.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
