# Implementation Plan: Gate find -delete/-exec in guard-destructive.sh

> Feature: bts-155-gate-find-destructive
> Work: linear:BTS-155
> Created: 1777152500
> Spec hash: 25decb9e
> Based on: docs/spec.md

## Objective

Add a path-agnostic destructive-find gate to `.claude/hooks/guard-destructive.sh` and add `find` to `.claude/hooks/guard-workspace.sh`'s verb regex. Tests in `hub/tests/guard-hooks.bats`.

## Sequence

### Step 1: Add failing tests for AC-1..AC-7 (destructive-find shape) and AC-9 (word anchor)
- **Test:** New BTS-155 test block in `guard-hooks.bats` after the BTS-156 block: `find . -delete`, `find . -exec rm {} +`, `find . -exec rm {} \;`, `find . -execdir chmod 644 {} +`, `find . -okdir rm {} \;`, `ALLOW_DESTRUCTIVE=1 find . -delete` (allow), three read-only finds (allow), `xfind . -delete` (allow).
- **Implement:** None yet — confirm tests fail.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** Run `bats-report.sh hub/tests/guard-hooks.bats` and confirm new tests fail (red).

### Step 2: Add the destructive-find gate to guard-destructive.sh
- **Implement:** After the BTS-156 rm block, add:
  ```bash
  # Block find with -delete or -exec/-execdir/-okdir. Path-agnostic:
  # the recursive traverse-and-mutate shape is the catastrophic footgun,
  # regardless of target. (BTS-155)
  if [[ "$COMMAND" =~ (^|[[:space:]\;\|\&])find[[:space:]] ]] \
     && [[ "$COMMAND" =~ (^|[[:space:]])(-delete|-exec|-execdir|-okdir)([[:space:]]|$) ]]; then
    echo "BLOCKED: find with -delete or -exec/-execdir/-okdir traverses then mutates." >&2
    echo "  To bypass: ALLOW_DESTRUCTIVE=1 find ..." >&2
    exit 2
  fi
  ```
- **Files:** `.claude/hooks/guard-destructive.sh`.
- **Verify:** Step 1 tests now pass.

### Step 3: AC-8 edge — `-delete` as name pattern argument
- **Test:** `find . -name '-delete' -print` exits 0. Note the regex requires `-delete` as a flag token (preceded by space, followed by space or end). Inside `-name '-delete'`, the `'-delete'` is wrapped in single quotes → guard tokenizes after stripping quotes (line 56 of guard-workspace, but guard-destructive doesn't tokenize — uses raw string). The regex `(^|[[:space:]])(-delete|...)([[:space:]]|$)` against the raw command `find . -name '-delete' -print` will match `-delete` because the quotes around `-delete` make it adjacent to `'` which isn't `[[:space:]]`. So this test will INITIALLY fail. Need to inspect.
- **Implement:** If the regex false-positives on quoted `-delete`, refine — likely add quote chars to the boundary class: `(^|[[:space:]'"])(-delete|...)([[:space:]'"]|$)`. Run test, iterate.
- **Files:** `.claude/hooks/guard-destructive.sh`, `hub/tests/guard-hooks.bats`.
- **Verify:** AC-8 passes.

### Step 4: AC-10 + AC-11 — workspace fence on find with absolute paths
- **Test:** `find /etc -name '*'` blocks (workspace fence). `find /tmp -name '*.log'` allows (whitelisted). Add to bats.
- **Implement:** In `.claude/hooks/guard-workspace.sh:31`, add `find` to verb regex: `(rm|cp|mv|chmod|chown|bash|find)`.
- **Files:** `.claude/hooks/guard-workspace.sh`, `hub/tests/guard-hooks.bats`.
- **Verify:** Both tests pass.

### Step 5: Regression sweep
- **Verify:** `bats-report.sh --parallel` — all 1175+ tests still pass. Then `bats-lint.sh hub/tests/` — no new BTS-127 leaks.

### Step 6: Documentation
- **Implement:** Update `.ccanvil/guide/hooks.md` row for `guard-destructive.sh` to mention the new find gate alongside the rm/chmod/git gates.
- **Files:** `.ccanvil/guide/hooks.md`.

## Risks

- **Regex false-positive on quoted `-delete`.** Step 3 covers this. If unsolvable, document as known limitation and accept the false-positive (rare in practice — `-name '-delete'` is contrived).
- **Workspace fence interaction with find subtree.** `find ~/projects/ccanvil -name x` should pass — `~/projects/` is whitelisted. Verify in step 4.
- **Hook firing on `find` as a substring of `findutils` documentation in commit messages.** Same family as BTS-151. Mitigate by writing commit messages to file when needed.

## Definition of Done

- [ ] All 12 ACs pass via bats
- [ ] `bats-report.sh --parallel`: all green
- [ ] `bats-lint.sh hub/tests/`: no new leaks introduced
- [ ] Hook source has explanatory comment
- [ ] Code reviewed via `/review`
