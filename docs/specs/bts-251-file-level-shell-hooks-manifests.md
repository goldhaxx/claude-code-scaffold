# Feature: File-level shell + hooks manifests

> Feature: bts-251-file-level-shell-hooks-manifests
> Work: linear:BTS-251
> Created: 1777480188
> Subject: File-level shell + hooks manifests
> Status: Complete

## Summary

Per `docs/manifest-rollout.md` Session 8 — extend Layer 2 (Self-Describing Systems) coverage from function-level cmd_* primitives to **file-level** shell substrate. Adds 17 file-level manifests across 5 single-purpose scripts (`bats-lint.sh`, `bats-report.sh`, `fetch-license.sh`, `fix-cloudflare-certs.sh`, `security-audit.sh`) and 12 PreToolUse / SessionStart / SessionEnd hooks. Includes a substrate extension to `module-manifest.sh` so drift-guard's depends-on + marker checks work for files with no `${fn_id}()` declaration. Allowlist grows 134 → 151.

## Job To Be Done

**When** I'm reviewing a hook or single-purpose substrate script and need to know its contract (purpose, inputs, exit semantics, side-effects, callers),
**I want to** read a `# @manifest` block at the top of the file with the same field set used for cmd_* primitives,
**So that** cold-start comprehension and drift-guard quality enforcement extend uniformly across the entire shell substrate, not just the mega-scripts.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `_function_body_grep` falls back to whole-file grep when no `${fn_id}()` declaration is found in the file. Verified by a new bats test under `hub/tests/module-manifest-validate-deep.bats` that stages a file-level fixture (no fn decl) with a depends-on declared in the manifest and asserts coverage = 1, drift = 0.
- [ ] **AC-2:** Each of the 5 single-purpose scripts (`bats-lint.sh`, `bats-report.sh`, `fetch-license.sh`, `fix-cloudflare-certs.sh`, `security-audit.sh`) carries a `# @manifest` block at the top of the file (after shebang + description comment) with all required keys (`purpose`, `input`, `output`, `side-effect`, `failure-mode`, `contract`, `anchor`).
- [ ] **AC-3:** Each of the 12 hooks (`branch-name-lint.sh`, `commit-msg-lint.sh`, `format-on-write.sh`, `guard-destructive.sh`, `guard-force-push.sh`, `guard-workspace.sh`, `lint-on-write.sh`, `permission-request-suppress-redundant.sh`, `post-compact-marker.sh`, `protect-files.sh`, `protect-main.sh`, `session-boundary.sh`) carries a `# @manifest` block with all required keys.
- [ ] **AC-4:** `.ccanvil/manifest-allowlist.txt` adds 17 file-level entries (path-only, no `:fn` suffix) under a new `# BTS-251 — Session 8` section. Total entries 134 → 151.
- [ ] **AC-5:** `bash .ccanvil/scripts/module-manifest.sh validate --json` exits 0 with `coverage.covered == 151`, `coverage.total == 151`, `drift == []`.
- [ ] **AC-6:** Every declared `failure-mode` in the 17 manifests has a matching `# @failure-mode: <id>` marker somewhere in the file body. Every declared `side-effect` has a matching `# @side-effect: <id>` marker. Drift-guard verifies via the file-level fallback.
- [ ] **AC-7 (Edge):** A fixture file with NO fn declaration AND NO inline marker for a declared failure-mode produces `DRIFT: <path> reason=missing-failure-mode-marker` from `validate`. Confirms the fallback grep is real (not a false-positive pass on absent markers).
- [ ] **AC-8:** Full bats suite passes (`bash .ccanvil/scripts/bats-report.sh --parallel` reports `PASS: 1923+ / FAIL: 0`). Net delta is the new tests added in AC-1 and AC-7.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/module-manifest.sh` | Modified — file-level fallback in `_function_body_grep` |
| `.ccanvil/scripts/bats-lint.sh` | Modified — `# @manifest` block added |
| `.ccanvil/scripts/bats-report.sh` | Modified — `# @manifest` block added |
| `.ccanvil/scripts/fetch-license.sh` | Modified — `# @manifest` block added |
| `.ccanvil/scripts/fix-cloudflare-certs.sh` | Modified — `# @manifest` block added |
| `.ccanvil/scripts/security-audit.sh` | Modified — `# @manifest` block added |
| `.claude/hooks/*.sh` (12 files) | Modified — `# @manifest` block added |
| `.ccanvil/manifest-allowlist.txt` | Modified — +17 file-level entries (134 → 151) |
| `hub/tests/module-manifest-validate-deep.bats` | Modified — AC-1 + AC-7 tests |
| `hub/tests/fixtures/manifest/file-level-valid.sh` | New — AC-1 fixture |
| `hub/tests/fixtures/manifest/file-level-missing-marker.sh` | New — AC-7 fixture |
| `docs/manifest-rollout.md` | Modified — Inventory `Done` column updated |

## Dependencies

- **Requires:** BTS-239 (manifest substrate), BTS-240 (markdown branch — _target_body_grep dispatch precedent)
- **Blocked by:** none

## Out of Scope

- Markdown manifests (skills/rules/agents/commands) — Sessions 9 and 10
- Layer 3 / `code-reviewer` integration — Session 11
- Manifest-aware `/review` skill — Session 11
- Refactoring file-level scripts themselves — manifest-only ship

## Implementation Notes

- **Substrate fallback shape:** track a `fn_decl_seen` flag inside `_function_body_grep`. When the existing loop reaches EOF with `fn_decl_seen=0`, fall through to `grep -qE -- "$pattern" "$path"`. Preserves existing semantics for cmd_* targets (where the decl always exists) and only changes behavior for file-level scope.
- **Allowlist shape:** path-only entries (no `:fn` suffix). `cmd_validate` already extracts `id` from basename in this case (line 459). Confirmed by reading the validate path.
- **Manifest placement:** at the top of each file, after shebang and any short description comment, before `set -uo pipefail` (or whatever first non-comment line). Parser ends the block at the first non-`# key:` line per `cmd_extract` semantics.
- **Hook-specific contract patterns:** PreToolUse hooks read JSON from stdin, exit 0 (allow) / 2 (block + stderr-as-feedback). SessionStart/SessionEnd hooks read no input, exit 0 always. Document these as `contract: stdin-json-passthrough` / `contract: never-blocks` etc.
- **Inline-marker discipline:** every `failure-mode` and `side-effect` declared in the manifest needs a real inline marker (`# @failure-mode: <id>` or `# @side-effect: <id>`) on the line where the failure/side-effect occurs. Per `feedback_drift_guard_compounds_quality_across_sessions` — the marker is the load-bearing structural check.
- **No refactoring:** coverage-only ship. Body changes limited to (1) the substrate fallback, (2) inline marker comments in 17 files, (3) the manifest blocks themselves. No behavior changes.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
