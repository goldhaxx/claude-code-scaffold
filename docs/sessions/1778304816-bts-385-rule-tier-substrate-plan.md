# Implementation Plan: Rule atomicity + content-tiering — substrate + seed transformations

> Feature: bts-385-rule-tier-substrate
> Work: linear:BTS-385
> Created: 1778296800
> Spec hash: c63d297b
> Based on: docs/spec.md

## Objective

Land the frontmatter + tier substrate (`tier:`/`scope:`/`stack:`/`anchors:` schema, `module-manifest.sh` validate extension, `cmd_rule_resolve` primitive, `ccanvil.json` stacks declaration) plus 3 seed atom transformations on the smallest existing rules — establishing the dogfood proof that rules can be atomized + their deeper context routed to skills/reference docs without information loss.

## Sequence

Each step is one red-green-refactor cycle. Targeted bats only during iteration (per BTS-383 test-execution-discipline rule); full suite at PR finalize.

### Step 1: Bats fixture for rule-resolve happy path (RED)

* **Test:** `hub/tests/rule-resolve.bats` — new fixture with one test asserting `bash docs-check.sh rule-resolve <id> --project-dir .` returns a JSON envelope `{rule, tier, scope, stack, anchors, body_path}` on a fixture rule file with frontmatter.
* **Implement:** create the bats fixture; the test fails because `rule-resolve` subcommand does not exist yet.
* **Files:** `hub/tests/rule-resolve.bats` (new); fixture rule under `hub/tests/fixtures/rule-tier/sample-atom.md` (new).
* **Verify:** `bats hub/tests/rule-resolve.bats` shows 1 fail with "rule-resolve: unknown command" or similar.

### Step 2: `cmd_rule_resolve` happy path (GREEN) + manifest discipline

* **Test:** Step 1's test starts passing.
* **Implement:** add `cmd_rule_resolve()` to `.ccanvil/scripts/docs-check.sh` after `cmd_validate_spec` (\~line 7900). Reads `.claude/rules/<id>.md`, parses top-level YAML frontmatter for `tier:`, `scope:`, `stack:`, `anchors:` (peer to existing `manifest:` block — backward-compat). Returns JSON envelope on stdout. Backward-compat default for files without these fields: `{tier: 0, scope: "universal", stack: "any", anchors: {}}`. Add `@manifest` block with purpose/input/output/depends-on/side-effect/failure-mode/contract/anchor. Add `cmd_rule_resolve` to `.ccanvil/manifest-allowlist.txt`.
* **Files:** `.ccanvil/scripts/docs-check.sh`, `.ccanvil/manifest-allowlist.txt`.
* **Verify:** `bats hub/tests/rule-resolve.bats` passes (1/1). `bash .ccanvil/scripts/module-manifest.sh validate hub/tests/fixtures/rule-tier/ .ccanvil/scripts/docs-check.sh --json` exits 0 with drift 0.

### Step 3: `cmd_rule_resolve` error paths

* **Test:** add 3 cases to `hub/tests/rule-resolve.bats` — rule-not-found exits 1 with `{error: "rule-not-found"}`; malformed-yaml frontmatter exits 2 with `{error: "frontmatter-malformed", reason: ...}`; missing-frontmatter returns the back-compat default envelope (exit 0, info-level).
* **Implement:** error branches in `cmd_rule_resolve`. Use `yq` or `jq -e` for malformed-YAML detection (if not available, manual parse + structured error).
* **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/rule-resolve.bats`, fixtures: `hub/tests/fixtures/rule-tier/malformed.md` (new), `hub/tests/fixtures/rule-tier/no-frontmatter.md` (new).
* **Verify:** `bats hub/tests/rule-resolve.bats` passes 4/4.

### Step 4: Rule-frontmatter validation in `module-manifest.sh`

* **Test:** new `hub/tests/rule-frontmatter.bats` — covers (a) tier-0 file at ≤150 tokens passes (no `tier-budget-exceeded` drift); (b) tier-0 file at ≥200 tokens emits one `tier-budget-exceeded` drift entry, status=`drift`, exit code 0 (warn-shape); (c) `--strict` flag escalates to exit 2; (d) missing-frontmatter file emits a `frontmatter-missing` info entry, no drift; (e) malformed-yaml file emits a `frontmatter-malformed` drift entry.
* **Implement:** extend `module-manifest.sh` validate verb to also scan rule files (the BTS-240 markdown frontmatter parser already exists at line \~178; add a sibling parse for top-level `tier:` peer to `manifest:`). Token estimate: char-count / 4 (matches `context-budget.sh` heuristic). Default threshold 150.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-frontmatter.bats` (new), fixtures under `hub/tests/fixtures/rule-tier/` reused.
* **Verify:** `bats hub/tests/rule-frontmatter.bats` passes 5/5. `bats hub/tests/module-manifest-markdown-validate.bats` still passes (no regression in the existing manifest-block path).

### Step 5: `ccanvil.json` stacks declaration

* **Test:** add a smoke assertion to `hub/tests/rule-resolve.bats` (or a new tiny fixture) verifying that hub's `.claude/ccanvil.json` parses with a top-level `stacks: ["bats"]` key without breaking any existing consumers (`operations.sh resolve`, `lifecycle-state`, `radar-gather`).
* **Implement:** add `"stacks": ["bats"]` at top level of `.claude/ccanvil.json`. No substrate enforcement yet (skill discovery is deferred per Out-of-Scope §5); the field is declarative for future Tier-1 skill loaders.
* **Files:** `.claude/ccanvil.json`.
* **Verify:** smoke assertion passes; `bash docs-check.sh status --project-dir .` and `bash operations.sh resolve idea.add --project-dir .` continue to return correct envelopes.

