# Implementation Plan: Extend INIT_GITHUB_TEMPLATES helper to cmd_diff + cmd_push_candidates

> Feature: bts-494-extend-helper-to-diff-and-push-candidates
> Work: linear:BTS-494
> Created: 1778885000
> Spec hash: a10cf1ad
> Based on: docs/spec.md

## Objective

Route `cmd_diff` (4 call sites) and `cmd_push_candidates` (1 call site) through the existing `_resolve_hub_relpath_for_lockfile_key` helper so INIT_GITHUB_TEMPLATES-mapped lockfile entries resolve to their template-source paths instead of failing with "File not in hub" or silent has_diff:false.

## Sequence

### Step 1: New bats file + AC-1/AC-2 red tests

* **Test:** New file `hub/tests/diff-push-init-templates-mapping.bats`. Mirror BTS-493's setup pattern — `setup_hub_with_template` (mktemp + populate `$HUB/.ccanvil/templates/github/workflows/ccanvil-checks.yml`), `setup_node_with_template_entry` (mktemp + populate `$NODE/.github/workflows/ccanvil-checks.yml` + jq-write lockfile with hub_source=$HUB and entry origin=hub status=clean), strict-mode `teardown` with `if [[ -n "${HUB:-}" ]]; then ... fi` blocks. Two tests: AC-1 (hub identical to local → `cmd_diff <dest>` emits `--- hub:` and `+++ local:` headers, NO "File not in hub" on stdout) and AC-2 (hub differs → headers + non-empty diff body). Use `run --separate-stderr` so the `scan_hub_files` empty-array warning doesn't corrupt stdout.
* **Implement:** None — confirm red.
* **Files:** `hub/tests/diff-push-init-templates-mapping.bats` (new).
* **Verify:** `bats hub/tests/diff-push-init-templates-mapping.bats` shows 2/2 fail with the expected "File not in hub" output.

### Step 2: cmd_diff specific-file refactor → AC-1 + AC-2 green

