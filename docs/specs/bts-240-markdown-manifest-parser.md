# Feature: Markdown manifest parser substrate

> Feature: bts-240-markdown-manifest-parser
> Work: linear:BTS-240
> Created: 1777402708
> Subject: Markdown manifest parser substrate
> Status: Complete

<!-- Subject: markdown manifest parser — frontmatter shape + 4 reference seeds -->

## Summary

Extend `module-manifest.sh cmd_extract` to parse manifest blocks declared in YAML frontmatter of markdown files, unblocking Sessions 9-10 of the manifest rollout (`docs/manifest-rollout.md`). Add 4 reference manifests — one per markdown sub-shape (skill, rule, agent, command) — to validate end-to-end and seed bulk rollout. The frontmatter shape aligns with skills' and agents' existing `name` / `description` frontmatter convention.

## Job To Be Done

**When** the manifest rollout reaches markdown sub-shapes (skills, rules, agents, commands — 37 units in Sessions 9-10),
**I want to** declare manifests using YAML frontmatter that the existing extract / validate / query / index substrate consumes identically,
**So that** Layer 2 coverage extends cleanly across all four markdown sub-shapes without parser-shape divergence and without breaking the function-level shell shape already shipped in BTS-239.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `cmd_extract <path.md>` on a markdown file with a YAML frontmatter `manifest:` block emits the same JSON shape as `cmd_extract <path.sh>` produces for an equivalent shell `# @manifest` block. Identical keys, identical types (scalar vs array), identical `id` resolution.
- [ ] **AC-2:** `cmd_extract <path.md>` on a markdown file with no frontmatter, or frontmatter without a `manifest:` key, emits `[]` and exits 0 (no-block fast path, parity with shell behavior).
- [ ] **AC-3:** `cmd_extract <path.md>` on malformed YAML (unclosed frontmatter, broken indent, unrecognized array shape under `manifest:`) emits `MALFORMED: ...` on stderr and exits 2.
- [ ] **AC-4:** `cmd_validate` accepts file-level allowlist entries pointing to `.md` files (e.g. `.claude/skills/spec/SKILL.md`). The `id` defaults to `basename .md` when not declared in the manifest body, and may be overridden by a `manifest.id:` value. Drift-guard's required-key, missing-callers, and missing-depends-on checks apply identically.
- [ ] **AC-5:** Source-marker requirement (`# @failure-mode: <id>` / `# @side-effect: <id>` inline markers) is **skipped** for `.md` paths. Markdown manifests describe documentation/skill contracts, not code bodies — markers have no anchor. The validator's marker-check branch must explicitly skip when the path's extension is `.md`.
- [ ] **AC-6:** `cmd_query` and `cmd_index` consume markdown manifests via the same internal JSON envelope as shell manifests. A query like `query 'caller:.claude/commands/spec.md'` returns matching markdown-declared manifests.
- [ ] **AC-7:** Four reference manifests land in this ship — one per sub-shape:
  - `.claude/skills/spec/SKILL.md` (skill)
  - `.claude/rules/tdd.md` (rule)
  - `.claude/agents/code-reviewer.md` (agent)
  - `.claude/commands/pr.md` (command)
  Each is appended to `.ccanvil/manifest-allowlist.txt` and passes `cmd_validate` cleanly. Allowlist grows from 7 → 11; drift-guard at 100% coverage.
