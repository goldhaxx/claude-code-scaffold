# Implementation Plan: scaffold.json Node-Override Strategy

> Feature: scaffold-json-override
> Created: 1774312975
> Spec hash: fdf5f5cf
> Based on: docs/spec.md

## Objective

Add `scaffold.local.json` as a gitignored overlay that deep-merges over the hub-tracked `scaffold.json`, wired into all config-reading scripts.

## Sequence

### Step 1: Merge function + core tests (AC-1, AC-3, AC-4, AC-11)

- **Test:** In a new `tests/scaffold-json-override.bats`, write tests for the merge expression: both files present → deep merge; only hub file → hub content; neither file → empty/no-op; deep merge preserves nested keys from both sides (AC-11).
- **Implement:** Create a standalone helper function `merge_scaffold_config` that takes a project dir, runs `jq -s '.[0] * (.[1] // {})' scaffold.json scaffold.local.json`, and outputs the merged JSON. Place it in `scripts/operations.sh` (primary consumer). The function outputs the effective config JSON to stdout.
- **Files:** `tests/scaffold-json-override.bats` (new), `scripts/operations.sh` (add function)
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 2: Node-wins conflict behavior (AC-2)

- **Test:** Add test: both files define `features.pr_review` with different values → local file's value wins.
- **Implement:** Already handled by jq `*` operator (right-side wins). This step verifies the behavior, no new code expected.
- **Files:** `tests/scaffold-json-override.bats`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 3: Invalid local JSON error (AC-7)

- **Test:** Add test: `scaffold.local.json` contains invalid JSON → exit 1, stderr contains `ERROR: .claude/scaffold.local.json is not valid JSON`.
- **Implement:** Add JSON validation for the local file in `merge_scaffold_config`, matching the existing validation pattern in `read_config`.
- **Files:** `tests/scaffold-json-override.bats`, `scripts/operations.sh`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 4: Wire operations.sh read_config to use merge (AC-5)

- **Test:** In `tests/operations.bats`, add test: routing config in `scaffold.local.json` only → `operations.sh resolve` uses the merged config and resolves to the configured provider.
- **Implement:** Modify `read_config()` in `operations.sh` to call `merge_scaffold_config` and use the merged result for all downstream jq queries.
- **Files:** `tests/operations.bats`, `scripts/operations.sh`
- **Verify:** `bats tests/operations.bats`

### Step 5: Wire docs-check.sh config-get to use merge (AC-6)

- **Test:** Add test: `features.pr_review: true` only in `scaffold.local.json` → `docs-check.sh config-get pr_review` returns `"true"`.
- **Implement:** Modify `cmd_config_get()` in `docs-check.sh` to merge both files before reading the feature toggle.
- **Files:** `tests/scaffold-json-override.bats` (add config-get tests), `scripts/docs-check.sh`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 6: Gitignore and claudeignore (AC-9, AC-10)

- **Test:** Add tests: `grep -q 'scaffold.local.json' .gitignore` and `grep -q 'scaffold.local.json' .claudeignore` both pass.
- **Implement:** Add `.claude/scaffold.local.json` to `.gitignore` (next to `settings.local.json`) and `.claudeignore`.
- **Files:** `.gitignore`, `.claudeignore`, `tests/scaffold-json-override.bats`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 7: Pull safety verification (AC-8)

- **Test:** Add test: simulate hub change to `scaffold.json` while local copy is clean (no local modifications because overrides live in `scaffold.local.json`) → `pull-plan` classifies it as `auto-update`.
- **Implement:** No code changes expected — this is a verification that the design works with existing pull-plan logic. If scaffold.json is clean (node edits go to local file), pull-plan already classifies it as auto-update.
- **Files:** `tests/scaffold-json-override.bats`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 8: Update template (AC-12)

- **Test:** Add test: `docs/templates/scaffold.json` contains a reference to `scaffold.local.json`.
- **Implement:** Update the template to include a documentation comment or adjacent README reference explaining the overlay pattern.
- **Files:** `docs/templates/scaffold.json`, `tests/scaffold-json-override.bats`
- **Verify:** `bats tests/scaffold-json-override.bats`

### Step 9: Documentation updates

- **Implement:** Update hub documentation to reflect the new overlay pattern:
  - `CLAUDE.md`: Add `scaffold.local.json` to the Architecture section and document the merge behavior
  - `GUIDE.md`: **Blocked by BTS-26** — GUIDE.md is over 40k chars and the lint hook now blocks writes to it. Skip GUIDE.md updates in this PR; they'll be incorporated when BTS-26 restructures the file. Document the overlay pattern in CLAUDE.md only.
- **Files:** `CLAUDE.md`
- **Verify:** `bats tests/` (all tests pass)

### Step 10: Sync fucina node with hub

- **Context:** The fucina downstream project has not synced with the hub in a while. Multiple features have landed since last sync (permissions-audit, context-budget, tool-integration, and now scaffold-json-override). This step runs after PR merge.
- **Implement:** In the fucina project directory, run `/scaffold-pull` to pull all hub updates. Resolve any conflicts (scaffold.json will now auto-update cleanly thanks to BTS-24). Verify fucina's node-specific sections are preserved. Run fucina's test suite to confirm nothing broke.
- **Files:** Fucina project (external — `~/projects/fucina` or equivalent)
- **Verify:** `/scaffold-status` shows all files clean or node-only in fucina

## Risks

- **jq `*` operator array behavior:** jq's `*` replaces arrays (right-side wins), it does not concatenate. The current schema has no arrays, but this must be documented as a known limitation with an explicit policy for when arrays are added.
- **Bash 3 compatibility:** The `jq -s` slurp with two files is standard and works on macOS bash 3. No risk.
- **Duplicate merge logic:** Two scripts (`operations.sh`, `docs-check.sh`) each need the merge function. Risk of drift. Mitigated by keeping the function small (~10 lines) and testing both paths.

## Definition of Done

- [ ] All 12 acceptance criteria from spec pass
- [ ] All existing tests still pass (332 + new)
- [ ] No type errors
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
