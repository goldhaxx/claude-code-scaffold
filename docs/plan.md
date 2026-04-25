# Implementation Plan: Gate `rm -rf` in guard-destructive.sh

> Feature: bts-156-gate-rm-rf
> Work: linear:BTS-156
> Created: 1777151400
> Spec hash: 552141e5
> Based on: docs/spec.md

## Objective

Add a path-agnostic recursive-AND-force `rm` block to `guard-destructive.sh`, with bypass via the existing `ALLOW_DESTRUCTIVE=1` envelope, fully tested in `hub/tests/guard-hooks.bats`.

## Sequence

### Step 1: Add a failing test for the canonical `rm -rf` form (AC-1)
- **Test:** New test in `hub/tests/guard-hooks.bats` after the chmod block: `guard-destructive: blocks rm -rf`. Input `rm -rf /tmp/foo`, assert exit 2, stderr contains `BLOCKED:` and `rm -rf`.
- **Implement:** None yet — confirm the test fails (currently `rm` is unblocked, exit 0).
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** `bash .ccanvil/scripts/bats-report.sh -f 'blocks rm -rf'` shows 1 failing.

### Step 2: Add the cluster-flag block in the hook (AC-1, AC-2)
- **Test:** Step 1 test, plus add tests for the cluster variants from AC-2: `rm -fr`, `rm -rfv`, `rm -fR`, `rm -Rfv`. Five tests total at this point.
- **Implement:** After the chmod block in `.claude/hooks/guard-destructive.sh`, add:
  ```bash
  if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$) ]]; then
    echo "BLOCKED: rm -rf (and combined recursive+force variants) recursively delete without prompt." >&2
    echo "  To bypass: ALLOW_DESTRUCTIVE=1 rm -rf ..." >&2
    exit 2
  fi
  ```
- **Files:** `.claude/hooks/guard-destructive.sh`, `hub/tests/guard-hooks.bats`.
- **Verify:** All 5 tests green.

### Step 3: Add the long-form block (AC-3)
- **Test:** Two tests for `rm --recursive --force /tmp/foo` and `rm --force --recursive /tmp/foo` (either order). Both should be blocked.
- **Implement:** Add a second branch:
  ```bash
  if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]] ]] && [[ "$COMMAND" =~ --recursive ]] && [[ "$COMMAND" =~ --force ]]; then
    echo "BLOCKED: rm --recursive --force recursively deletes without prompt." >&2
    echo "  To bypass: ALLOW_DESTRUCTIVE=1 rm --recursive --force ..." >&2
    exit 2
  fi
  ```
- **Files:** `.claude/hooks/guard-destructive.sh`, `hub/tests/guard-hooks.bats`.
- **Verify:** All 7 tests green.

### Step 4: Bypass works (AC-4)
- **Test:** `ALLOW_DESTRUCTIVE=1 rm -rf /tmp/foo` exits 0. Should pass without code changes — line 15 short-circuits.
- **Implement:** None.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** Test green.

### Step 5: Allow safe `rm` shapes (AC-5, AC-6, AC-7, AC-8)
- **Test:** Add tests for: `rm -r dir/`, `rm -R dir/`, `rm -f file`, `rm --force file`, `rm file1 file2`, `rm -i -f file` (interactive+force, no recursive), `rm -v -r dir/` (verbose+recursive, no force). All exit 0.
- **Implement:** None expected — the cluster regex requires BOTH r/R AND f in the same flag chunk; `-i -f` and `-v -r` have separate chunks. Verify the regex doesn't false-positive. If any test fails, narrow the regex.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** All 7 new "allow" tests green.

### Step 6: Word-boundary anchor verification (AC-9)
- **Test:** `form -rf foo` and `arm -rf foo` exit 0 (substring `rm` inside another word should NOT match). Two tests.
- **Implement:** The `(^|[[:space:]])rm[[:space:]]` anchor in step 2 already handles this. Verify.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** Both tests green.

### Step 7: Path-agnostic spot checks (AC-10)
- **Test:** Three tests confirming the block fires regardless of path: `rm -rf /tmp/foo`, `rm -rf ./foo`, `rm -rf ~/projects/x`. All exit 2.
- **Implement:** None — already covered by the regex which doesn't inspect paths.
- **Files:** `hub/tests/guard-hooks.bats`.
- **Verify:** All 3 tests green.

### Step 8: Regression — existing gates intact (AC-11)
- **Verify:** Run the full guard-hooks suite (`bash .ccanvil/scripts/bats-report.sh -f guard-hooks`). All pre-BTS-156 tests still pass. Then run the entire suite (`bash .ccanvil/scripts/bats-report.sh --parallel`) to confirm no cross-file regressions.

### Step 9: Documentation
- **Implement:** Update the hub section of `.ccanvil/guide/hooks.md` (or whichever guide file documents PreToolUse hooks) to mention the new rm-recursive-force gate alongside the existing chmod / git gates. One paragraph.
- **Files:** `.ccanvil/guide/hooks.md` (or equivalent — verify path during step).
- **Verify:** Re-read the section; it accurately describes the gate and bypass envelope.

## Risks

- **Regex false-positives.** The cluster regex must match `-rf` but not `-rzfx` if some unrelated tool uses such flags after `rm`. Mitigation: the regex requires BOTH r/R AND f in a single `-` chunk; covered by AC-8 / AC-9 tests.
- **xargs / pipe blind spots.** `find . -type d | xargs rm -rf` reaches `rm -rf` via xargs; the hook only sees the literal command string. Acknowledged in spec Out of Scope. Not a regression — current behavior is also blind to this.
- **Surprise to operator.** The block is new; existing scripts that legitimately need `rm -rf` (like cleanup in build pipelines) will need `ALLOW_DESTRUCTIVE=1` prefixed. Mitigation: bypass syntax in stderr; pattern matches existing chmod block.

## Definition of Done

- [ ] All 11 acceptance criteria pass with bats tests
- [ ] Existing guard-hooks tests still pass (no regressions)
- [ ] Full suite runs green via `bats-report.sh --parallel`
- [ ] Hook source has explanatory comment matching the chmod-block style
- [ ] Code reviewed (`/review`)