- [ ] **AC-8:** `failure-mode` line schema is preserved unchanged from BTS-239 — pipe-delimited string `<id> | exit=N | visible=<phrase> | mitigation=<phrase>`. Markdown frontmatter encodes each as a YAML string in the `failure-mode:` array. Parser produces identical internal representation across both containers.
- [ ] **AC-9:** Cross-file caller resolution at scale — at least one of the four reference manifests declares 5+ callers spanning ≥3 files (mix of `.sh`, `.md`, `.bats` paths). `cmd_validate` resolves each via the existing grep-based lookup; all must hit. Verifies the existing resolver scales beyond BTS-239's 7-seed test set before bulk rollout starts.
- [ ] **AC-10:** Drift-guard tests (`hub/tests/module-manifest-drift-guard.bats`) gain one mutation test per markdown sub-shape — for each, mutate the reference manifest (drop a required key, fabricate a non-existent caller, etc.) and assert `cmd_validate` exits 2 with the expected `reason=` class.
- [ ] **AC-11:** `.ccanvil/templates/manifest.md` (locked format doc) gains a "Markdown frontmatter shape" section documenting the YAML form, the marker-skip semantics, and a worked example. The "Out of scope (first ship — BTS-239)" section's first bullet is updated to reflect that markdown is now in-scope.
- [ ] **AC-12:** Live-AC — next session's `/recall` step 11 surfaces `Manifest coverage: 11 / 11 (allowlist), drift: 0`. The allowlist increment is the post-merge proof.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/module-manifest.sh` | Modified — `cmd_extract` gains markdown branch (file-extension detection); `cmd_validate` skips marker-check for `.md` paths |
| `.ccanvil/templates/manifest.md` | Modified — new "Markdown frontmatter shape" section; out-of-scope bullet updated |
| `.claude/skills/spec/SKILL.md` | Modified — `manifest:` key added to existing frontmatter |
| `.claude/rules/tdd.md` | Modified — frontmatter block added (currently no frontmatter); `manifest:` key inside |
| `.claude/agents/code-reviewer.md` | Modified — `manifest:` key added to existing frontmatter |
| `.claude/commands/pr.md` | Modified — frontmatter block added (currently no frontmatter); `manifest:` key inside |
| `.ccanvil/manifest-allowlist.txt` | Modified — 4 new entries (one per sub-shape) |
| `hub/tests/module-manifest-markdown-extract.bats` | New — AC-1, AC-2, AC-3 |
| `hub/tests/module-manifest-markdown-validate.bats` | New — AC-4, AC-5 |
| `hub/tests/module-manifest-markdown-references.bats` | New — AC-7, AC-9 |
| `hub/tests/module-manifest-drift-guard.bats` | Modified — AC-10 markdown mutation tests |
| `hub/tests/fixtures/manifest/markdown/*` | New — fixture files for each AC |
| `docs/manifest-rollout.md` | Modified — Inventory `Done` column updated post-ship |

## Dependencies

- **Requires:** BTS-239 substrate (extract / validate / query / index, allowlist mechanic, drift-guard) — landed.
- **Blocked by:** none.

## Out of Scope

- Inline `@failure-mode` / `@side-effect` markers in markdown body. Markers anchor code paths; markdown describes contracts. Markers stay shell-only.
- Bulk rollout of all 37 markdown units (skills + rules + agents + commands). Sessions 9-10 ship those once this substrate is live and 4 references prove the shape.
- HTML-comment block alternative (`<!-- @manifest -->`). Decided in spec: YAML frontmatter is the chosen shape — semantic alignment with existing skills/agents convention.
- Pre-commit warn hook for missing manifests on changed files. Layer 2 follow-up ship in a later session.

## Implementation Notes

- **YAML parser approach**: avoid adding a YAML dep (no `yq`, no `python3 -c "import yaml"`). Implement a constrained YAML extractor in pure bash + awk that handles: top-level frontmatter delimiters (`---`), `manifest:` block detection (zero-indent), nested keys (2-space indent), array values (`  - <val>` lines under a key). Do NOT support arbitrary nesting, anchors, references, multi-line strings — the manifest schema is flat-by-design.
- **Internal data shape**: the markdown branch produces the same `key\tval\n` block_data string the shell branch produces, then funnels through the existing `_compose_block` helper. Same JSON output, same `id` resolution path (basename fallback for file-level), same compose semantics. One parser surface, two intake shapes.
- **`id` resolution for markdown**: when the manifest body declares `manifest.id:`, use it; otherwise fall back to `basename "$path" .md`. Mirrors shell's `basename .sh` fallback for file-level entries.
- **Bash 3.2 compat constraint** holds — no `mapfile`, no `local -n`. Use indexed arrays + `while IFS= read` loops + global array references where helpers need them.
- **Marker-skip branch in cmd_validate**: gate the existing `_check_failure_mode_markers` and `_check_side_effect_markers` helpers behind `[[ "$path" != *.md ]]`. Single-line guard, no architectural change.
- **Reference manifest selection rationale**: `pr.md` is chosen over a smaller command because it spans 5+ caller surfaces (`/pr` operator dispatch + several internal callers in skill flows) — exercises AC-9 cross-file resolution at scale.
- **Frontmatter on rules and commands**: rules and commands files do not currently carry frontmatter. Adding frontmatter to `tdd.md` and `pr.md` requires care — verify rendering tooling and any skill-loader that reads these files isn't sensitive to leading `---`. Quick scan needed in /plan.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
