# Feature: Rule distribution scope + abstraction discipline

> Feature: bts-384-rule-distribution-scope
> Work: linear:BTS-384
> Created: 1778364361
> Subject: Rule distribution scope + abstraction discipline
> Status: Complete

## Summary

Hub `.claude/rules/*.md` distribute unconditionally to every downstream node via `ccanvil-sync.sh`'s `TRACKED_PATTERNS`. Rules already carry a `scope:` frontmatter field (BTS-385 substrate, all 9 currently `universal`) — but distribution does not honor it. Add a `scope:`-aware filter at sync time, a node-side `role:` opt-in flag, and a vocabulary-leak drift-guard for `universal` rules so downstream agent context only contains rules that apply to the node's stack and role.

## Job To Be Done

**When** I author or update a hub rule and run `/ccanvil-pull` on a downstream node,
**I want** the node to receive only rules whose `scope:` matches its `role:`, with vocabulary stack-neutral in `universal` rules,
**So that** every sentence the agent reads is relevant to that node's context (no hub-substrate leak).

## Acceptance Criteria

- [ ] **AC-1: scope vocabulary.** `module-manifest.sh validate` accepts `scope: universal | substrate | hub-only` on rule frontmatter. Unknown values emit `rule-scope-invalid` to `drift[]` (block-shape). Missing `scope:` defaults to `universal` and emits `rule-scope-missing` to `info[]` (advisory).
- [ ] **AC-2: role field.** `.claude/ccanvil.json` accepts a top-level `role: hub-substrate-developer | substrate-consumer` string. When absent, `ccanvil-sync.sh` and dependents treat the node as `substrate-consumer`. Hub's own `ccanvil.json` is updated to `role: hub-substrate-developer`.
- [ ] **AC-3: substrate filter at sync.** `ccanvil-sync.sh` distribution path (`is_distributable_path` or its caller chain) skips a hub file with `scope: substrate` when the destination node's `role` is `substrate-consumer`. Verified via `pull-plan` preview output: substrate-tagged rules appear under a `skipped (scope-filter)` bucket, not under `pull` or `auto-update`.
- [ ] **AC-4: hub-only filter at sync.** Files with `scope: hub-only` never appear in any `pull-plan`, regardless of node `role` — including `hub-substrate-developer`. Hub-only files live at the hub source by definition; the sync mechanism never distributes them anywhere.
- [ ] **AC-5: vocabulary drift-guard.** `module-manifest.sh validate` scans `scope: universal` rule bodies for hub-specific tokens (`bats-report.sh`, `module-manifest.sh`, `ccanvil-sync.sh`, `BTS-N` patterns) appearing OUTSIDE an `## Anchored on (...)` block, emits one `rule-vocabulary-leak` entry per file to `info[]` (advisory; warn-shape only). Tokens inside a fenced anchor block are exempt.
- [ ] **AC-6: audit-pass.** At least one existing hub rule is re-tagged from `universal` → `substrate` based on operator review, with the surfaced vocabulary-leak findings. `provider-integration.md` is the canonical candidate (it is literally about ccanvil http-vs-MCP). The audit-pass commit lists each rule's pre/post `scope:` value in its body.
- [ ] **AC-7: edge — missing role on downstream.** Given: a downstream `ccanvil.json` with no `role:` field. When: `ccanvil-sync.sh pull-plan` runs against the hub. Then: `scope: substrate` files are filtered identically to an explicit `role: substrate-consumer` (no null-coalescing crash; same `skipped (scope-filter)` bucket entries).
- [ ] **AC-8: tests.** Bats fixtures cover scope-filter matrix (3 scopes × 2 roles = 6 cases) + vocabulary drift-guard (with/without anchor block). `module-manifest.sh validate` exits 0 with `drift: 0`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | New: scope-filter integration in `is_distributable_path` callers (`cmd_pull_plan`, `cmd_changelog`, `scan_hub_files`). Read node `role` from `ccanvil.json` once at sync entry. |
| `.ccanvil/scripts/module-manifest.sh` | Modified: extend rule frontmatter parser to extract `scope:`, emit `rule-scope-invalid` (drift) / `rule-scope-missing` (info). Add `rule-vocabulary-leak` scan over `scope: universal` rule bodies. |
| `.claude/ccanvil.json` | Modified: add `"role": "hub-substrate-developer"` at top level. |
| `.ccanvil/templates/ccanvil.json.md` | Modified: default `role: substrate-consumer` on `/ccanvil-init`. |
| `.claude/rules/provider-integration.md` | Modified: frontmatter `scope: universal` → `scope: substrate`. |
| `hub/tests/rule-distribution-scope.bats` | New: scope-filter matrix + role-default + missing-frontmatter cases. |
| `hub/tests/rule-vocabulary-leak.bats` | New: drift-guard fixtures with hub-specific tokens inside/outside anchor blocks. |

## Dependencies

- **Requires:** BTS-385 (rule frontmatter substrate, SHIPPED) — frontmatter parser already extracts `tier`; this extends to `scope`.
- **Requires:** BTS-386 (rule-tier-validator extension, SHIPPED) — drift-guard plumbing pattern (warn-shape `info[]`, block-shape `drift[]`) is already in place.
- **Blocked by:** none.

## Out of Scope

- **Profile-based opt-in** (`testing-discipline`, `ai-collab-meta`) — single `role` enum suffices until a third role appears empirically. Capture as follow-up if pattern emerges.
- **Drift-guard severity escalation** — vocabulary-leak stays advisory (`info[]`) in v1; escalate to blocking (`drift[]` + `--strict`) only after a soak window.
- **Migration of already-deployed nodes** — handled by next routine `/ccanvil-pull`; one-time correction noise expected. No proactive heal pass.
- **Stack-aware filtering** — `stack:` field already exists on frontmatter (`stack: any` today). Stack-driven distribution lives in BTS-312 (test-runner indirection); BTS-384 honors `scope:` only.

## Implementation Notes

- Audit-pass may surface additional rule(s) needing re-tag from `universal` → `substrate` based on the AC-5 vocabulary-leak scan output (e.g., `self-review.md` if it references hub-specific tokens). Re-tag list is determined empirically from the leak scan, not pre-specified.
- Keep filter integration narrow: read `role` once in `cmd_pull_plan` entry, pass into `is_distributable_path` (or a sibling `is_scope_allowed`). Avoid threading through every helper.
- `pull-plan` preview output gets a new bucket `skipped (scope-filter: <scope> not allowed for role=<role>)` so operators see the filter at work, not silent omission.
- Vocabulary-leak token list lives in module-manifest.sh as a constant array. Start narrow (`bats-report.sh`, `module-manifest.sh`, `ccanvil-sync.sh`, `linear-query.sh`, `docs-check.sh`, `BTS-[0-9]+`); expand if leaks slip through.
- Anchor block convention: `## Anchored on (<hub-id>)` — substrate enforces presence in `scope: substrate` rules (later phase); v1 only checks anchor-membership for the leak-scan exemption.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