### Step 6: Seed atom — `code-quality.md` (frontmatter-only, byte-identical body)

* **Test:** add a bats test asserting that after the edit, `code-quality.md`'s body content (everything below the frontmatter closing `---`) is byte-identical to the pre-edit content. `cmd_rule_resolve code-quality` returns the bundle with `tier: 0, scope: universal, stack: any`.
* **Implement:** prepend frontmatter `---\ntier: 0\nscope: universal\nstack: any\nanchors: {}\n---\n` to `.claude/rules/code-quality.md`. No body changes.
* **Files:** `.claude/rules/code-quality.md`.
* **Verify:** test passes; `bash module-manifest.sh validate --json` exits 0 with drift 0.

### Step 7: Seed atom — `workflow.md` (atomize + extract reference)

* **Test:** bats test asserts `cmd_rule_resolve workflow` returns envelope with `anchors.evidence: ["docs/research/feature-lifecycle.md"]`. Manifest validate emits NO `tier-budget-exceeded` drift entry on `workflow.md` (atom is ≤150 tokens). `docs/research/feature-lifecycle.md` exists and contains the lifecycle table content verbatim.
* **Implement:** trim `.claude/rules/workflow.md` body to the lifecycle directive + rule list (≤150 tokens). Move the Feature Lifecycle table and Strategic Awareness section to new `docs/research/feature-lifecycle.md`. Add frontmatter with `tier: 0, scope: universal, stack: any, anchors: {evidence: ["docs/research/feature-lifecycle.md"]}`.
* **Files:** `.claude/rules/workflow.md` (modified), `docs/research/feature-lifecycle.md` (new).
* **Verify:** test passes; `bash docs-check.sh rule-resolve workflow` returns the expected envelope; `cat docs/research/feature-lifecycle.md` shows preserved content.

### Step 8: Seed atom — `deterministic-first.md` (atomize + extract reference)

* **Test:** mirror Step 7's pattern — bats asserts atom ≤150 tokens, anchors.evidence points to `docs/research/deterministic-first-foundations.md`, reference doc exists with extracted content.
* **Implement:** trim `.claude/rules/deterministic-first.md` to the hierarchy directive (`hook → script → command → reasoning`) + apply-questions list. Move "Why" + anti-pattern catalog to new `docs/research/deterministic-first-foundations.md`. Add frontmatter.
* **Files:** `.claude/rules/deterministic-first.md` (modified), `docs/research/deterministic-first-foundations.md` (new).
* **Verify:** test passes; rule-resolve returns expected envelope.

### Step 9: Context-budget signal verification

* **Test:** observation only. `bash .ccanvil/scripts/context-budget.sh check --json | jq '.total_tokens'` returns ≤11700 (≥1500 reduction from 13224 baseline).
* **Implement:** no-op (verification step). If reduction falls short, surface the gap and revisit Steps 7/8 atomization aggressiveness.
* **Files:** none (read-only check).
* **Verify:** numeric assertion holds.

### Step 10: Update preset documentation

* **Test:** none (documentation step).
* **Implement:** update `.ccanvil/guide/configuration.md` (hub section) with the new `stacks:` field schema and the rule frontmatter convention (`tier`, `scope`, `stack`, `anchors`). Update `.ccanvil/guide/command-reference.md` with the new `rule-resolve` verb. No CLAUDE.md changes (this PR does not change tech stack or commands at the top level).
* **Files:** `.ccanvil/guide/configuration.md`, `.ccanvil/guide/command-reference.md`.
* **Verify:** docs read cleanly; no broken anchors.

## Risks

* **Frontmatter parser regression.** Existing rule files with `manifest:` block must continue to parse correctly after the new `tier:` peer fields land. Mitigation: top-level `tier:` is a NEW key peer to `manifest:` — existing parser code path stays unchanged; new parser code path adds new behavior. Test `module-manifest-markdown-validate.bats` for no regression at Step 4 verify.
* **workflow.md / deterministic-first.md trim losing nuance.** Atom must preserve meaning, not rewrite. Mitigation: extract content verbatim to reference doc; atom carries the directive + pointer. After landing, `cmd_rule_resolve` returning atom + reference path means an operator following the chain reads the same content as before.
* **Token-count heuristic inaccuracy.** Char-count / 4 is approximate; an atom under 150 estimated tokens may exceed when actually tokenized. Mitigation: lint is warn-only (drift entry, not block); operator can revise if real tokens overshoot. Future improvement: exact tokenizer (out of scope).
* **Backward-compat for frontmatter-less rules.** The 5 unmigrated rules (tdd.md, provider-integration.md, evidence-required-for-captures.md, background-task-discipline.md, self-review.md) must continue functioning. Mitigation: AC-3 explicitly tests this; default envelope returned for files without frontmatter.
* **No live-API risk.** All substrate work; no external API contract uncertainty.

## Definition of Done

- [ ] All 15 acceptance criteria from `docs/spec.md` pass.
- [ ] All existing bats tests still pass at PR finalize full-suite check.
- [ ] `bash .ccanvil/scripts/module-manifest.sh validate` exits 0 with drift 0.
- [ ] `bash .ccanvil/scripts/context-budget.sh check --json` reports ≥1500 token reduction.
- [ ] Code reviewed via the review skill.
- [ ] Sessions B/C/D follow-up tickets captured before PR finalize (BTS-385 umbrella has remaining work).
