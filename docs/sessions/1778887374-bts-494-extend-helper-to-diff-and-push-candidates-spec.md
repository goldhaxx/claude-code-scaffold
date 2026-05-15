# Feature: Extend INIT_GITHUB_TEMPLATES helper to cmd_diff + cmd_push_candidates

> Feature: bts-494-extend-helper-to-diff-and-push-candidates
> Work: linear:BTS-494
> Created: 1778884585
> Subject: Extend INIT_GITHUB_TEMPLATES helper to cmd_diff + cmd_push_candidates
> Status: In Progress

## Summary

BTS-493 shipped a bash-3.2-safe helper (`_resolve_hub_relpath_for_lockfile_key`) and routed `cmd_pull_plan`, `cmd_pull_auto`, `cmd_pull_apply` through it. Two more consumers in `ccanvil-sync.sh` use the same raw `hub_file="$hub_source/$file"` pattern and inherit the same bug for `INIT_GITHUB_TEMPLATES`-mapped lockfile entries: `cmd_diff` (lines 1445/1460/1471/1473) and `cmd_push_candidates` (line 2611). Today the user-visible failure is `ccanvil-sync.sh diff .github/workflows/ccanvil-checks.yml` emitting "File not in hub" instead of a real diff on every node that received the BTS-488 heal. `cmd_push_candidates` is a latent silent-misclassification (template entries surface as `has_diff: false` even when they differ from hub). This spec routes both consumers through the existing helper, closing the INIT_GITHUB_TEMPLATES path-resolution story across all five sync-side surfaces.

## Job To Be Done

**When** I inspect or push template-mapped lockfile entries via `ccanvil-sync.sh diff` or `push-candidates`,
**I want to** see the same correct hub-side resolution that `pull-plan` / `pull-auto` / `pull-apply` already do,
**So that** review and promotion flows give true answers — not "File not in hub" for files the hub demonstrably owns at the template path.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_diff .github/workflows/ccanvil-checks.yml` on a fixture node whose lockfile entry hash matches the hub template — emits the unified diff header (`--- hub:` / `+++ local:`) and exit 0. No "File not in hub" output anywhere on stdout.
- [ ] **AC-2:** `cmd_diff .github/workflows/ccanvil-checks.yml` on a fixture where hub template content differs from local — emits `--- hub:` / `+++ local:` headers plus a non-empty `diff --unified` body capturing the actual content difference.
- [ ] **AC-3:** Error-path preservation. `cmd_diff .github/workflows/ccanvil-checks.yml` when the hub-side template is genuinely absent (operator deleted `.ccanvil/templates/github/workflows/ccanvil-checks.yml`) — STILL emits "File not in hub: .github/workflows/ccanvil-checks.yml" and exit 0. Removal semantics preserved.
- [ ] **AC-4:** `cmd_diff` no-arg form (diff-all) on a fixture with a `modified` template-mapped lockfile entry whose local file differs from the hub template — emits `=== .github/workflows/ccanvil-checks.yml ===` header + a non-empty diff body for that file. Never silently skips.
- [ ] **AC-5:** `cmd_push_candidates` on a fixture with a `modified`-status template-mapped lockfile entry whose local differs from the hub template — emits one JSON entry `{file, status, has_diff: true}`. Status `clean` entries are still filtered out (per existing line 2599 logic).
- [ ] **AC-6:** Regression guard — `cmd_diff` and `cmd_push_candidates` on a non-template lockfile entry (e.g., `.claude/rules/tdd.md`) behave identically before and after the change. Pre-existing diff and push-candidates output unchanged.
- [ ] **AC-7:** Manifest registration — `cmd_diff` and `cmd_push_candidates` `@manifest` blocks each gain `depends-on: _resolve_hub_relpath_for_lockfile_key` (alphabetical position). `module-manifest.sh validate --json` returns `status: ok`, drift `[]`.
- [ ] **AC-8:** Full bats suite (`docs-check.sh test-suite-run --parallel`) returns green; no regression in pull-plan-init-templates-mapping.bats from BTS-493.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified: 4 call sites in cmd_diff (lines \~1445/1460/1471/1473) + 1 call site in cmd_push_candidates (line \~2611); 2 @manifest depends-on additions |
| `hub/tests/diff-push-init-templates-mapping.bats` | New: fixtures + 6 tests covering AC-1 through AC-6 |

## Dependencies

* **Requires:** `_resolve_hub_relpath_for_lockfile_key` helper (BTS-493, shipped on main as `8fa19dd`). Helper interface is stable and bash-3.2-safe.
* **Blocked by:** Nothing.

## Out of Scope

* BTS-489 (init-time lockfile registration gap for github templates) — orthogonal upstream bug; today only `ccanvil-checks.yml` reaches the lockfile via BTS-488's heal.
* Push direction (`cmd_push_apply` lines 2685/2689) — push targets that ARE `INIT_GITHUB_TEMPLATES` entries don't exist by construction (template entries are hub-owned, not node-promoted); routing those sites through the helper would be incorrect.
* `scan_hub_files` and the `new files in hub` block of `cmd_pull_plan` (line 2114/2123) — these walk the hub tree directly and emit hub-relative paths, not lockfile-key paths; no helper consultation needed.

## Implementation Notes

* **Refactor pattern:** at each of the 5 affected lines, replace `"$hub_source/$file"` (or `"$hub_source/$f"`) with `"$hub_source/$(_resolve_hub_relpath_for_lockfile_key "$file")"`. For `cmd_diff`'s specific-file branch, introduce `local hub_file="$hub_source/$(_resolve_hub_relpath_for_lockfile_key "$file")"` once and reuse for the `[[ ! -f ]]` check AND the `diff --unified` invocation (DRY — line 1460 currently re-expands `$hub_source/$file` instead of using `$hub_file`).
* **Bats fixture pattern:** mirror BTS-493's `hub/tests/pull-plan-init-templates-mapping.bats` setup helpers (`setup_hub_with_template` / `setup_node_with_template_entry` / strict-mode teardown). Use `run --separate-stderr` to isolate stdout for JSON parsing (BTS-493 lesson — `scan_hub_files` empty-array unbound-variable warning to stderr would corrupt JSON-mixed stdout).
* **Live-API risk:** None — pure filesystem + lockfile mutations.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
