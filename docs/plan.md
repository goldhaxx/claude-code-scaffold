# Implementation Plan: Add sort to guard-workspace verb regex

> Feature: bts-157-gate-sort-o
> Work: linear:BTS-157
> Created: 1777153400
> Spec hash: 3bac5d42
> Based on: docs/spec.md

## Objective

One-line change to `.claude/hooks/guard-workspace.sh` — add `sort` to the gated-verb regex. The existing path-token iteration handles the rest.

## Sequence

### Step 1: Write tests for AC-1..AC-9 (red)
- **Test:** New BTS-157 block in `guard-hooks.bats` after BTS-155: blocked cases (`sort -o ~/.zshrc`, `sort -o /etc/foo`, `sort input > ~/.zshrc`), allowed cases (`./local-output`, `~/projects/ccanvil/foo`, `/tmp/foo`, plain `sort input`, `xsort -o ~/.zshrc x`), bypass (`ALLOW_OUTSIDE_WORKSPACE=1 sort -o ~/.zshrc`).
- **Implement:** None yet.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** Blocked-case tests fail (current verb regex misses sort).

### Step 2: Add sort to verb regex
- **Implement:** `.claude/hooks/guard-workspace.sh:31` → add `sort` to alternation. Refresh header comment on line 3.
- **Files:** `.claude/hooks/guard-workspace.sh`.
- **Verify:** All BTS-157 tests green.

### Step 3: Regression sweep
- **Verify:** `bats-report.sh --parallel` (target 1188 + 9 = 1197 tests). `bats-lint.sh hub/tests/guard-hooks.bats` clean.

## Risks

- **False-positive on commit messages.** `git commit -m "fix sort"` on a body with `sort` plus a `~/foo` path-token — same family as BTS-151. Existing workaround: write to file, use `commit -F`.
- **Operator scripts using `sort -o`.** Likely rare for paths outside `~/projects/`; if blocked, `ALLOW_OUTSIDE_WORKSPACE=1` is the documented bypass.

## Definition of Done

- [ ] All 10 ACs pass via bats
- [ ] Full suite green
- [ ] Lint clean (no new BTS-127 leaks)
- [ ] Code reviewed via `/review`
