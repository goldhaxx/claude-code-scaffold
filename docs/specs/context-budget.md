# Feature: Context Budget Measurement

> Feature: context-budget
> Created: 1774234571
> Status: In Progress

## Summary

A deterministic script that measures the token cost of all always-loaded scaffold files (CLAUDE.md, rules, settings.json, .claudeignore) and reports budget utilization against research-backed thresholds. Every token in the always-loaded layer competes for attention weight — this tool makes the cost visible so the scaffold can be kept lean.

## Job To Be Done

**When** adding or modifying always-loaded scaffold files (CLAUDE.md, rules, settings),
**I want to** see exactly how much of the context budget each file consumes,
**So that** I can make informed decisions about what belongs in the always-loaded layer versus on-demand loading.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `context-budget.sh check` outputs JSON with per-file entries for every always-loaded file: `{path, lines, chars, estimated_tokens}` and a `totals` object with aggregate counts.
- [ ] **AC-2:** Token estimation uses chars/4 heuristic (industry-standard BPE approximation for English text). Each file's `estimated_tokens` equals `ceil(chars / 4)`.
- [ ] **AC-3:** `context-budget.sh check --context-window N` sets the context window size in tokens. The budget ceiling is `context_window × 0.04` (the ~4% system prompt overhead from SCAFFOLD_FRAMEWORK.md). Default context window: 200000.
- [ ] **AC-4:** `context-budget.sh check --text` outputs a human-readable table with columns: File, Lines, Tokens, % of Budget. Includes a total row, a status line (HEALTHY / WARNING / CRITICAL), and the detected/configured context window.
- [ ] **AC-5:** Exit code 0 when total is under 70% of budget (HEALTHY), exit code 1 when 70-90% (WARNING), exit code 2 when over 90% (CRITICAL).
- [ ] **AC-6:** `--budget N` flag overrides the computed budget ceiling directly (e.g., `--budget 8000`), taking precedence over `--context-window`.
- [ ] **AC-7:** The script measures both the project CLAUDE.md and the global `~/.claude/CLAUDE.md` (if it exists), reporting them as separate entries but including both in the total.
- [ ] **AC-8:** Files that don't exist are skipped silently (no error for missing optional files like global CLAUDE.md). Files that are expected but missing (project CLAUDE.md) produce a warning entry in the output.
- [ ] **AC-9:** `/scaffold-audit` integration — the scaffold-audit command includes context budget status in its report, calling `context-budget.sh check`.
- [ ] **AC-10:** CLAUDE.md line count is reported separately with a threshold warning if it exceeds 80 lines (the research-backed maximum from SCAFFOLD_FRAMEWORK.md).
- [ ] **AC-11:** `--model MODEL_ID` flag maps known models to their context window size. Supported models: `claude-opus-4-6[1m]` → 1000000, `claude-opus-4-6` → 200000, `claude-sonnet-4-6` → 200000, `claude-haiku-4-5` → 200000. Unknown models default to 200000 with a warning on stderr.
- [ ] **AC-12:** The JSON output includes a `context` object: `{model: "<model_id or null>", context_window: <tokens>, budget_ceiling: <tokens>, source: "flag|model|context-window|default"}` so the user knows how the budget was determined.

## Affected Files

| File | Change |
|------|--------|
| `scripts/context-budget.sh` | New — the measurement script |
| `tests/context-budget.bats` | New — bats tests |
| `.claude/commands/scaffold-audit.md` | Modified — add budget check step |
| `CLAUDE.md` | Modified — add command reference |
| `GUIDE.md` | Modified — add to command reference tables |

## Dependencies

- **Requires:** `jq` (already a project dependency for other scripts)
- **Blocked by:** Nothing

## Out of Scope

- Actual tokenizer integration (tiktoken, Claude tokenizer) — chars/4 is sufficient for budget monitoring. Exact counts are unnecessary for threshold-based warnings.
- Measuring on-demand files (commands, agents, skills) — these load into isolated contexts and don't compete with the always-loaded budget.
- Measuring conversation history or tool results — these are runtime concerns, not scaffold configuration concerns.
- Automatic remediation (moving content to on-demand files) — the tool reports, the user decides.

## Implementation Notes

- Follow the same script pattern as `permissions-audit.sh`: subcommand dispatch, `set -euo pipefail`, JSON primary output, `--text` flag for human-readable.
- Always-loaded file list (hardcoded, matches GUIDE.md "Always Loaded at Launch" diagram):
  - `./CLAUDE.md`
  - `~/.claude/CLAUDE.md` (global, optional)
  - `.claude/rules/*.md` (glob)
  - `.claude/settings.json`
  - `.claudeignore`
- Hook scripts (`.claude/hooks/*.sh`) execute outside the context window — they are NOT loaded as text, so they don't count against the token budget. Only their references in settings.json count.
- Budget ceiling formula: `context_window × 0.04`. For 200K → 8,000 tokens. For 1M → 40,000 tokens. The `--budget` flag overrides this formula entirely.
- `ceil(chars / 4)` can be computed in bash as `$(( (chars + 3) / 4 ))`.
- Flag precedence: `--budget` (explicit ceiling) > `--context-window` (compute ceiling) > `--model` (look up window, compute ceiling) > default (200K window, 8K ceiling).
- Model lookup table is a simple bash associative array. New models are added by editing one line — no external dependency.
- The `source` field in JSON output tracks provenance: `"flag"` if `--budget` was used, `"model"` if `--model` was used, `"context-window"` if `--context-window` was used, `"default"` otherwise.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
