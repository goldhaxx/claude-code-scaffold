# Feature: Rule atomicity + content-tiering — substrate + seed transformations

> Feature: bts-385-rule-tier-substrate
> Work: linear:BTS-385
> Created: 1778296380
> Subject: Rule atomicity + content-tiering — substrate + seed transformations
> Status: In Progress

## Summary

Hub rule files have grown to \~1000-2300 tokens each by embedding war stories ("Why" sections), substrate-specific tooling references, anti-pattern catalogs, and incident evidence — all auto-loading on every Claude Code turn, on every node. Hub at 165% / tour-scheduler at 160% of the 8000-token soft context budget. Most expensive context category in the system.

Architecture detailed in `docs/research/rule-content-tiering.md` (committed `72bcf68`). Three-tier model: Tier 0 atoms (always-on directives, ≤150 tokens) / Tier 1 skills (on-invocation) / Tier 2 reference (on-demand). Stack-profile composition for stack-specific content. Frontmatter `tier:` + `stack:` + `anchors:` declares how each file loads.

**This spec scopes Session A of the BTS-385 umbrella** — substrate (frontmatter schema, validation, resolve primitive) plus seed atom transformations on the smallest existing rules (proof-of-substrate dogfood). Sessions B (atomization audit on the larger rules), C (BTS-384 scope-tag composition), and D ([CLAUDE.md/settings.json](<http://CLAUDE.md/settings.json>) trim) ship as separate PRs after this lands.

## Job To Be Done

**When** I author or update a hub rule, or when ccanvil-sync delivers rules to a node,
**I want** rules to declare their tier explicitly so cheap directives stay always-on while deeper context (tooling references, war stories) loads only when relevant,
**So that** the agent's auto-load context budget shrinks \~60% (13224 → \~5400 tokens) without losing access to any of the underlying knowledge.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

### Frontmatter substrate

- [ ] **AC-1:** Rule files accept frontmatter declaring `tier:` (0|1|2), `scope:` (universal|substrate|hub-only — placeholder for BTS-384's filter; substrate accepts the field but does NOT yet filter on it), `stack:` (any|<name>), and `anchors:` (object with `apply:`, `evidence:`, `related-rules:` arrays).
- [ ] **AC-2:** `bash .ccanvil/scripts/module-manifest.sh validate --json` extends to scan rule files. Files declaring `tier: 0` and exceeding 150 tokens emit a `tier-budget-exceeded` drift entry (warn-shape, not block-shape — `status: drift` with the entry, exit code 0 by default; `--strict` flag escalates to exit 2).
- [ ] **AC-3:** Rule files without frontmatter default to `{tier: 0, scope: universal, stack: any, anchors: {}}` and emit a `frontmatter-missing` info entry (not drift). Backward-compat preserved.

### `cmd_rule_resolve` primitive

- [ ] **AC-4:** `bash .ccanvil/scripts/docs-check.sh rule-resolve <rule-id> --project-dir .` returns a JSON envelope `{rule, tier, scope, stack, anchors: {apply: [...], evidence: [...], related_rules: [...]}, body_path}`. Resolves `<rule-id>` from the basename of the rule file (e.g. `tdd` → `.claude/rules/tdd.md`).
- [ ] **AC-5:** When `<rule-id>` doesn't exist, `rule-resolve` exits 1 with `{error: "rule-not-found", rule: "<id>"}` on stdout.
- [ ] **AC-6:** When the rule file's frontmatter is malformed YAML, `rule-resolve` exits 2 with `{error: "frontmatter-malformed", rule: "<id>", reason: "<jq error excerpt>"}`.

### `ccanvil.json` stacks declaration

- [ ] **AC-7:** `ccanvil.json` accepts a top-level `stacks:` array (e.g. `["bats"]`, `["jest", "playwright"]`, `["pytest"]`). Defaults to `["any"]` when absent. The hub `.claude/ccanvil.json` declares `stacks: ["bats"]`.

### Seed atom transformations (proof-of-substrate dogfood)

- [ ] **AC-8:** `code-quality.md` (754 tokens) gains frontmatter `tier: 0, scope: universal, stack: any, anchors: {}`. No content changes — this rule is already atomic-shaped. Manifest validate exits 0; rule-resolve returns the bundle.
- [ ] **AC-9:** `workflow.md` (789 tokens) gains frontmatter `tier: 0, scope: universal, stack: any, anchors: {apply: [".claude/skills/workflow/SKILL.md (existing)"]}`. Body trimmed to the lifecycle directive and rule list (≤150 tokens). The lifecycle table content moves into a new Tier-2 reference at `docs/research/feature-lifecycle.md`. Manifest validate exits 0 with no `tier-budget-exceeded` drift on `workflow.md`.
- [ ] **AC-10:** `deterministic-first.md` (1127 tokens) atomizes: rule body trimmed to the hierarchy directive (`hook → script → command → reasoning`) plus the apply-questions list (≤150 tokens). The "Why" section + anti-pattern catalog move to a new Tier-2 reference at `docs/research/deterministic-first-foundations.md`. Frontmatter declares `anchors: {evidence: ["docs/research/deterministic-first-foundations.md"]}`. Manifest validate exits 0 with no `tier-budget-exceeded` drift on `deterministic-first.md`.

### Tests + manifests

- [ ] **AC-11:** New bats fixture `hub/tests/rule-frontmatter.bats` covers: frontmatter parsing happy path; malformed YAML; missing frontmatter (back-compat default); tier-0 budget threshold lint (file at 150 tokens passes; at 200 tokens drifts).
- [ ] **AC-12:** New bats fixture `hub/tests/rule-resolve.bats` covers: `rule-resolve <id>` happy path; rule-not-found; malformed-frontmatter error path; back-compat default envelope when no frontmatter.
- [ ] **AC-13:** All new `cmd_*` functions and helpers carry `@manifest` blocks. Added to `.ccanvil/manifest-allowlist.txt`. `bash .ccanvil/scripts/module-manifest.sh validate` exits 0 with `drift: 0`.

### Context-budget signal (substrate-level, not full target)

- [ ] **AC-14:** After AC-8/9/10 land, `bash .ccanvil/scripts/context-budget.sh check --json` shows total auto-load tokens reduced by ≥1500 from current baseline (13224 → ≤11700). This is a partial-progress signal toward the full BTS-385 target (\~5400); the seed-transformations alone don't hit the final number.

### Validation

- [ ] **AC-15:** Targeted bats files for the touched surfaces (`rule-frontmatter.bats`, `rule-resolve.bats`, `module-manifest.bats`, `operations.bats`) pass during iteration. Full `bash .ccanvil/scripts/bats-report.sh --parallel` runs once at /pr time per the test-execution-discipline rule.

## Affected Files

| File | Change |
| -- | -- |
| `.ccanvil/scripts/module-manifest.sh` | Modified: extend scanner to handle rule-file frontmatter; add tier-budget lint |
| `.ccanvil/scripts/docs-check.sh` | New: `cmd_rule_resolve`. Possibly: helper `_rule_frontmatter_parse` |
| `.claude/rules/code-quality.md` | Modified: frontmatter added (no body changes) |
| `.claude/rules/workflow.md` | Modified: frontmatter added; body trimmed; reference doc extracted |
| `.claude/rules/deterministic-first.md` | Modified: frontmatter added; body trimmed; reference doc extracted |
| `docs/research/feature-lifecycle.md` | New: extracted Tier-2 reference |
| `docs/research/deterministic-first-foundations.md` | New: extracted Tier-2 reference |
| `.claude/ccanvil.json` | Modified: declare `stacks: ["bats"]` |
| `hub/tests/rule-frontmatter.bats` | New |
| `hub/tests/rule-resolve.bats` | New |
| `.ccanvil/manifest-allowlist.txt` | Add new cmd\_\* surfaces |

## Dependencies

* **Requires:** BTS-239 (manifest substrate — frontmatter parsing precedent), BTS-265 (validate-spec — JSON envelope precedent), BTS-310 (`docs/research/` Tier-2 precedent).
* **Blocked by:** none.
* **Blocks:** BTS-384 (scope-tag distribution filter — composes on top once rules carry frontmatter).

## Out of Scope

* **Atomization audit on** `tdd.md`, `provider-integration.md`, `evidence-required-for-captures.md`, `background-task-discipline.md`, `self-review.md` — these are the larger / more substrate-bound rules. Each requires careful skill extraction and is its own PR. Captured as Session B follow-up ticket after this PR ships.
* **BTS-384 scope-tag distribution filter** — composes on top of this substrate; ships as a separate PR (Session C).
* **CLAUDE.md trim + settings.json review** — Session D scope; separate ticket.
* **Skill-discovery mechanism for stack-conditional auto-load** — research §10 open question; for v1 the agent reads `anchors.apply` from atom frontmatter and Read's the skill manually. Hook-injection-on-file-edit is a future optimization.
* **Reference docs as Linear Documents (BTS-204 SSOT extension)** — defer.
* **Atom file naming convention overhaul** (e.g. renaming to `atom-<verb>.md`) — defer to atomization audit (Session B); v1 keeps existing filenames.

## Implementation Notes

* **Frontmatter parser:** reuse the BTS-239 manifest substrate's YAML parser. Same shape (`---\nkey: value\n---`) but the schema differs (rule frontmatter has `tier`, `scope`, `stack`, `anchors`; manifest frontmatter has `purpose`, `input`, `output`, etc.). Likely a small refactor to share the parser between the two consumers.
* **Token-counting for lint:** use the same heuristic as `context-budget.sh` (currently char-count / 4 approximation). Don't introduce a tokenizer dependency.
* **Atomization for** `workflow.md` + `deterministic-first.md`: preserve the meaning verbatim — move text, don't rewrite. The Tier-2 reference is the same content with a heading, not a rewrite. After landing, `cmd_rule_resolve workflow` should return both the trimmed atom AND the reference path; an operator following the chain reads the same content they'd have seen before.
* `code-quality.md` frontmatter-only: zero body changes. Tests must verify the file remains byte-identical except for the frontmatter prepend. Safest dogfood case.
* **Backward-compat:** rule files without frontmatter MUST continue to function (default envelope). The hub itself is in mid-migration after this PR — only 3 of 8 rules carry frontmatter; the other 5 stay frontmatterless until Session B.
* **No live-API risk:** all substrate work, no external API contract uncertainty. Doesn't trigger the live-API validation gate.
* **TDD cadence (per the test-execution-discipline rule):** during iteration, run only the bats files touching modified surfaces. Full-suite at /pr time only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
