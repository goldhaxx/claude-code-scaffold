# Implementation Plan: Context Budget Measurement

> Feature: context-budget
> Created: 1774235150
> Spec hash: 9889e126
> Based on: docs/spec.md

## Objective

Build a deterministic bash script that measures token cost of always-loaded scaffold files and reports budget utilization with model-aware thresholds.

## Sequence

### Step 1: Script skeleton with usage and arg parsing
- **Test:** `context-budget.sh` with no args prints usage and exits 2. `context-budget.sh check` exits 0 with valid JSON.
- **Implement:** Script boilerplate: `set -euo pipefail`, usage function, argument parsing loop (check command, --text, --budget, --context-window, --model flags), dispatch.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 2: File discovery and per-file measurement (AC-1, AC-2)
- **Test:** `check` outputs JSON with `files` array containing entries for project CLAUDE.md, rules/*.md, settings.json, .claudeignore. Each entry has `path`, `lines`, `chars`, `estimated_tokens`. Token estimate = ceil(chars/4).
- **Implement:** Glob for always-loaded files, `wc -c` and `wc -l` for each, compute tokens, build JSON array.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 3: Budget computation and exit codes (AC-3, AC-5, AC-12)
- **Test:** Default budget = 200000 * 0.04 = 8000. JSON includes `totals` with aggregate counts and `budget_percent`. JSON includes `context` object with model/context_window/budget_ceiling/source. Exit 0 when under 70%, exit 1 when 70-90%, exit 2 when over 90%.
- **Implement:** Compute totals from file array, compute budget_percent, determine status and exit code, add context object.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 4: --context-window, --model, --budget flags (AC-3, AC-6, AC-11)
- **Test:** `--context-window 1000000` sets budget to 40000. `--model claude-opus-4-6[1m]` sets window to 1000000. `--budget 5000` overrides computed ceiling. Unknown model warns on stderr and defaults to 200K. Flag precedence: budget > context-window > model > default.
- **Implement:** Model lookup via case statement (bash 3 compatible), flag precedence logic, source tracking.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 5: Global CLAUDE.md and missing file handling (AC-7, AC-8)
- **Test:** When global CLAUDE.md exists, it appears in files array. When it doesn't exist, it's silently skipped. When project CLAUDE.md is missing, a warning entry appears.
- **Implement:** Check `~/.claude/CLAUDE.md` existence, add to file list if present. Mark project CLAUDE.md as expected; report warning if missing.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 6: CLAUDE.md line count warning (AC-10)
- **Test:** JSON includes `warnings` array. When CLAUDE.md exceeds 80 lines, a warning entry appears with the line count.
- **Implement:** Check line count of project CLAUDE.md, add warning to output if > 80.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 7: Text output mode (AC-4)
- **Test:** `--text` outputs table with File/Lines/Tokens/% columns, total row, status line (HEALTHY/WARNING/CRITICAL), and context window info.
- **Implement:** Format file array as aligned table, compute and display status.
- **Files:** `scripts/context-budget.sh`, `tests/context-budget.bats`
- **Verify:** bats tests pass

### Step 8: Scaffold-audit integration + docs updates (AC-9)
- **Test:** Verify scaffold-audit command references context-budget.sh.
- **Implement:** Add context budget check step to scaffold-audit command. Update CLAUDE.md command reference and GUIDE.md tables.
- **Files:** `.claude/commands/scaffold-audit.md`, `CLAUDE.md`, `GUIDE.md`
- **Verify:** bats tests pass, full test suite passes

## Risks

- **macOS wc padding:** `wc` on macOS pads output with spaces. Use `awk` or `tr -d ' '` to normalize.
- **Bash 3 on macOS:** macOS ships bash 3 which lacks associative arrays. Use `case` statement for model lookup instead.
- **Test isolation:** Tests need fixture directories with known file content to get deterministic token counts. Use bats `setup`/`teardown` with temp dirs.

## Definition of Done

- [ ] All 12 acceptance criteria from spec pass
- [ ] All existing tests still pass (256 baseline)
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
