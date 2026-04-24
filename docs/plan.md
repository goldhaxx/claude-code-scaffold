# Implementation Plan: Land Post-Merge Branch Recovery

> Feature: bts-138-land-post-merge-branch-recovery
> Work: linear:BTS-138
> Created: 1777063437
> Spec hash: e56bbff5
> Based on: docs/spec.md

## Objective

Extend `cmd_land`'s `branch == main` path so that it recovers the landed feature branch from the last squash-merge commit's `(#<PR>)` suffix and delegates to `cmd_auto_close_emit` — closing the 3rd-consecutive-stasis determinism-review gap.

## Sequence

Each step is one red-green-refactor cycle. All tests live in the new file `hub/tests/land-post-merge-recovery.bats` unless noted. Each step runs `bash .ccanvil/scripts/bats-report.sh -f <filter>` for the relevant tests, then the full suite at the end to confirm AC-7 (no regressions).

### Step 1: Bats test scaffolding + gh shim helper
- **Test:** Write test #1 for AC-1 (happy path: HEAD = squash merge `(#54)`, stub `gh pr view 54` → `claude/feat/<slug>`, assert `AUTO-CLOSE: {"provider":"linear","id":"BTS-X","role":"done"}` on stdout).
- **Implement:** In test `setup()`, seed a tmpdir git repo; write a `gh` shim to `$PROJECT/.bin/gh` that reads `$@`, looks for `pr view <N> --json headRefName -q .headRefName`, and prints a pre-configured branch name from an env var `FAKE_HEAD_REF`. Prepend to PATH.
- **Files:** NEW `hub/tests/land-post-merge-recovery.bats`. NEW `hub/tests/helpers/gh-shim.bash` (shared helper if other tests need it later; inline for now if simpler).
- **Verify:** Test fails with "assert AUTO-CLOSE emitted" because `cmd_land` on main today never calls `cmd_auto_close_emit`.

### Step 2: Add `cmd_land` main-path recovery — happy path (AC-1)
- **Test:** #1 from step 1.
- **Implement:** In `cmd_land` at `.ccanvil/scripts/docs-check.sh:1309-1324` (the `branch == main` block), after the fast-forward + before the `return 0`, inline the recovery logic:
  1. `git log -1 --format=%s` → capture subject.
  2. Regex `(#([0-9]+))$` to extract PR number; if no match, WARN + return 0.
  3. `command -v gh` → if missing, WARN + return 0 (AC-8).
  4. `gh pr view <N> --json headRefName -q .headRefName` → capture branch name; if exit nonzero or empty, WARN + return 0.
  5. `cmd_auto_close_emit "$recovered_branch"` — delegate.
- **Files:** `.ccanvil/scripts/docs-check.sh`.
- **Verify:** Test #1 passes; full suite green.

