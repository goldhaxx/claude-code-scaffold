# Feature: Deterministic Layer 3 ramp — diff-vs-manifest

> Feature: bts-268-deterministic-layer-3-ramp
> Work: linear:BTS-268
> Created: 1777691396
> Subject: Deterministic Layer 3 ramp — diff-vs-manifest
> Status: In Progress

## Summary

Today Layer 3 (Comprehension Gate at PR time) is operator-attention-dependent: the `code-reviewer.md` agent and `/review` skill carry prose nudges describing four manifest-drift classes (new caller / new depends-on / new exit path / new side-effect not declared), but enforcement is the agent's pattern-matching, not a deterministic gate. This ticket adds `module-manifest.sh diff-vs-manifest` — a substrate primitive that consumes a unified-diff (path or stdin) and emits structured `{path, id, drift_type, value}` JSON for each delta. `/review` and `/pr` consume the envelope as a BLOCKING gate; the prose nudge becomes fallback.

## Job To Be Done

**When** an operator runs `/review` or `/pr` on a branch whose diff touches manifested substrate,
**I want to** get a deterministic, machine-checkable list of manifest drift classes the diff introduces (without relying on the reviewer agent's pattern recognition),
**So that** Layer 3 enforcement scales without operator-attention drift or false-positive accumulation.

## Acceptance Criteria

- [ ] **AC-1:** `bash .ccanvil/scripts/module-manifest.sh diff-vs-manifest --diff <path>` (or `--diff -` for stdin) emits JSON envelope `{drift: [{path, id, drift_type, value}], status: "ok"|"drift"}` to stdout. Exit 0 on no drift; exit 2 on any drift detected.
- [ ] **AC-2 (new-caller):** Given a unified diff that adds a file or function under `.claude/{skills,commands,rules,agents}/` or `.ccanvil/scripts/` whose body invokes a manifested primitive `cmd_X` (word-boundary match), AND the primitive's manifest `caller:` field does NOT list the new caller path, Then `diff-vs-manifest` emits `{drift_type: "new-caller-not-declared", path: <primitive-path>:<id>, value: <new-caller-path>}`.
- [ ] **AC-3 (new-depends-on):** Given a diff that ADDS a line inside a manifested primitive's body invoking a script or helper (e.g., `bash linear-query.sh ...`, `jq ...`, `_helper_fn`) that is NOT in the manifest's `depends-on:` array, Then emit `{drift_type: "new-depends-on-not-declared", path, id, value: <added-dep>}`.
- [ ] **AC-4 (new-exit-path):** Given a diff that ADDS a `return N` or `exit N` line (N != 0) inside a manifested primitive's body, AND no `failure-mode: <id> | exit=N | …` entry in the manifest matches that N, Then emit `{drift_type: "new-exit-path-not-declared", path, id, value: <exit-code>}`.
- [ ] **AC-5 (new-side-effect):** Given a diff that ADDS a `# @side-effect: <id>` marker inside a manifested primitive's body, AND `<id>` is NOT in the manifest's `side-effect:` array, Then emit `{drift_type: "new-side-effect-not-declared", path, id, value: <marker-id>}`.
- [ ] **AC-6 (clean diff):** Given a diff that touches NO manifested paths (e.g., docs-only, test-only-on-non-manifested-substrate), Then `diff-vs-manifest` exits 0 with `{drift: [], status: "ok"}`.
- [ ] **AC-7 (error):** Given `--diff <path>` points at a non-existent file, Then stderr surfaces `ERROR: diff file not found: <path>` and exit code is 2.
- [ ] **AC-8:** `.claude/commands/review.md` Step 0 (manifest pre-flight) is augmented to ALSO run `diff-vs-manifest --diff <(git diff main...HEAD)` and surface its `drift[]` envelope. When any drift is reported, the review reports it as BLOCKING regardless of agent commentary.
- [ ] **AC-9:** New bats test file `hub/tests/module-manifest-diff-vs-manifest.bats` covers AC-1 through AC-7 with fixture diff files in `hub/tests/fixtures/manifest/diffs/`. At least one fixture per drift class.
- [ ] **AC-10:** New `cmd_diff_vs_manifest` primitive added to `.ccanvil/manifest-allowlist.txt` with complete `# @manifest` block — drift-guard remains 100% (185 → 186).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified — add `cmd_diff_vs_manifest` + dispatch entry |
| `.claude/commands/review.md` | Modified — augment Step 0 manifest pre-flight to invoke diff-vs-manifest |
| `hub/tests/module-manifest-diff-vs-manifest.bats` | New — bats coverage for AC-1..7 |
| `hub/tests/fixtures/manifest/diffs/*.diff` | New fixtures (one per drift class) |
| `.ccanvil/manifest-allowlist.txt` | Modified — add `cmd_diff_vs_manifest` entry |

## Dependencies

* **Requires:** [module-manifest.sh](<http://module-manifest.sh>) substrate (BTS-239) + cmd_extract / cmd_validate in their current shape; manifest-allowlist.txt populated (185 entries today).
* **Blocked by:** none. The 1-week verification routine `trig_01V3eu7T8WurLRzg1iSPSA3j` (fires 2026-05-06) produces tuning evidence post-ship — it does NOT gate this ticket.

## Known Limitations (first ramp — tolerable, follow-up tickets if friction)

* **Cross-file primitive-name collision.** When two files in the allowlist define the same `cmd_X` (e.g., both `module-manifest.sh:cmd_validate` and `docs-check.sh:cmd_validate`), an added text mention in one file's diff flags as a new caller for the OTHER file's primitive. Heuristic limit; mitigation in follow-up: require dispatch-shape (`bash <path> <verb>` or `<primitive_path>` mention) before flagging.
* **Hunk-context misattribution on multi-commit branches.** Git's `@@ ... @@` context anchors to the function declaration that PRECEDES the hunk in the merge-base file. When a branch adds a NEW function later in the file, additions inside the new function get attributed to its preceding sibling. Surfaces as occasional misattributed drift on multi-commit feature branches. Mitigation in follow-up: brace-count attribution against the post-state file when hunk context is ambiguous.

## Out of Scope

* The Layer 3 cohesion graph (BTS-269 / L3-B) — separate sibling ticket.
* Manifest query helpers (BTS-270 / L3-C) — separate sibling ticket.
* Auto-suggesting manifest updates from drift (e.g., "add this caller, here's the snippet") — Phase 3 enhancement; this ship surfaces the drift only.
* Diff-vs-manifest invocation from CI on the GitHub side (workflow YAML). Local /review + /pr coverage is the first ramp; CI integration is BTS-21-territory.
* Retiring the [code-reviewer.md](<http://code-reviewer.md>) Layer 3 prose section. Keep it as fallback — when `diff-vs-manifest` returns drift, the prose helps the agent explain WHY in human terms; when the substrate misses an edge case the prose still catches it.

## Implementation Notes

* Pattern: `cmd_diff_vs_manifest` follows `cmd_extract` / `cmd_validate` shape — manifest block above, dispatch entry, pure bash + awk + grep (no python / yq / external diff parser deps).
* Diff parsing approach: walk `+++ b/<path>` headers to identify changed files; for each file in the manifest allowlist, walk added lines (`^+` not `^+++`) within hunks. Build a `{path: <bare-or-:fn>, added_lines: […]}` map per touched primitive.
* For new-caller detection: walk added lines in NON-manifested files (skills/commands/rules/agents/scripts/hooks) for `cmd_X\b` where `cmd_X` is on the allowlist; cross-reference against the primitive's existing `caller:` list (extract via `cmd_extract`).
* For new-depends-on / new-exit / new-side-effect: scope to added lines INSIDE manifested primitive bodies (use brace-counted body grep helpers `_function_body_grep` / `_target_body_grep` already in [module-manifest.sh](<http://module-manifest.sh>)).
* `--diff -` (stdin) for the /review and /pr piping case; `--diff <path>` for tests with fixture files.
* JSON envelope mirrors `cmd_validate`'s shape so consumers (review skill) read both with the same jq idioms.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
