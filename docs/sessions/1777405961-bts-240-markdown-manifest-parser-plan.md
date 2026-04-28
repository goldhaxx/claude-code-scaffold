# Implementation Plan: Markdown manifest parser substrate

> Feature: bts-240-markdown-manifest-parser
> Work: linear:BTS-240
> Created: 1777403200
> Spec hash: 4ddbbe92
> Based on: docs/spec.md

## Objective

Extend `module-manifest.sh` so manifests declared in markdown YAML frontmatter (skills, rules, agents, commands) are parsed, validated, queried, and indexed identically to shell-comment manifests — without adding a YAML dependency. Land 4 reference manifests as living proof and grow the allowlist 7 → 11 with drift-guard at 100%.

## Sequence

### Step 0: Commit pending rollout doc onto the feature branch

* **Test:** none — preliminary chore
* **Implement:** `git add docs/manifest-rollout.md && git commit -m "docs(manifest-rollout): multi-session rollout plan"`
* **Files:** `docs/manifest-rollout.md`
* **Verify:** `git status --short` is clean

### Step 1: RED+GREEN — cmd_extract markdown happy path (AC-1, AC-8)

* **Test:** `hub/tests/module-manifest-markdown-extract.bats` — fixture `markdown-happy.md` with frontmatter `manifest:` block declaring purpose / input / output / failure-mode (pipe-delimited) / contract / anchor. Assert extract emits same JSON shape as the equivalent shell shape (compare key set, scalar vs array types, `id` resolution).
* **Implement:** in `cmd_extract`, branch on `[[ "$path" == *.md ]]`. New helper `_extract_markdown_block` reads the frontmatter (between first two `---` lines), locates the `manifest:` key (zero-indent), captures lines indented under it, parses scalar (`  key: val`) and array (`  key:\n    - val`) shapes into `key\tval\n` block_data. Funnel through existing `_compose_block` (passing path + computed block_start_lineno + the same `lines` global pattern). Pure bash + awk; no yq, no python yaml.
* **Files:** `hub/tests/module-manifest-markdown-extract.bats` (new), `hub/tests/fixtures/manifest/markdown-happy.md` (new), `.ccanvil/scripts/module-manifest.sh` (modified)
* **Verify:** new bats file passes; existing bats suite untouched

### Step 2: RED+GREEN — cmd_extract markdown edge cases (AC-2, AC-3)

* **Test:** extend `module-manifest-markdown-extract.bats` —
  * fixture `markdown-no-frontmatter.md` (no `---` block) → extract emits `[]`, exit 0
  * fixture `markdown-no-manifest-key.md` (frontmatter present, no `manifest:` key) → `[]`, exit 0
  * fixture `markdown-malformed-yaml.md` (unclosed frontmatter / broken array shape under `manifest:`) → `MALFORMED:` on stderr, exit 2
* **Implement:** in `_extract_markdown_block`, return early-empty when no `---` delimiters or no `manifest:` key. On malformed input (unclosed frontmatter, broken indent, missing `- ` for array items, multi-line scalar without `|` block), emit `MALFORMED: <path>:<line>: <reason>` and `return 2`.
* **Files:** `hub/tests/module-manifest-markdown-extract.bats` (extended), 3 new fixture files
* **Verify:** all extract bats green; malformed fixture emits correct stderr

### Step 3: RED+GREEN — cmd_validate accepts .md file-level entry + marker-skip (AC-4, AC-5)

* **Test:** `hub/tests/module-manifest-markdown-validate.bats` —
  * Allowlist with `<fixture-path>.md` (no `:fn` suffix); `id` resolves to `basename .md`; manifest with all required keys → validate exits 0, coverage 1/1
  * Manifest declares `failure-mode: foo | exit=1` but the markdown body has no `# @failure-mode: foo` marker → validate STILL exits 0 (markers skipped for `.md`)
  * Same for `side-effect: bar` with no marker
* **Implement:** in `cmd_validate`'s deep-validation block, gate the failure-mode marker check (lines 372-391) and side-effect marker check (lines 393-408) behind `[[ "$path" != *.md ]]`. Single guard each. No other changes here.
* **Files:** `hub/tests/module-manifest-markdown-validate.bats` (new), 1 fixture, `.ccanvil/scripts/module-manifest.sh` (modified)
* **Verify:** new tests pass; shell marker-check tests in `module-manifest-validate-deep.bats` still pass (regression guard)

### Step 4: RED+GREEN — cmd_validate caller + depends-on for .md (whole-file body)

