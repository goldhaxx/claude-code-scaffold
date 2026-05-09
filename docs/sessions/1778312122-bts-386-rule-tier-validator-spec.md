# Feature: Rule-tier validator extension — module-manifest scan + warn-shape drift + info array

> Feature: bts-386-rule-tier-validator
> Work: linear:BTS-386
> Created: 1778305859
> Subject: Rule-tier validator extension — module-manifest scan + warn-shape drift + info array
> Status: In Progress

## Summary

BTS-385 Session A landed the rule frontmatter substrate (`cmd_rule_resolve`, `tier`/`scope`/`stack`/`anchors` schema) and 4 seed atom transformations, reducing auto-load context budget by 1144 tokens (165% → 151% of 8000-token soft ceiling). The validator extension scoped in BTS-385 spec AC-2 was deferred per `feedback_scope_down_on_reveal` — atomization first, enforcement second.

This ticket lands the deferred substrate: `module-manifest.sh validate` extends to scan all `.claude/rules/*.md` files for tier-budget compliance, emits a new warn-shape drift category (`rule-tier-budget-exceeded`), introduces an `info` array peer to `drift` for advisory-only entries (`frontmatter-missing`), and adds a `--strict` flag that escalates warn-shape drift to block-shape (exit 2). Hardens the BTS-385 thesis structurally: rules that drift the budget surface as discoverable signal, not human-tracked invariant.

## Job To Be Done

**When** I author or modify a rule file in `.claude/rules/`,
**I want** `module-manifest.sh validate` to flag tier-0 rules whose body exceeds 150 tokens AND surface frontmatter-missing as informational signal,
**So that** atomization discipline is enforced structurally and BTS-387 (Session B atomization audit) gets a deterministic drift list to work down rather than reading-and-comparing manually.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Validator scan extension

- [ ] **AC-1:** `bash .ccanvil/scripts/module-manifest.sh validate --json` extends to scan all `.claude/rules/*.md` files. Each file is read; top-level YAML frontmatter is parsed (reusing the same python3+yaml parser as `cmd_rule_resolve`). Files without frontmatter are still processed under back-compat default (tier=0).
- [ ] **AC-2:** Tier-0 rule file exceeding 150 tokens (char-count / 4 heuristic, matches `context-budget.sh`) emits a drift entry `{path, id, reason: "rule-tier-budget-exceeded", value: <tokens>, threshold: 150}`. Default exit code 0 when this is the only drift category present (warn-shape — atomization signal).
- [ ] **AC-3:** Malformed-yaml rule frontmatter emits `{path, id, reason: "rule-frontmatter-malformed", reason_detail: "<yaml-error excerpt>"}` in `drift[]` (block-shape — broken substrate, exit 2 like other manifest drift).

### Info array (advisory entries)

- [ ] **AC-4:** Validator envelope gains an `info` array distinct from `drift`. Shape: `[{path, id, reason}, ...]`. Status is unaffected by info entries (status="ok" still possible when only info present).
- [ ] **AC-5:** Rule files without YAML frontmatter emit `{path, id, reason: "frontmatter-missing"}` in `info[]`, NOT `drift[]`. Backward-compat preserved — frontmatter-less rules continue to function; the info entry is signal-only.

### `--strict` flag

- [ ] **AC-6:** `module-manifest.sh validate --json --strict` escalates warn-shape drift entries (only `rule-tier-budget-exceeded` currently) to exit code 2 when any are present. Block-shape drift (existing manifest-not-found, missing-required-field, etc.) continues to exit 2 with or without `--strict`.
- [ ] **AC-7:** Without `--strict`, `rule-tier-budget-exceeded` entries DO change `status` to `"drift"` (so consumers see the signal in JSON) but exit code stays 0.

### Tests + manifests

