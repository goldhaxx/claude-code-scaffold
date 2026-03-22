# Implementation Plan: Determinism Enforcement

> Feature: determinism-enforcement
> Created: 1774212158
> Spec hash: 4b20797e
> Based on: docs/spec.md

## Objective

Make end-of-session determinism review mandatory via checkpoint template, validate enforcement in docs-check.sh, add a safety-net `audit-session` script for post-hoc detection, and wire it all into `/catchup` for cross-session continuity.

## Sequence

### Step 1: Checkpoint template — required Determinism Review section (AC-1)
- **Test:** Template has `## Determinism Review` section with `operations_reviewed`, `candidates_found` fields and bulleted list format
- **Implement:** Add the required section to `docs/templates/checkpoint.md` above the NODE-SPECIFIC delimiter
- **Files:** `docs/templates/checkpoint.md`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — new template test passes, existing template tests still pass

### Step 2: validate reports missing-determinism-review (AC-4)
- **Test:** `docs-check.sh validate` returns `missing-determinism-review` when checkpoint exists but has no `## Determinism Review` section (or empty/placeholder)
- **Implement:** Extend `cmd_validate` in `docs-check.sh` to check for the section after other checks pass
- **Files:** `scripts/docs-check.sh`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — new validate tests pass, existing tests unaffected

### Step 3: audit-session basic pattern scanning (AC-5, AC-6)
- **Test:** `docs-check.sh audit-session` scans a git diff for stochastic patterns (`cp `, `jq `, `shasum`, `git -C`, `curl`, `wget`) and outputs JSON with `patterns_found` array and `summary` object
- **Implement:** Add `cmd_audit_session` to `docs-check.sh` — uses `git diff --unified=0` to get changed lines, greps for patterns, outputs structured JSON
- **Files:** `scripts/docs-check.sh`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — tests with mock git repos containing known patterns

### Step 4: audit-session --since flag (AC-7)
- **Test:** `audit-session --since <commit>` scans from specified commit; without flag, defaults to checkpoint metadata or last 10 commits
- **Implement:** Add flag parsing to `cmd_audit_session`, read checkpoint.md metadata for default commit
- **Files:** `scripts/docs-check.sh`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — tests with different --since values

### Step 5: audit-session allowlist (AC-8)
- **Test:** Patterns found in `scripts/*.sh` are excluded from results; same patterns in other files are reported
- **Implement:** Add allowlist logic — skip matches in `scripts/*.sh` files by default
- **Files:** `scripts/docs-check.sh`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — zero false positives on scaffold scripts

### Step 6: audit-session commit message scanning (AC-9)
- **Test:** Commit messages containing "manually ran", "had to", "workaround" are flagged in output
- **Implement:** Add `git log --format=%s` scan to `cmd_audit_session`, grep for indicator phrases
- **Files:** `scripts/docs-check.sh`, `tests/docs-check.bats`
- **Verify:** `bats tests/docs-check.bats` — tests with mock commits containing indicator phrases

### Step 7: Workflow rule — checkpoint flow and checklist (AC-2, AC-3)
- **Test:** `workflow.md` contains checkpoint flow order (content → review → write section → commit → suggest /clear) and the 4-item checklist
- **Implement:** Update Context Preservation section in `workflow.md`
- **Files:** `.claude/rules/workflow.md`, `tests/docs-check.bats`
- **Verify:** `bats tests/` — grep-based tests confirm rule content; existing tests still pass

### Step 8: Self-review.md update
- **Test:** `self-review.md` references mandatory `## Determinism Review` section and the warm-context checklist
- **Implement:** Update self-review.md to reference the mandatory checkpoint section instead of optional "Determinism Notes"
- **Files:** `.claude/rules/self-review.md`, `tests/docs-check.bats`
- **Verify:** `bats tests/` — grep-based tests confirm references

### Step 9: /catchup integration (AC-10, AC-11)
- **Test:** `catchup.md` includes steps to read Determinism Review section and run `audit-session`
- **Implement:** Update catchup.md to surface outstanding determinism items and run audit-session
- **Files:** `.claude/commands/catchup.md`, `tests/docs-check.bats`
- **Verify:** `bats tests/` — grep-based tests confirm catchup references

### Step 10: Documentation updates
- **Test:** README manifest includes `audit-session` description; GUIDE command reference includes `audit-session`
- **Implement:** Update README scripts table and GUIDE command reference + docs lifecycle scripts table
- **Files:** `README.md`, `GUIDE.md`, `tests/docs-check.bats`
- **Verify:** `bats tests/` — all tests pass; `bash scripts/manifest-check.sh check README.md` shows verified

## Risks

- **Git test isolation:** audit-session tests need real git repos with commits. Use `git init` in BATS temp dirs with controlled commits. Risk: test pollution if cleanup fails. Mitigation: BATS teardown handles cleanup.
- **Pattern false positives:** Regex patterns for `cp `, `jq ` etc. could match legitimate code comments or strings. Mitigation: allowlist mechanism (AC-8) and line-level context in output.
- **Checkpoint commit detection:** Finding the "last checkpoint commit" from metadata may be fragile if metadata format changes. Mitigation: fallback to `git log --grep` and then to last-10-commits default.

## Definition of Done

- [ ] All 11 acceptance criteria from spec pass
- [ ] All existing tests still pass (144 + new tests)
- [ ] No syntax errors (`bash -n scripts/docs-check.sh`)
- [ ] Code reviewed (run /review)
- [ ] README manifest verified (`bash scripts/manifest-check.sh check README.md`)
