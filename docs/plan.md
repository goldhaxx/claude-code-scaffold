# Implementation Plan: CLAUDE.md context budget trim

> Feature: claudemd-budget-trim
> Created: 1775520965
> Spec hash: 9251316f
> Based on: docs/spec.md

## Objective

Reduce the always-loaded context budget from 90.5% to ≤85% by trimming CLAUDE.md (both preset template and hub node section) and relocating removed content to on-demand files.

## Analysis

**What to remove from preset CLAUDE.md hub-managed section (lines 45-83):**

| Content | Lines | Action | Reason |
|---------|-------|--------|--------|
| Conventions section (5 items) | 60-65 | Remove entirely | 3 of 5 are framework-specific (API shape, barrel exports, typed env vars). The 2 universal ones (error handling, naming) already exist in `code-quality.md`. |
| Reference: @docs/decisions.md | 71-72 | Remove | File doesn't exist in the preset. Projects add their own in node section. |
| Reference: @docs/testing.md | 74-75 | Remove | Same — dangling reference. |
| Do Not: "suppress type errors" | 81 | Remove | Framework-specific (TypeScript). |
| Do Not: "database schema" | 82 | Remove | Framework-specific. |

**Estimated savings:** ~16 lines / ~260 tokens from hub-managed section.

**What to trim from hub CLAUDE.md node section (lines 1-48):**

| Content | Lines | Action | Reason |
|---------|-------|--------|--------|
| Commands: 8 of 13 entries | 16-24 | Remove 8 | Keep 5 essential commands. Full list in command-reference.md. |
| Architecture tree | 27-48 | Tighten | Remove placeholder comments, compress. |

**Estimated savings:** ~10 lines / ~200 tokens from node section.

**Projected result:** CLAUDE.md from 87 lines / 1,234 tokens → ~63 lines / ~780 tokens. Total budget from 90.5% → ~84.8%.

## Sequence

### Step 1: Relocate framework-specific conventions to guide (AC-9)
- **Test:** Grep `preset/.ccanvil/guide/getting-started.md` for "conventions" — should not exist yet.
- **Implement:** Add a "Node-Specific Conventions (Examples)" subsection to `getting-started.md` (below NODE-SPECIFIC-START or in a new section) listing the 3 framework-specific conventions as copy-paste examples for downstream projects: API response shape, barrel exports, typed env vars.
- **Files:** `preset/.ccanvil/guide/getting-started.md`
- **Verify:** Content exists in on-demand file. Not always-loaded.

### Step 2: Trim preset CLAUDE.md hub-managed section (AC-1, AC-2, AC-3)
- **Test:** Count lines in hub-managed section — currently ~38.
- **Implement:**
  - Remove entire Conventions section (lines 60-65)
  - Remove Reference Documents entries for @docs/decisions.md and @docs/testing.md (keep Preset Guide pointer)
  - Remove "Do Not" items: "suppress type errors" and "database schema"
  - Tighten remaining whitespace
- **Files:** `preset/CLAUDE.md`
- **Verify:** Hub-managed section ≤ 30 lines. No dangling references. Only universal rules in "Do Not".

### Step 3: Trim hub CLAUDE.md node section (AC-4, AC-5)
- **Test:** Count lines in node section — currently 48.
- **Implement:**
  - Commands: keep `bats hub/tests/`, `security-audit.sh`, `context-budget.sh check --text`, `docs-check.sh activate <id>`, `docs-check.sh complete <id>`. Remove the other 8. Add comment: "Full list: .ccanvil/guide/command-reference.md"
  - Architecture tree: remove NODE-SPECIFIC placeholder comments, tighten whitespace
- **Files:** `CLAUDE.md` (hub root)
- **Verify:** Node section ≤ 45 lines. Architecture preserved.

### Step 4: Propagate template to hub root (AC-6)
- **Test:** Run `wc -l CLAUDE.md` — should be ≤ 80.
- **Implement:** Section-merge the updated preset/CLAUDE.md into hub root CLAUDE.md to pick up the hub-managed changes while preserving the trimmed node section.
- **Files:** `CLAUDE.md`
- **Verify:** Total CLAUDE.md ≤ 80 lines.

### Step 5: Verify context budget (AC-7, AC-8)
- **Test:** Run `bash .ccanvil/scripts/context-budget.sh check --text`.
- **Implement:** If budget is still > 85%, identify next trim candidate (tls-troubleshooting.md is 16.1% — could extract tool-specific fixes to on-demand). Only trim further if needed.
- **Files:** Potentially `preset/.claude/rules/tls-troubleshooting.md`
- **Verify:** Budget ≤ 85%. Exit code 0 or 1 (not 2/CRITICAL).

### Step 6: Full test suite + downstream check (AC-10, AC-11)
- **Test:** `bats hub/tests/` — all 352+ pass.
- **Implement:** Fix any failures.
- **Files:** Any affected test files.
- **Verify:** 352/352 pass. Downstream template is coherent.

## Risks

| Risk | Mitigation |
|------|-----------|
| Removing conventions breaks downstream expectations | AC-9 ensures all content relocated. Framework-specific items become examples in guide, not always-loaded. |
| Budget still > 85% after CLAUDE.md trim | Step 5 has a fallback: trim tls-troubleshooting.md if needed. |
| Section-merge loses hub node content | Step 4 uses the sync script's section-merge, which preserves node sections by design. |

## Definition of Done

- [ ] All acceptance criteria from spec pass (11 ACs)
- [ ] All existing tests still pass (352+)
- [ ] `context-budget.sh check` exits non-CRITICAL
- [ ] Code reviewed (run /review)
