# Implementation Plan: Rule-tier validator extension

> Feature: bts-386-rule-tier-validator
> Work: linear:BTS-386
> Created: 1778305970
> Spec hash: db9bbd40
> Based on: docs/spec.md

## Objective

Extend `module-manifest.sh validate` to scan all `.claude/rules/*.md` files for tier-budget compliance, emitting warn-shape `rule-tier-budget-exceeded` drift entries and an `info` array peer to `drift` for advisory `frontmatter-missing` entries. Add `--strict` flag that escalates warn-shape drift to exit 2. Closes the deferred BTS-385 AC-2 substrate.

## Sequence

Each step is one red-green-refactor cycle. Targeted bats only during iteration (per BTS-383); full suite at PR finalize.

### Step 1: Bats fixtures + RED test for over-budget drift

* **Test:** `hub/tests/rule-frontmatter-validate.bats` — new fixture with one test asserting `module-manifest.sh validate --json` on a rule fixture with body > 200 tokens emits a `rule-tier-budget-exceeded` drift entry.
* **Implement:** create `hub/tests/fixtures/rule-tier/over-budget.md` (tier-0 rule with ≥800 chars / \~200 tokens body). Create the bats fixture with one test that runs against an isolated project tree containing only that rule. Test fails because validator doesn't yet scan rule files.
* **Files:** `hub/tests/rule-frontmatter-validate.bats` (new), `hub/tests/fixtures/rule-tier/over-budget.md` (new).
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` shows 1 fail.

### Step 2: Implement rule-scan loop + over-budget drift (GREEN)

* **Test:** Step 1's test starts passing.
* **Implement:** in `.ccanvil/scripts/module-manifest.sh cmd_validate`, after the existing manifest-allowlist loop (around line 808), add a new rule-scan loop:
  * Iterate `.claude/rules/*.md` (relative to current working dir; fixtures override via mktemp project root).
  * For each file: parse top-level YAML frontmatter via embedded python3+yaml heredoc (mirrors `cmd_rule_resolve` parser shape). Extract `tier` (default 0) and compute char-count of WHOLE FILE.
  * Token estimate: `chars / 4` (matches `context-budget.sh` heuristic).
  * When `tier == 0 && tokens > 150`: append `{path, id, reason: "rule-tier-budget-exceeded", value: <tokens>, threshold: 150}` to `drift_records`.
* **Files:** `.ccanvil/scripts/module-manifest.sh`.
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` passes 1/1. `bats hub/tests/module-manifest-markdown-validate.bats` still passes (no regression in existing parser).

### Step 3: Under-budget regression test + warn-shape exit code

* **Test:** add 2 cases to `rule-frontmatter-validate.bats`:
  * (a) tier-0 file at < 150 tokens → no drift entry, exit 0.
  * (b) over-budget file → status=`drift` AND exit code 0 (warn-shape, default behavior).
* **Implement:** for (b), refine drift→exit logic in `cmd_validate`. Currently `drift_count > 0` returns 2 unconditionally. Need to differentiate: if ANY drift entry has reason NOT starting with `rule-` → exit 2 (block-shape preserved). If ALL drift entries are rule-\* prefixed → exit 0 (warn-shape).
* **Files:** `hub/tests/rule-frontmatter-validate.bats`, `.ccanvil/scripts/module-manifest.sh`, `hub/tests/fixtures/rule-tier/under-budget.md` (new).
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` passes 3/3.

### Step 4: `--strict` flag escalates warn-shape to exit 2

* **Test:** add 1 case to `rule-frontmatter-validate.bats`: over-budget file + `--strict` flag → status=`drift`, exit 2.
* **Implement:** parse `--strict` in `cmd_validate` arg parser (top of function, around line 626). Track `strict=0` default. In the exit-code logic (Step 3): if `strict==1 && warn_shape_drift_present`: exit 2 instead of 0.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-frontmatter-validate.bats`.
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` passes 4/4.

### Step 5: `info` array + `frontmatter-missing` entry

* **Test:** add 1 case to `rule-frontmatter-validate.bats`: rule file without frontmatter → entry in `info[]` (not `drift[]`), status=`ok`, exit 0. (Reuses `hub/tests/fixtures/rule-tier/no-frontmatter.md` from BTS-385.)
* **Implement:** in `cmd_validate`:
  * Add `local info_records=()` near `drift_records`.
  * In rule-scan loop: when frontmatter is missing (parser returns `_no_frontmatter` flag), append `{path, id, reason: "frontmatter-missing"}` to `info_records`. Continue with default tier=0 budget check.
  * In JSON envelope emit (line 820): add `info` field → `jq -n ... --argjson info "$info_arr" '... + {info:$info}'`. When `info_records` empty, emit `info: []` so consumers can rely on field presence.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-frontmatter-validate.bats`.
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` passes 5/5.

### Step 6: Malformed-yaml drift entry (block-shape)

* **Test:** add 1 case: rule file with malformed yaml frontmatter → drift entry with `reason: "rule-frontmatter-malformed"` and `reason_detail: "<yaml-error excerpt>"`. Exit 2 (block-shape — broken substrate). (Reuses `hub/tests/fixtures/rule-tier/malformed.md` from BTS-385.)
* **Implement:** in rule-scan loop: when parser returns `_error: "frontmatter-malformed"`, append `{path, id, reason: "rule-frontmatter-malformed", reason_detail: ...}` to `drift_records`. Reason prefix `rule-frontmatter-malformed` does NOT start with the warn-shape `rule-tier-budget-` token; treated as block-shape via the prefix-check from Step 3. Adjust the prefix check to be tighter: warn-shape ⇔ `reason == "rule-tier-budget-exceeded"`. Everything else (including `rule-frontmatter-malformed`) is block-shape.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-frontmatter-validate.bats`.
* **Verify:** `bats hub/tests/rule-frontmatter-validate.bats` passes 6/6.

### Step 7: @manifest discipline + manifest-allowlist

* **Test:** `bash module-manifest.sh validate --json` exits 0 on the hub itself with drift 0 (other than the new rule-scan emissions, which warn but don't block — exit 0 per Step 3).
* **Implement:** if any new helpers were factored out of `cmd_validate` (e.g., `_scan_rule_tier_compliance`), add `@manifest` block. Add to `.ccanvil/manifest-allowlist.txt`. If extension stays inline in `cmd_validate`, no new manifest needed (existing `cmd_validate` manifest covers it; may need a contract addition).
* **Files:** `.ccanvil/scripts/module-manifest.sh` (manifest update only), `.ccanvil/manifest-allowlist.txt` (only if helpers were factored out).
* **Verify:** manifest validate exits 0 with drift 0.

### Step 8: Live verification (AC-12)

* **Test:** observation only. `bash .ccanvil/scripts/module-manifest.sh validate --json` on the hub's current `.claude/rules/` tree emits at least 1 `rule-tier-budget-exceeded` drift entry (the 4 unmigrated rules: `tdd.md`, `provider-integration.md`, `evidence-required-for-captures.md`, `background-task-discipline.md`).
* **Implement:** no-op (verification step). If fewer than 4 entries surface, investigate: parser may be miscounting tokens, or one of the unmigrated rules is borderline-under threshold.
* **Files:** none.
* **Verify:** `bash module-manifest.sh validate --json | jq '.drift | map(select(.reason == "rule-tier-budget-exceeded")) | length'` returns ≥ 1.

### Step 9: Update preset documentation

* **Test:** none (documentation step).
* **Implement:** update `.ccanvil/guide/configuration.md` Rule frontmatter subsection (added in BTS-385) to mention the validator behavior — `module-manifest.sh validate` now emits `rule-tier-budget-exceeded` drift for over-budget tier-0 atoms (warn-shape, exit 0 by default; `--strict` escalates). Note the `info` array for `frontmatter-missing` advisories.
* **Files:** `.ccanvil/guide/configuration.md`.
* **Verify:** docs read cleanly.

## Risks

* **Existing manifest-validate exit-code regression.** Step 3 changes `drift_count > 0 → exit 2` to a prefix-aware logic. Could miscategorize an existing manifest drift type as warn-shape if it ever uses a `rule-` prefix. Mitigation: tighten the warn-shape predicate to `reason == "rule-tier-budget-exceeded"` exactly (Step 6), not a prefix match. Verify existing `module-manifest-validate.bats` and `module-manifest-validate-deep.bats` pass throughout.
* **Token-count heuristic inaccuracy.** Char/4 may overcount for code-heavy rules (high-density tokens) or undercount for table-heavy rules (low-density). For v1 the heuristic is a discoverability signal, not a hard gate. Lint is warn-only (default).
* **Performance impact.** Validator already scans 100+ files for manifest extraction. Adding a python3 invocation per rule file adds \~50-100ms × 8 rules = \~0.5s overhead. Acceptable for /pr cadence (full-suite already takes 1+ min).
* **Python3+yaml dependency.** Already declared in BTS-385's `cmd_rule_resolve`. Validator will pick up the same dependency. If parser fails (yaml module unavailable), validator emits a single info-or-error entry per rule and proceeds.
* **No live-API risk.** All substrate work; no external API contract uncertainty.

## Definition of Done

- [ ] All 12 acceptance criteria from `docs/spec.md` pass.
- [ ] `bats hub/tests/rule-frontmatter-validate.bats` passes 6/6.
- [ ] `bats hub/tests/module-manifest-markdown-validate.bats` still passes (regression guard).
- [ ] Full bats suite passes via `bash .ccanvil/scripts/bats-report.sh --parallel` at PR finalize.
- [ ] Manifest validate exits 0 with drift 0 (rule-scan emissions warn but don't block).
- [ ] AC-12 live verification: hub `validate --json` surfaces ≥1 `rule-tier-budget-exceeded` entry.
- [ ] Code reviewed via the review skill.