* **Test:** extend `module-manifest-markdown-validate.bats` —
  * Manifest declares `caller: .claude/commands/foo.md` (path-form, not `skill:/foo`); fixture commands file invokes the primitive → validate passes
  * Manifest declares `depends-on: helper_thing` and the markdown body contains `helper_thing` somewhere → validate passes
  * Manifest declares `caller: .claude/commands/missing.md` (file does not exist) → validate fails with `caller-not-found`
  * Manifest declares `depends-on: nonexistent_thing` → validate fails with `depends-on-not-found`
* **Implement:** introduce `_target_body_grep` wrapper that for `.sh:fn` delegates to `_function_body_grep`, and for `.md` paths greps the whole file. Replace the depends-on grep call (line 361) with `_target_body_grep "$path" "$id" "$pattern"`. Extend `_caller_actually_calls_primitive` to accept bare path-form callers (`*.md`, `*.sh`) — when `caller_ref` is a literal path, check that the file exists and grep it directly (no function-extraction). Function-name and `skill:/` forms unchanged.
* **Files:** extended bats + fixtures, `.ccanvil/scripts/module-manifest.sh` (modified)
* **Verify:** all markdown validate tests green; shell caller/depends-on tests still pass

### Step 5: RED+GREEN — cmd_index walks markdown source dirs (AC-6)

* **Test:** `hub/tests/module-manifest-markdown-index.bats` — fixture project with manifests in `.claude/skills/foo/SKILL.md`, `.claude/rules/bar.md`, `.claude/agents/baz.md`, `.claude/commands/qux.md`. Run `cmd_index`; assert `.ccanvil/state/manifests.json` contains entries keyed `<path>:<id>` for each. Run `cmd_query 'caller:.claude/commands/qux.md'` and assert it returns matching entries.
* **Implement:** in `cmd_index`, extend `src_dirs` and the inner loop. Add a markdown walk pass: for each of `.claude/skills/*/SKILL.md`, `.claude/rules/*.md`, `.claude/agents/*.md`, `.claude/commands/*.md`, run `cmd_extract` and merge into the index. Glob with `for f in <pattern>; do [[ -f "$f" ]] || continue; ...`.
* **Files:** new bats + fixture tree, `.ccanvil/scripts/module-manifest.sh` (modified)
* **Verify:** new index/query tests green; existing index/query tests unaffected

### Step 6: RED+GREEN — drift-guard mutation tests for 4 sub-shapes (AC-10)

* **Test:** extend `hub/tests/module-manifest-drift-guard.bats` — for each sub-shape (skill, rule, agent, command), one mutation test:
  * skill: drop `purpose:` from manifest → `missing-required-key value=purpose`
  * rule: declare `caller: .claude/commands/nonexistent.md` → `caller-not-found`
  * agent: declare `depends-on: nonexistent_helper` → `depends-on-not-found`
  * command: declare manifest where the `id:` doesn't match the basename and isn't reachable → `manifest-not-found`
* **Implement:** none beyond Steps 1-5 — these are bats-only mutation tests using fixtures.
* **Files:** `hub/tests/module-manifest-drift-guard.bats` (extended), 4 markdown fixtures
* **Verify:** mutation tests green (assert validate exits 2 with correct `reason=`)

### Step 7: Write 4 reference manifests (AC-7, AC-9)

* **Test:** none — implement-and-validate; the validation IS the test (drift-guard at 100% on the new entries).
* **Implement:** add `manifest:` blocks to:
  * `.claude/skills/spec/SKILL.md` (already has frontmatter — add `manifest:` key; declare 5+ callers across ≥3 files including `.claude/commands/spec.md`, downstream skills like `.claude/skills/idea/SKILL.md`, and a relevant `.bats` test file — exercises AC-9 cross-file resolution)
  * `.claude/rules/tdd.md` (currently no frontmatter — add full `---`-delimited block with just the `manifest:` key)
  * `.claude/agents/code-reviewer.md` (already has `name:` `description:` `tools:` `model:` frontmatter — add `manifest:` key)
  * `.claude/commands/pr.md` (currently no frontmatter — add full block)
