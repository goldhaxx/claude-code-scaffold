# Checkpoint

> Feature: scaffold-json-override
> Last updated: 1774320071
> Plan hash: fba4ae15
> Session objective: BTS-24 (scaffold.json node-override strategy) + fucina sync + chores

## Accomplished

### BTS-24 implementation complete (all 12 ACs pass, merged PR #4)
- **Research phase:** 3 parallel agents researched 9 config management systems (Helm, Kustomize, Docker Compose, Terraform, ESLint, Spring Boot, Chrome/Firefox, NixOS, VS Code) + RFC 7396/6902 + jsonnet/CUE. All converged on Chrome's managed preferences model: separate files per owner, merged at read time.
- **Spec + Plan:** 12 acceptance criteria, 9 TDD steps + fucina sync step
- **Implementation:** `scaffold.local.json` overlay with RFC 7396 deep merge (jq `*` operator, node wins on conflict)
  - `merge_scaffold_config()` in operations.sh — handles all 4 file-presence combinations
  - `read_config()` wired to merge both files into temp file for downstream queries
  - `docs-check.sh config-get` wired to read merged effective config
  - 13 new tests in `tests/scaffold-json-override.bats`
- **Review fixes:** temp file leak (trap EXIT), hook basename anchoring, test cleanup
- **PR #4 squash-merged, BTS-24 marked Done in Linear**

### File size enforcement hook (chore)
- `lint-on-write.sh` now blocks always-loaded files (CLAUDE.md, GUIDE.md, rules/*.md) at 40k chars, warns general files at 80k
- GUIDE.md (45.5k chars) is currently blocked — forces BTS-26 resolution before further edits

### Backlog management
- **BTS-25 created:** operations.sh exec subcommand (Low, needs-spec) — determinism improvement from BTS-19
- **BTS-26 created:** GUIDE.md restructuring (High, needs-research) — 44.8k chars exceeds 40k limit

### Fucina synced with hub
- 14 auto-updates + 10 new files + scaffold-sync.sh manual update
- All 4 features since last sync: permissions-audit, context-budget, tool-integration, scaffold-json-override
- Pull-plan now shows `[]` — fully clean

## Current State

- **Branch:** `main`
- **Tests:** 345/345 passing
- **Uncommitted changes:** This checkpoint
- **Build status:** Clean
- **Fucina:** Synced and pushed

## Blocked On

- Nothing

## Next Steps

1. **BTS-26:** GUIDE.md restructuring (High) — blocked from editing GUIDE.md by hook until resolved. Options: split into docs/guide/, externalize, progressive disclosure, or hybrid.
2. **BTS-23:** CLAUDE.md content review — trim to 80-line budget (Medium, needs-spec)
3. **BTS-25:** operations.sh exec subcommand (Low, needs-spec)
4. **BTS-22:** Docs directory strategy (Medium, needs-research)

## Context Notes

- `scaffold.local.json` is gitignored and claudeignored — scripts read it via merge function, never raw
- Merge semantics are locked: jq `*` deep merge, arrays replace (not concatenate), node wins on conflict. Changing this later would be a Terraform-0.12-level breaking change.
- The companion doc pattern (`scaffold.json.md` next to `scaffold.json`) was used because JSON has no comments. This could be a general pattern for other JSON configs.
- Fucina sync revealed the bootstrap-skip issue: `scaffold-sync.sh` is bootstrapped in pre-check but the lockfile hash isn't updated, requiring a manual copy. This is a known quirk, not a bug.

## Determinism Review

- **operations_reviewed:** 8
- **candidates_found:** 1
- **Fucina scaffold-sync.sh hash fixup:** Had to manually copy scaffold-sync.sh and update lockfile hashes because the bootstrap-skip in pre-check doesn't update the lockfile. This is a recurring manual step that could be a `pull-auto --include-bootstrap` flag or automatic hash update after bootstrap. Impact: low (happens once per sync, not per file).
- All merge logic uses `jq -s` (deterministic). No manual cp or shasum improvised for the BTS-24 implementation. All file operations used dedicated tools.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