- [ ] **AC-8:** New `hub/tests/rule-frontmatter-validate.bats` covers: (a) tier-0 file at ≤150 tokens passes (no `rule-tier-budget-exceeded` drift); (b) tier-0 file at ≥200 tokens emits drift entry, status=`drift`, exit 0; (c) `--strict` on the same file → exit 2; (d) frontmatter-missing rule → info entry only, no drift, exit 0; (e) malformed-yaml rule → drift entry (block-shape), exit 2.
- [ ] **AC-9:** `hub/tests/module-manifest-markdown-validate.bats` continues passing (no regression in existing `manifest:` block path).
- [ ] **AC-10:** New helper(s) carry `@manifest` block. Manifest validate exits 0 with drift 0 (other than the new rule-scan emissions, which warn but don't block).

### Validation

- [ ] **AC-11:** Targeted bats files (`rule-frontmatter-validate.bats`, `module-manifest-markdown-validate.bats`, `module-manifest-validate.bats`) pass during iteration. Full bats suite passes at PR finalize.
- [ ] **AC-12:** Live invocation against the hub: `bash .ccanvil/scripts/module-manifest.sh validate --json` on the current `.claude/rules/` tree emits at least one `rule-tier-budget-exceeded` drift entry (the 4 unmigrated rules: tdd, provider-integration, evidence-required-for-captures, background-task-discipline).

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified: extend `cmd_validate` to scan rule files, emit warn-shape drift + info entries, accept `--strict` flag |
| `hub/tests/rule-frontmatter-validate.bats` | New — covers AC-1 through AC-7 with isolated fixtures |
| `hub/tests/fixtures/rule-tier/over-budget.md` | New fixture — tier-0 rule with body > 200 tokens |
| `hub/tests/fixtures/rule-tier/under-budget.md` | New fixture — tier-0 rule with body < 150 tokens |
| `.ccanvil/manifest-allowlist.txt` | Add new helpers introduced in [module-manifest.sh](<http://module-manifest.sh>) |
| `.ccanvil/guide/configuration.md` | Update Rule frontmatter subsection with validator behavior |

## Dependencies

* **Requires:** BTS-385 merged (rule frontmatter substrate + `cmd_rule_resolve`). BTS-385 shipped at commit `c7a40b6` (squash merge of PR #169).
* **Blocked by:** none.
* **Blocks:** BTS-387 (Session B atomization audit) — Session B benefits from this ticket's drift signal during the per-rule transformation work.

## Out of Scope

* **Token-count exact tokenizer.** Char-count / 4 heuristic stays. Future hardening if drift accuracy becomes a friction point; not load-bearing for v1.
* **Stack-conditional skill auto-load** (BTS-385 Out-of-Scope §5). Separate concern.
* **Atom file naming convention overhaul** (BTS-385 Out-of-Scope deferred to atomization audit).
* **BTS-384 scope-tag distribution filter.** Composes on top of this substrate; ships as separate PR after BTS-387.

## Implementation Notes

* **Reuse the python3+yaml parser** from `cmd_rule_resolve` (`.ccanvil/scripts/docs-check.sh`). The parsing logic is identical; consider factoring into a shared helper `_parse_rule_frontmatter` if the duplication is meaningful (judgment call at impl time — duplication acceptable for v1 if the helper would only have 2 callers).
* **Token counting:** char-count of the WHOLE FILE divided by 4. Matches the `context-budget.sh` heuristic for consistency. The whole-file count is what the harness auto-loads, not just the body.
* `--strict` parsing: add to `cmd_validate`'s arg parser at the top of the function (line 626 area). Set `local strict=0` default; flag toggles to 1.
* **Rule-scan loop placement:** insert after the existing manifest-allowlist scan loop (line 808 area, before `drift_count` calculation). Keeps the two scans separate; envelope composition combines them.
* **Drift entry shape consistency:** match the existing `{path, id, reason}` shape so consumers don't need conditional parsing. New optional fields (`value`, `threshold`, `reason_detail`) are additive.
* **Info array emit:** when `info_records` array is non-empty, include `info: [...]` in the JSON envelope. When empty, still include `info: []` so consumers can rely on the field existing (no conditional output).
* **No live-API risk** — all substrate work; doesn't trigger the live-API validation gate.
* **TDD cadence:** during iteration run only the new + existing manifest-validate bats files. Full-suite at PR finalize per the test-execution-discipline rule.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