### Step 3: AC-2 — session-stasis commit at HEAD
- **Test:** Case #2 seeds two commits: HEAD = `docs: stasis …`, HEAD~1 = `feat(bts-X): … (#54)`. Assert AUTO-CLOSE still emitted.
- **Implement:** In the recovery block, if the HEAD subject starts with `^docs: stasis `, re-query with `git log -1 --skip=1 --format=%s` and re-match regex.
- **Files:** `.ccanvil/scripts/docs-check.sh`, `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #2 passes; case #1 still passes.

### Step 4: AC-3 — no `(#N)` suffix in last commit
- **Test:** Case #3 seeds HEAD = `direct commit to main` (no PR suffix). Assert stderr contains `WARN: land on main — could not recover PR number`; stdout contains NO `AUTO-CLOSE:` substring; exit code 0.
- **Implement:** Already handled in step 2's regex miss. Confirm `WARN:` message text matches AC-3.
- **Files:** `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #3 passes.

### Step 5: AC-4 — gh PR lookup fails (offline / 404)
- **Test:** Case #4 stubs `gh` to exit 1. Assert stderr contains `WARN: land on main — could not recover landed branch via gh`; no AUTO-CLOSE marker; exit 0.
- **Implement:** Already covered in step 2's `if ! gh …` branch. Confirm message text matches AC-4.
- **Files:** `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #4 passes.

### Step 6: AC-8 — gh binary missing
- **Test:** Case #5 overrides PATH to exclude gh entirely. Assert stderr contains `WARN: land on main — gh unavailable`; no AUTO-CLOSE marker; exit 0.
- **Implement:** Already covered in step 2's `command -v gh` branch. Confirm message text matches AC-8.
- **Files:** `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #5 passes.

### Step 7: AC-5 — recovered branch not `claude/<type>/<slug>`
- **Test:** Case #6 stubs `gh` to return a non-claude branch (e.g., `main-rebase-branch`). Assert stdout contains `auto-close: no feature-id detected` (from `cmd_auto_close_emit`'s existing behavior); no AUTO-CLOSE marker; exit 0.
- **Implement:** No new code — delegation to `cmd_auto_close_emit` already handles this (BTS-119 behavior).
- **Files:** `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #6 passes; confirms existing decision tree still fires correctly when reached via the new path.

### Step 8: AC-6 — recovered branch maps to local-provider spec
- **Test:** Case #7 stubs `gh` to return `claude/feat/local-idea-999`; seed `docs/specs/local-idea-999.md` with `Work: local:idea-999`. Assert stdout contains `auto-close: local provider — skipping`; no AUTO-CLOSE marker; exit 0.
- **Implement:** No new code — `cmd_auto_close_emit` handles this.
- **Files:** `hub/tests/land-post-merge-recovery.bats`.
- **Verify:** Case #7 passes; existing provider dispatch unchanged.

### Step 9: AC-7 — on-branch path unchanged (regression gate)
- **Test:** Run `bash .ccanvil/scripts/bats-report.sh --parallel hub/tests/auto-close-linear-on-merge.bats hub/tests/lifecycle-gate-audit.bats` — all existing cases green.
- **Implement:** N/A — all additive code is inside the `branch == main` block; the feature-branch path at line 1326+ is untouched.
- **Files:** none (verification only).
- **Verify:** Existing tests pass; no regressions in BTS-119's test surface.

### Step 10: Documentation — command-reference.md
- **Test:** Case #8 greps `.ccanvil/guide/command-reference.md` for `"land on main"` and `"post-merge"` mentions.
- **Implement:** Update the `land` command row's note to explicitly say: "When invoked on main after `gh pr merge --delete-branch`, recovers the landed branch from the last squash-merge's `(#<PR>)` suffix via `gh pr view` and emits the same `AUTO-CLOSE:` marker."
- **Files:** `.ccanvil/guide/command-reference.md`.
- **Verify:** Case #8 passes; `legacy-refs-scan` still clean.

### Step 11: Full suite + /review
- **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel` — full suite green (expected 930 + 8 = 938).
- **Implement:** Run `/review` agent + `security-audit.sh --files-only`. Address any WARN-level findings before /pr.
- **Files:** none.
- **Verify:** Full suite passes; no DANGER / secrets.

## Risks

- **gh PATH stub fragility** — if other bats tests don't cleanly reset PATH, my shim could leak into their invocations. Mitigation: set PATH inside each `@test` block, not `setup()`, so isolation is per-test. Confirm with `--parallel` (bats `--jobs`) where test ordering is nondeterministic.
- **HEAD~1 edge case when only one commit exists on main** — `git log --skip=1` on a fresh repo returns empty. Handled: the regex miss on empty subject falls through to the "no PR suffix" WARN.
- **AC-10 dogfood-close validation is post-merge** — cannot be confirmed until PR #54 merges and the new code runs on its own land. If auto-close fails on self-merge, I'll need to manually invoke `auto-close-emit BTS-138` and file a follow-up ticket on the fix.
- **Sync-check drift mid-implementation** — if someone else pushes to main while I'm on this branch, `/pr` will trip BTS-122's pr-guard. Acceptable — that's the gate working correctly. Resolve via rebase if it happens.

## Definition of Done

- [ ] All 10 ACs pass (AC-10 validates at PR-merge time)
- [ ] Full bats suite green via `bats-report.sh --parallel`
- [ ] `.ccanvil/guide/command-reference.md` updated
- [ ] `/review` clean
- [ ] `security-audit.sh --files-only` PASS
- [ ] PR #54 merged and AUTO-CLOSE fires on its own `/land` without manual `auto-close-emit`

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
