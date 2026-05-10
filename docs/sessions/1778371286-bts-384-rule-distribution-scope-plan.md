# Implementation Plan: Rule distribution scope + abstraction discipline

> Feature: bts-384-rule-distribution-scope
> Work: linear:BTS-384
> Created: 1778364532
> Spec hash: 5a4162a4
> Based on: docs/spec.md

## Objective

Extend the BTS-385/386 rule-frontmatter substrate to honor `scope:` at distribution time and add a vocabulary-leak drift-guard, so downstream nodes only receive rules that match their `role:` and read in stack-neutral vocabulary.

## Sequence

### Step 1: scope-vocabulary parser extension (AC-1)

* **Test:** `hub/tests/rule-scope-validate.bats` fixtures for `scope: universal` (clean), `scope: substrate` (clean), `scope: hub-only` (clean), `scope: invalid-value` (drift — `rule-scope-invalid`), missing `scope:` (info — `rule-scope-missing`).
* **Implement:** Extend the python+yaml parser block in `module-manifest.sh` rule-scan loop (line \~875) to surface `scope` alongside `tier`. Emit `rule-scope-invalid` to `drift_records[]` for unknown values; emit `rule-scope-missing` to `info_records[]` when key absent.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-scope-validate.bats`, `hub/tests/fixtures/rule-scope/{universal,substrate,hub-only,invalid,missing}.md`.
* **Verify:** `bash bats-report.sh hub/tests/rule-scope-validate.bats` green; `bash module-manifest.sh validate --json` on hub still drift=0 (all 9 rules already `scope: universal`).

### Step 2: vocabulary-leak drift-guard (AC-5)

* **Test:** `hub/tests/rule-vocabulary-leak.bats` fixtures: `universal` rule with hub token (`bats-report.sh`) outside anchor (info: `rule-vocabulary-leak`), inside `## Anchored on (ccanvil hub)` block (clean), `substrate` rule with same token (clean — not scanned), `universal` rule with no leak (clean).
* **Implement:** In the rule-scan loop (Step 1's site), for each `scope: universal` rule extract body text (everything after the closing `---`), strip lines from the first `## Anchored on` heading onward, then grep for the constant token list (`bats-report.sh`, `module-manifest.sh`, `ccanvil-sync.sh`, `linear-query.sh`, `docs-check.sh`, `BTS-[0-9]+`). Emit one `rule-vocabulary-leak` info entry per file found with `tokens: [...]` array.
* **Files:** `.ccanvil/scripts/module-manifest.sh`, `hub/tests/rule-vocabulary-leak.bats`, `hub/tests/fixtures/rule-vocab-leak/*.md`.
* **Verify:** Targeted bats green; `module-manifest.sh validate --json` on hub surfaces leaks for any current rules in violation (operator inspects output for Step 5 audit input).

### Step 3: role field substrate (AC-2, AC-7)

* **Test:** `hub/tests/ccanvil-role-field.bats` — `.claude/ccanvil.json` parses with `role: hub-substrate-developer`; `.ccanvil/templates/ccanvil.json.md` documents `role: substrate-consumer` default; helper `_resolve_node_role()` in [ccanvil-sync.sh](<http://ccanvil-sync.sh>) returns `substrate-consumer` when key absent (AC-7), `hub-substrate-developer` when key present.
* **Implement:** Add `"role": "hub-substrate-developer"` to hub `.claude/ccanvil.json`. Update `.ccanvil/templates/ccanvil.json.md` with the role-field doc + `substrate-consumer` default. Add `_resolve_node_role()` helper in `ccanvil-sync.sh` (reads `<node>/.claude/ccanvil.json` via jq with `// "substrate-consumer"` fallback).
* **Files:** `.claude/ccanvil.json`, `.ccanvil/templates/ccanvil.json.md`, `.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/ccanvil-role-field.bats`.
* **Verify:** Targeted bats green; jq parse-check on `.claude/ccanvil.json` clean.

### Step 4: scope filter at sync (AC-3, AC-4)

* **Test:** `hub/tests/rule-distribution-scope.bats` matrix — for each (scope ∈ {universal, substrate, hub-only}, role ∈ {hub-substrate-developer, substrate-consumer}), assert pull-plan output bucket: universal→pull (both roles), substrate→pull only when role=hub-substrate-developer (else `skipped (scope-filter)`), hub-only→`skipped (scope-filter)` always (both roles). 6 cases.
* **Implement:** Add `is_scope_allowed(hub_file_abs_path, node_role)` helper in `ccanvil-sync.sh` — extracts `scope:` from frontmatter via the same python+yaml parser used in [module-manifest.sh](<http://module-manifest.sh>) (factor into shared helper or inline call); returns 0 (allow) / 1 (skip). Wire into `cmd_pull_plan` so files failing the check land in a new `skipped_scope_filter[]` envelope bucket. Update preview rendering to surface the new bucket.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`, `hub/tests/rule-distribution-scope.bats`, `hub/tests/fixtures/rule-distribution-scope/`.
* **Verify:** Targeted bats green; live `bash ccanvil-sync.sh pull-plan` on hub-self surfaces no surprises.

### Step 5: audit-pass — re-tag provider-integration.md (AC-6)

* **Test:** Implicit — Step 1's test ensures scope vocabulary; this step's correctness is measured by the leak-scan output from Step 2 returning empty for the audit-pass set, plus `provider-integration.md` showing `scope: substrate`.
* **Implement:** Run `bash module-manifest.sh validate --json` post-Step 2; for each `rule-vocabulary-leak` finding, decide re-tag (`universal`→`substrate`) vs vocabulary-rewrite (move hub tokens behind `## Anchored on` block). Always re-tag `provider-integration.md` per AC-6 (substrate-only by content). Commit body lists each rule's pre/post `scope:` value.
* **Files:** `.claude/rules/provider-integration.md` (and any others surfaced).
* **Verify:** `module-manifest.sh validate --json` returns `info[]` with no `rule-vocabulary-leak` entries; `pull-plan` on a substrate-consumer fixture skips `provider-integration.md`.

### Step 6: full-suite verify + manifest validate (AC-8)

* **Test:** Full bats suite via `bash .ccanvil/scripts/bats-report.sh --parallel --progress`. Spec validate-spec exits 0.
* **Implement:** No code — verification step.
* **Files:** —
* **Verify:** PASS 2106+ / FAIL 0 (4 new test files add rows). `module-manifest.sh validate --json` returns `coverage: 194/194`, `drift: []`, `status: ok`. `bash docs-check.sh validate-spec --feature bts-384-rule-distribution-scope` emits `status: ok`.

### Step 7: docs update

* **Implement:** Add a "Rule scope and node role" section to `.ccanvil/guide/rules.md` (or `presets.md` — confirm during step) explaining the three scopes, role-field default, anchor-block convention, and how `pull-plan` surfaces the filter. Update CLAUDE.md hub-managed section only if a new "do not" rule emerges (likely not — convention only).
* **Files:** `.ccanvil/guide/<rules.md|presets.md>`, possibly `CLAUDE.md`.
* **Verify:** Read-back of guide section matches the substrate behavior shipped Steps 1-5.

## Risks

* **Per-file frontmatter parse cost in** `cmd_pull_plan` — TRACKED_PATTERNS expands to \~50 files; parsing yaml on each per pull-plan call adds latency. Mitigation: parser only invoked for `.claude/rules/*.md` paths (the only ones carrying `scope:` today); other paths short-circuit allowed. Confirm via benchmark — if measurable, hash-cache.
* `is_distributable_path` callers beyond `cmd_pull_plan` — `cmd_changelog` (line 1231/1246), `scan_hub_files` (line 487/718/2768/2882). Filter must thread role through OR scope filter applies only at `cmd_pull_plan` to avoid breaking changelog semantics for hub-self. **Decision:** Step 4 keeps scope filter inside `cmd_pull_plan` only; `cmd_changelog` is hub-internal and already filters by `is_distributable_path`. Confirm via Step 4 test that changelog on hub-self still surfaces all distributable changes.
* **Vocabulary-leak token false positives** — a `universal` rule may legitimately reference a tool name in stack-neutral phrasing. Token list starts narrow (6 entries); leak entries are advisory `info[]` only. Operator can move tokens behind `## Anchored on` block to silence per-rule.
* **provider-integration.md re-tag distribution surprise** — downstream nodes that pulled prior to this PR now stop receiving the rule on next pull. That's the intended behavior, but worth flagging in the PR body so operators with active downstreams aren't confused.

## Definition of Done

- [ ] All 8 acceptance criteria pass binary checks.
- [ ] All existing tests still pass (PASS 2106+ baseline).
- [ ] `module-manifest.sh validate --json` returns `coverage: 194/194, drift: 0`.
- [ ] No `rule-vocabulary-leak` entries in `info[]` post-Step 5 audit.
- [ ] Code reviewed (run `/review`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
