# Feature: CLAUDE.md context budget trim

> Feature: claudemd-budget-trim
> Created: 1775520520
> Status: Complete

## Summary

The always-loaded context budget is at 90.5% (7,239 of 8,000 tokens). CLAUDE.md alone is 87 lines / 1,234 tokens — exceeding the 80-line recommended maximum from foundations.md research. Every excess token in always-loaded files steals attention from the actual task.

This feature trims CLAUDE.md (both the hub-specific node section and the hub-managed preset template) and audits the other top token consumers for relocation opportunities.

## Job To Be Done

**When** Claude starts any session in a ccanvil-managed project,
**I want** the always-loaded context to be lean and high-signal,
**So that** maximum attention is available for the actual task, not boilerplate.

## Current State (from context-budget.sh)

| File | Lines | Tokens | % Budget |
|------|-------|--------|----------|
| tls-troubleshooting.md | 134 | 1,291 | 16.1% |
| CLAUDE.md | 87 | 1,234 | 15.4% |
| workflow.md | 72 | 1,158 | 14.5% |
| deterministic-first.md | 47 | 821 | 10.3% |
| settings.json | 98 | 628 | 7.8% |
| global CLAUDE.md | 31 | 548 | 6.9% |
| code-quality.md | 42 | 495 | 6.2% |
| self-review.md | 41 | 452 | 5.7% |
| tdd.md | 39 | 430 | 5.4% |
| .claudeignore | 57 | 182 | 2.3% |
| **TOTAL** | **648** | **7,239** | **90.5%** |

## Acceptance Criteria

### CLAUDE.md preset template (hub-managed section)

- [ ] **AC-1:** Hub-managed section of `preset/CLAUDE.md` is ≤ 30 lines (currently ~38). The Workflow section is preserved. Generic conventions that don't apply to all projects (API response shape, barrel exports, typed env vars) are moved to an on-demand rule or removed.
- [ ] **AC-2:** Reference Documents section has no dangling references — entries pointing to files that don't exist in the preset (`@docs/decisions.md`, `@docs/testing.md`) are removed or made conditional.
- [ ] **AC-3:** "Do Not" section retains only universally-applicable rules. Framework-specific rules (database schema, type errors) are removed from the template and noted as examples in the guide.

### CLAUDE.md hub-specific section (node section)

- [ ] **AC-4:** Hub CLAUDE.md node section is ≤ 45 lines (currently 48). Commands section is trimmed — keep the 4-5 most essential commands, move the full list to a discoverable location.
- [ ] **AC-5:** Architecture tree is preserved but tightened — no wasted lines.

### Overall budget

- [ ] **AC-6:** Total CLAUDE.md (hub) is ≤ 80 lines.
- [ ] **AC-7:** Total always-loaded context budget is ≤ 85% (currently 90.5%). This may require trimming files beyond CLAUDE.md.
- [ ] **AC-8:** `context-budget.sh check` exits with status 0 (OK or WARNING, not CRITICAL).

### No information lost

- [ ] **AC-9:** Every convention or rule removed from CLAUDE.md still exists in an on-demand file (rule, guide section, or template). Nothing is deleted — only relocated.
- [ ] **AC-10:** Downstream projects that pull the updated template see a cleaner CLAUDE.md without losing any hub-managed functionality.

### Tests pass

- [ ] **AC-11:** All hub bats tests pass (352+).

## Affected Files

| File | Change |
|------|--------|
| `preset/CLAUDE.md` | Trim hub-managed section, relocate conventions |
| `CLAUDE.md` (hub root) | Trim node section, reduce commands list |
| `preset/.claude/rules/code-quality.md` | May absorb relocated conventions |
| `preset/.ccanvil/guide/index.md` | May absorb reference doc pointers |
| `.claude/rules/*.md` | Potential trim candidates for AC-7 |

## Constraints

- The hub-managed section delimiter (`<!-- HUB-MANAGED-START -->`) and node-specific content must remain intact.
- The 6-step workflow is non-negotiable — it's the core methodology.
- Rules files (.claude/rules/) are always-loaded. Moving content there doesn't reduce budget — only moving to on-demand files (guide, templates) does.
- tls-troubleshooting.md (16.1%) is the biggest consumer but serves a critical function (auto-fix VPN cert issues). Trimming it requires care.

## Out of Scope

- Restructuring the rules directory or settings.json.
- Changes to the context-budget.sh script itself.
- Global CLAUDE.md (~/.claude/CLAUDE.md) — that's user-controlled.