* **Test:** Re-run the file from Step 1.
* **Implement:** In cmd_diff ([ccanvil-sync.sh:1445](<http://ccanvil-sync.sh:1445>)), the existing `local hub_file="$hub_source/$file"` becomes `local hub_file="$hub_source/$(_resolve_hub_relpath_for_lockfile_key "$file")"`. Then at line 1460, replace `diff --unified "$hub_source/$file" "$file"` with `diff --unified "$hub_file" "$file"` (DRY — reuse the local). The `[[ ! -f "$hub_file" ]]` check at 1446 already consumes $hub_file; no further change needed there.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`.
* **Verify:** AC-1 + AC-2 green. AC-1, AC-2.

### Step 3: AC-3 error-path preservation

* **Test:** Add test: tmpdir hub does NOT have the template file (operator-deleted shape); lockfile still has the entry. Run `cmd_diff <dest>`. Assert: stdout contains `"File not in hub: .github/workflows/ccanvil-checks.yml"`, exit 0. Confirms passthrough still resolves to the template path; the `! -f` guard correctly catches genuine absence.
* **Implement:** None — Step 2's helper integration is sufficient (helper returns the template path; `! -f` catches it as missing).
* **Files:** `hub/tests/diff-push-init-templates-mapping.bats`.
* **Verify:** test green. AC-3.

### Step 4: cmd_diff diff-all refactor + AC-4

* **Test:** Add test: tmpdir node with lockfile entry status=`modified`, hub_hash from v1, local now contains v2; hub template at the template path contains v3 (so local hash ≠ hub_hash AND local content differs from hub template). Run `cmd_diff` (no arg). Assert: stdout contains `=== .github/workflows/ccanvil-checks.yml ===` AND non-empty diff body for that entry. Red first.
* **Implement:** In cmd_diff diff-all branch ([ccanvil-sync.sh:1471](<http://ccanvil-sync.sh:1471>) and :1473), replace both `$hub_source/$f` with the resolved form. Pattern: introduce a `local hub_file_for_f="$hub_source/$(_resolve_hub_relpath_for_lockfile_key "$f")"` once inside the while-loop body before the `[[ -f $hub_source/$f ]]` check; reuse for both the `-f` test and the `diff --unified` invocation.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/diff-push-init-templates-mapping.bats`.
* **Verify:** AC-4 green.

### Step 5: cmd_push_candidates refactor + AC-5

* **Test:** Tmpdir node with lockfile entry status=`modified` (NOT clean — line 2599 filters out clean entries), local file content differs from hub template. Run `cmd_push_candidates`. Assert: JSON array length 1; the entry's `{file, status, has_diff}` equals `{file: ".github/workflows/ccanvil-checks.yml", status: "modified", has_diff: true}`. Red first.
* **Implement:** In cmd_push_candidates ([ccanvil-sync.sh:2611](<http://ccanvil-sync.sh:2611>)), replace `local hub_file="$hub_source/$file"` with the resolved form (same one-liner as the other call sites).
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/diff-push-init-templates-mapping.bats`.
* **Verify:** AC-5 green.

### Step 6: AC-6 regression guard (non-template entries)

* **Test:** Three sub-tests using a non-template lockfile entry (`.claude/rules/tdd.md`). Setup helpers `setup_hub_with_rule` + `setup_node_with_rule_entry` (mirror BTS-493). (a) cmd_diff specific-file on clean entry → empty diff (no `--- hub:` because content identical, just exit 0). Actually for a clean entry both sides identical: diff --unified emits no body; assert exit 0 and `--- hub:` header IS still present (cmd_diff always emits headers for present files). (b) cmd_diff diff-all on a `modified` non-template entry with content divergence → emits `=== .claude/rules/tdd.md ===` + diff body. (c) cmd_push_candidates on modified non-template entry → JSON entry has_diff:true. Confirms helper passthrough doesn't perturb the dominant path.
* **Implement:** None — passthrough handles it.
* **Files:** `hub/tests/diff-push-init-templates-mapping.bats`.
* **Verify:** 3 green sub-tests. AC-6.

### Step 7: Manifest depends-on additions

* **Test:** `bash .ccanvil/scripts/module-manifest.sh validate --json` returns status:ok, drift:\[\], coverage 197/197.
* **Implement:** In cmd_diff @manifest block ([ccanvil-sync.sh](<http://ccanvil-sync.sh>) \~1419-1434), add `# depends-on: _resolve_hub_relpath_for_lockfile_key` in alphabetical position; add `# anchor: BTS-494 (helper resolution)`. Same in cmd_push_candidates @manifest block. No new allowlist entry needed — helper already allowlisted from BTS-493.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh` (2 manifest blocks).
* **Verify:** validate --json clean. AC-7.

### Step 8: Full bats regression

* **Test:** `bash .ccanvil/scripts/docs-check.sh test-suite-run --project-dir . --parallel --progress`. Confirm all green including BTS-493's `pull-plan-init-templates-mapping.bats` (regression). 2329 + 9 new = 2338 expected.
* **Implement:** None — pure regression check.
* **Files:** N/A.
* **Verify:** dispatcher exit 0, all-green summary. AC-8.

## Risks

* **Helper-name collision in diff-all loop.** The diff-all branch uses `$f` (not `$file`) as the loop variable. Using a local hub_file_for_f (or rebinding hub_file) cleanly avoids any shadowing with the specific-file branch's `hub_file`.
* **AC-1 header assertion.** `cmd_diff` always emits `--- hub:` and `+++ local:` headers (line 1458-1459) even when the diff body is empty (identical content). Assert presence of the headers AND absence of "File not in hub" — both shapes together capture the AC.
* **AC-5 status:modified setup.** The fixture must explicitly set lockfile status to `modified` because cmd_push_candidates' line 2599 filters out `clean` entries before reaching the hub_file lookup. Without this the test would assert on an empty array.
* **Test fixture isolation.** Each test mktemps its own hub + node; teardown uses strict-mode `if [[ ]]; then ... fi` blocks (the `[[ ]] && rm -rf` shape breaks under `set -e` — confirmed BTS-488 + BTS-493 incident).

## Definition of Done

- [ ] All 8 ACs from spec pass (new bats file).
- [ ] BTS-493's `hub/tests/pull-plan-init-templates-mapping.bats` still 15/15 green (regression).
- [ ] Full bats suite green via dispatcher.
- [ ] `module-manifest.sh validate --json` returns status:ok, drift:\[\], coverage:197/197.
- [ ] Code reviewed (/review) — code-reviewer + security-audit + self-review.
- [ ] Live-API gate: N/A (pure filesystem + lockfile ops).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