* **Files:** the 4 reference markdown files, modified
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh extract <each>` emits valid JSON; manual inspection that field semantics are accurate (purpose actually describes the file's role, callers are real, depends-on entries appear in the body).

### Step 8: Grow allowlist 7 → 11 + drift-guard verify 11/11 (AC-7, AC-12)

* **Test:** `hub/tests/module-manifest-drift-guard.bats` (the production drift-guard test, not fixture-based) — assert `cmd_validate` against the real allowlist exits 0 with coverage 11/11 and drift count 0.
* **Implement:** append 4 lines to `.ccanvil/manifest-allowlist.txt`:

  ```
  .claude/skills/spec/SKILL.md
  .claude/rules/tdd.md
  .claude/agents/code-reviewer.md
  .claude/commands/pr.md
  ```
* **Files:** `.ccanvil/manifest-allowlist.txt` (modified)
* **Verify:** `bash .ccanvil/scripts/module-manifest.sh validate --json` reports `coverage.covered == 11`, `coverage.total == 11`, `drift == []`. Production drift-guard bats test green.

### Step 9: Update format docs (AC-11)

* **Test:** none (documentation step)
* **Implement:**
  * `.ccanvil/templates/manifest.md`: new section "Markdown frontmatter shape" between "Block syntax" and "Keys" — documents YAML form, the `manifest:` key inside top-level frontmatter, scalar vs array shape, marker-skip semantics for `.md`, worked example using the actual `.claude/skills/spec/SKILL.md` reference manifest.
  * Update "Out of scope (first ship — BTS-239)" — remove the markdown-frontmatter bullet (now in scope) and replace with a "Layer 2 follow-ups" bullet pointing at `docs/manifest-rollout.md` for the rest of the rollout.
  * `.ccanvil/guide/command-reference.md`: brief note in the existing "Module Manifest Substrate (BTS-239)" section that markdown sub-shape is now supported (one sentence).
  * `docs/manifest-rollout.md`: update Inventory table — `Markdown — skills`, `rules`, `agents`, `commands` rows each get `Done: 1` (the reference manifests).
* **Files:** `.ccanvil/templates/manifest.md`, `.ccanvil/guide/command-reference.md`, `docs/manifest-rollout.md` (modified)
* **Verify:** read-back; [manifest.md](<http://manifest.md>) still renders correctly when /review fetches it.

### Step 10: Full suite green + final review

* **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel` — entire suite passes; expected delta ≈ 1892 → \~1920 (+28 new tests across 3-4 new files plus extensions).
* **Implement:** any cleanup surfaced by the suite. Run `bash .ccanvil/scripts/module-manifest.sh validate` one final time; verify 11/11.
* **Files:** none new
* **Verify:** suite green, drift 0; commit; `/review`; address findings if any; mark PR ready.

## Risks

* **YAML parser edge cases.** Pure-bash YAML extractor may miss legal-but-uncommon shapes (inline arrays `[a, b]`, quoted strings with colons, nested maps). Mitigation: scope hard to the constrained schema (flat manifest with scalar + simple-array values only). Reject anything outside that schema with `MALFORMED:`. Documented constraint in Step 1.
* **Frontmatter on rules/commands may break tooling.** `tdd.md` and `pr.md` currently have no frontmatter. The skill loader (Claude Code's harness) reads `.claude/commands/*.md` — adding frontmatter MIGHT change parsing. Mitigation: in Step 7, add the frontmatter and immediately verify `/pr` still resolves correctly via its existing dispatch path. If breakage observed, revert that one file and use a different command for the reference (e.g., `commit.md` instead of `pr.md`).
* `_target_body_grep` for markdown is whole-file — false-positives possible if the manifest declares `depends-on: foo` and the prose mentions `foo` incidentally elsewhere. Mitigation: word-boundary regex `\bfoo\b` (already used). Accept that markdown semantics are looser than function-body semantics — drift-guard for markdown is structural validity, not behavioral verification.
* **AC-9's 5+-callers manifest may flake** if the cross-file caller resolver doesn't scale. Mitigation: explicitly run validate against the [spec.md](<http://spec.md>) reference IMMEDIATELY after writing it (Step 7), not at end-of-suite — surface any resolver gaps early. If gaps found, extend resolver in Step 4 before proceeding.

## Definition of Done

- [ ] All 12 acceptance criteria from `docs/spec.md` pass
- [ ] All existing tests still pass (1892 baseline preserved)
- [ ] No type errors (n/a — bash)
- [ ] Manifest coverage 11/11, drift 0 — verified by `module-manifest.sh validate`
- [ ] Format doc `.ccanvil/templates/manifest.md` updated
- [ ] `docs/manifest-rollout.md` Inventory table reflects new Done counts
- [ ] Code reviewed (run `/review`)
