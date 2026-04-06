# Checkpoint

> Feature: scaffold-terminology-eradication
> Last updated: 1775502853
> Plan hash: 7ce64c7d
> Session objective: Implement scaffold terminology eradication — steps 1-14

## Accomplished

### Steps 1-4: Core ccanvil-sync.sh (complete)
- Lockfile keys: scaffold_source→hub_source, scaffold_version→hub_version, scaffold_hash→hub_hash, scaffold-only→hub-only, origin "scaffold"→"hub"
- Functions: 6 renamed (get_scaffold_source→get_hub_source, scaffold_dist_root→hub_dist_root, scan_scaffold_files→scan_hub_files, etc.)
- Variables: 12 renamed (scaffold_source→hub_source, scaffold_hub→hub_root, etc.)
- Strings: take-scaffold→take-hub, chore(scaffold)→chore(sync), all output/comments/help text
- Commits: 648fe66, 9e1b2cd, 5d94994, 7d27c8e

### Step 5: Config file rename (complete)
- scaffold.json→ccanvil.json (preset + hub root), scaffold.local.json→ccanvil.local.json
- merge_scaffold_config()→merge_config() in operations.sh + docs-check.sh
- Template: scaffold.json.md→ccanvil.json.md
- TRACKED_PATTERNS, .gitignore, .claudeignore updated
- Commit: c1a37f7

### Steps 6-7: Supporting scripts + test renames (complete)
- security-audit.sh allowlist: scaffold-framework.md→foundations.md
- context-budget.sh comment updated
- scaffold-sync.bats→ccanvil-sync.bats, scaffold-json-override.bats→ccanvil-json-override.bats
- Commits: 7d3f3b2, 83b5684

### Step 8: Guide files (complete)
- scaffold-sync.md→sync.md, scaffold-framework.md→foundations.md
- All 11 guide files swept
- Protection rules updated in code-quality.md, deterministic-first.md
- Commit: e893b36

### Steps 9-12: Documentation sweep (complete)
- 48 files: templates, commands, agents, rules, skills, hooks, hub meta, README, CLAUDE.md
- SCAFFOLD_SYSTEM_PROMPT.md→SYSTEM_PROMPT.md
- scaffold-differ→ccanvil-differ agent name
- All delimiter comments: /scaffold-pull→/ccanvil-pull
- Hub root .claude/ rules updated
- Commit: 86419ff

### Step 13: Downstream projects (in progress)
- Agents running for luxlook and fucina — copying fresh preset files, re-initing lockfiles

## Current State

- **Branch:** `claude/feat/scaffold-terminology-eradication`
- **Hub tests:** 352/352 passing
- **Working tree:** clean (downstream work in separate repos)
- **Hub scaffold refs:** 0 in active files; only in historical specs, research docs, and current feature docs (spec/plan/checkpoint)
- **Lockfile init verified:** produces hub_source, hub_version, hub_hash keys

## Next Steps

1. Verify downstream agents completed successfully (AC-24, AC-25)
2. Step 15: Guide cross-ref audit — verify all internal links resolve after renames
3. Final comprehensive grep sweep (step 14)
4. Mark spec as complete, create PR

## Determinism Review

- **operations_reviewed:** 8
- **candidates_found:** 0

No candidates this session. All file operations were handled by agents with explicit copy commands. The downstream migration pattern (copy preset files → re-init lockfile) is the same manual process flagged in the previous checkpoint — BTS-65 (migrate subcommand) would automate this.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
