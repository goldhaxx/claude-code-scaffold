# Implementation Plan: Disable [guard-workspace.sh](<http://guard-workspace.sh>) workspace-fence hook

> Feature: bts-602-disable-guard-workspace-hook
> Work: linear:BTS-602
> Created: 1780345428
> Spec hash: 981f53d8
> Based on: docs/spec.md

## Objective

Remove `.claude/hooks/guard-workspace.sh`, the four dedicated bats files maintaining its carve-outs, the in-`guard-hooks.bats` test cases that exercise it, and every stale reference in settings + manifest allowlist + [ccanvil-sync.sh](<http://ccanvil-sync.sh>) + guide docs + permissions-log rationales + [guard-destructive.sh](<http://guard-destructive.sh>) comments. End state: hook gone, suite still green, manifest delta exactly −1, registry broadcast lists the deletion downstream.

## Sequence

Each step is one red-green-refactor cycle. For a deletion spec the cycle is: confirm the pre-change state (the thing exists/asserts/passes) → execute the change → confirm the post-change state + targeted test green → commit.

### Step 0: Baseline measurements (not a cycle — preflight)

* Capture pre-change values to verify against later:
  * `cat .ccanvil/manifest-allowlist.txt | wc -l` → `$ALLOWLIST_PRE`
  * `bash .ccanvil/scripts/module-manifest.sh validate --json | jq '.coverage.total'` → `$TOTAL_PRE`
  * `bash .ccanvil/scripts/bats-report.sh --parallel | tail` → record passing-test count `$TESTS_PRE`
  * `grep -c guard-workspace hub/tests/guard-hooks.bats` → `$REFS_PRE`
* **Files:** none modified. Record values in commit-message bodies as evidence for AC-5 / AC-10.

### Step 1: Delete the four dedicated bats files (AC-3)

* **Test:** confirm all four files exist; count `^@test ` lines per file (expect 13+14+10+17=54).
* **Implement:** `rm hub/tests/guard-workspace-{slashword-exemption,apostrophe-tolerance,jq-exemption,prose-tolerance}.bats`.
* **Files:** the 4 deleted .bats files.
* **Verify:** files absent; `bash hub/tests/guard-hooks.bats` still passes (the dedicated tests are orthogonal — guard-hooks.bats does not source them).
* **Commit:** `test(bts-602): drop dedicated guard-workspace carve-out bats files (-54 tests)`.

### Step 2: Strip workspace-fence cases from guard-hooks.bats (AC-4)

* **Test:** `grep -c guard-workspace hub/tests/guard-hooks.bats` returns N>0 pre-change.
* **Implement:** edit `hub/tests/guard-hooks.bats` — remove the `WORKSPACE_HOOK` setup variable; remove every `@test` block that sources or exercises `WORKSPACE_HOOK`/`guard-workspace.sh`; keep all `guard-force-push.sh` + `guard-destructive.sh` cases intact. Cases by anchor: BTS-146 workspace-fence; BTS-147 bare-slash false-positive; BTS-151 git-commit carve-out (AC-2/AC-4); BTS-153 cat read fence; BTS-157 sort -o.
* **Files:** `hub/tests/guard-hooks.bats`.
* **Verify:** `grep -c guard-workspace hub/tests/guard-hooks.bats` returns 0; targeted run `bats hub/tests/guard-hooks.bats` passes with the residual cases (force-push + destructive).
* **Commit:** `test(bts-602): strip workspace-fence cases from guard-hooks.bats`.

### Step 3: Remove the hook + its settings wiring (AC-1, AC-2)

* **Test:** `[ -f .claude/hooks/guard-workspace.sh ]` true; `grep -c guard-workspace .claude/settings.json` returns 1.
* **Implement:** `rm .claude/hooks/guard-workspace.sh`; edit `.claude/settings.json` to delete the PreToolUse Bash hook block whose `command` references `guard-workspace.sh` (single matcher today at line 174).
* **Files:** `.claude/hooks/guard-workspace.sh`, `.claude/settings.json`.
* **Verify:** hook file absent; `grep -c guard-workspace .claude/settings.json` returns 0; `jq . .claude/settings.json` parses cleanly (no malformed JSON from the edit).
* **Commit:** `feat(bts-602): remove guard-workspace.sh + settings wiring`.

### Step 4: Drop the manifest allowlist entry (AC-5)

* **Test:** `grep -c '.claude/hooks/guard-workspace.sh' .ccanvil/manifest-allowlist.txt` returns 1.
* **Implement:** remove the `.claude/hooks/guard-workspace.sh` line (currently line 219) from the allowlist.
* **Files:** `.ccanvil/manifest-allowlist.txt`.
* **Verify:** line absent; `cat .ccanvil/manifest-allowlist.txt | wc -l` is exactly `$ALLOWLIST_PRE - 1`; `bash .ccanvil/scripts/module-manifest.sh validate --json | jq '{drift_count: (.drift|length), total: .coverage.total, covered: .coverage.covered}'` returns `drift_count: 0`, `covered == total`, and `total == $TOTAL_PRE - 1`.
* **Commit:** `chore(bts-602): drop manifest-allowlist entry for guard-workspace.sh`.

### Step 5: Clean up [ccanvil-sync.sh](<http://ccanvil-sync.sh>) workspace-fence references (AC-6)

* **Test:** `grep -n 'workspace-fence-bypass-required\|guard-workspace' .ccanvil/scripts/ccanvil-sync.sh` returns 2 lines (around 4692, 4702).
* **Implement:** edit `.ccanvil/scripts/ccanvil-sync.sh` — drop or rewrite the `# contract: workspace-fence-bypass-required` line and the launchd-install comment that explains the cp+launchctl bypass need. The bypass commentary is no longer load-bearing because the fence no longer exists.
* **Files:** `.ccanvil/scripts/ccanvil-sync.sh`.
* **Verify:** `grep 'workspace-fence-bypass-required\|guard-workspace' .ccanvil/scripts/ccanvil-sync.sh` returns nothing; `bash -n .ccanvil/scripts/ccanvil-sync.sh` parses cleanly (no syntax break).
* **Commit:** `refactor(bts-602): drop ccanvil-sync.sh workspace-fence references`.

### Step 6: Update guide docs (AC-7)

* **Test:** `grep -c guard-workspace .ccanvil/guide/hooks.md` returns ≥1; `grep -n 'workspace-fence\|guard-workspace' .ccanvil/guide/configuration.md` returns ≥1.
* **Implement:** delete the `guard-workspace.sh` hook-table row in `.ccanvil/guide/hooks.md` (\~line 93); update the line 159 prose in `.ccanvil/guide/configuration.md` so the workspace-fence is no longer cited as a current false-alert example (history reference acceptable: "previously the workspace-fence pattern…" is fine).
* **Files:** `.ccanvil/guide/hooks.md`, `.ccanvil/guide/configuration.md`.
* **Verify:** `grep guard-workspace .ccanvil/guide/hooks.md` empty; configuration.md prose no longer cites workspace-fence as a live example.
* **Commit:** `docs(bts-602): drop guard-workspace references from hooks.md + configuration.md`.

### Step 7: Update [guard-destructive.sh](<http://guard-destructive.sh>) anchor comments (AC-9)

* **Test:** `grep -n guard-workspace .claude/hooks/guard-destructive.sh` returns 2 lines (28, 145).
* **Implement:** drop or rewrite the BTS-157 `@anchor` (sort -o → "handled in guard-workspace") and the line-145 traversal comment. Choose: (a) flag the `sort -o` writer-flag gap as currently unmitigated with a TODO; (b) capture a separate BTS for the gap and link from the comment. Pick (a) for this ship; capture (b) as a follow-up idea via `/idea`.
* **Files:** `.claude/hooks/guard-destructive.sh`.
* **Verify:** `grep guard-workspace .claude/hooks/guard-destructive.sh` empty; targeted run `bats hub/tests/guard-hooks.bats` still passes (destructive cases unaffected).
* **Commit:** `refactor(bts-602): retire workspace-fence anchors from guard-destructive.sh`.

### Step 8: Re-derive permissions-log.json rationales (AC-8)

* **Test:** `jq '[.[] | select(.rationale | strings | contains("guard-workspace"))] | length' .claude/permissions-log.json` returns ≥13 (the chmod/chown/cp/env/find/mv/rm/sort/bash/cat + ALLOW_DESTRUCTIVE+ALLOW_MAIN+ALLOW_DESTRUCTIVE_rm entries).
* **Implement:** bulk-edit each rationale string to replace the false claim of hook-based path-fencing with the new shape: "Pre-allowed; operator vigilance + git-as-recovery-substrate are the boundary, not a workspace-fence hook. Catastrophic forms remain gated by [guard-destructive.sh](<http://guard-destructive.sh>)." Preserve the entry's `permission`, `source`, `status`, `matched_pattern`, `risk_accepted` fields untouched. Keep individual `risk` strings; they still describe the threat shape correctly.
* **Files:** `.claude/permissions-log.json`.
* **Verify:** `jq '[.[] | select(.rationale | strings | contains("guard-workspace"))] | length'` returns 0; `jq . .claude/permissions-log.json` parses cleanly; `bash .ccanvil/scripts/permissions-audit.sh check --json | jq '.danger'` still returns 0 (no entry slipped from REVIEWED to UNREVIEWED).
* **Commit:** `refactor(bts-602): re-derive permissions-log rationales for removed workspace-fence`.

### Step 9: Full bats suite gate (AC-10)

* **Test:** `bash .ccanvil/scripts/bats-report.sh --parallel` exits 0.
* **Implement:** none (verification only).
* **Files:** none.
* **Verify:** exit 0; passing-test count `$TESTS_POST == $TESTS_PRE - (54 + N)` where N is the guard-hooks.bats workspace-fence subset removed in Step 2; no unrelated regressions.
* **Commit:** no commit (verification gate).

### Step 10: Live edge-case fence-not-firing verification (AC-11)

* **Test:** none — this verifies the absence of the fence in a live run.
* **Implement:** run `cat /etc/hosts >/dev/null` directly via Bash (no `ALLOW_OUTSIDE_WORKSPACE=1` prefix). Pre-change this would have tripped `BLOCKED: path '/etc/hosts' is outside the workspace`. Post-change it should complete with exit 0.
* **Files:** none.
* **Verify:** command runs without `BLOCKED` output and without retry; exit 0.
* **Commit:** no commit (verification gate). Capture the result in the PR body's Test Plan.

### Step 11: Documentation pass + capture follow-up (preset-infra hygiene)

* **Test:** the hub-shared `.ccanvil/guide/hooks.md` + `.ccanvil/guide/configuration.md` cover the change (already addressed in Step 6); `.claude/rules/` has no orphan rule referencing the fence.
* **Implement:** `grep -rn 'guard-workspace\|workspace-fence' .claude/rules .ccanvil/guide CLAUDE.md 2>/dev/null` — fix any orphan references. Capture the `sort -o` unmitigated gap (from Step 7) as a `/idea` follow-up.
* **Files:** any orphan files surfaced; new Linear idea.
* **Verify:** no stale doc refs to guard-workspace remain; the follow-up ticket exists in Linear Backlog.
* **Commit:** if any docs were touched, `docs(bts-602): sweep orphan guard-workspace references`. Else no commit.

### Step 12: Pre-merge AC-12 verification dry-run

* **Test:** before `/pr`, run `bash .ccanvil/scripts/ccanvil-sync.sh broadcast --dry-run` and inspect for `.claude/hooks/guard-workspace.sh` listed as a deletion for ≥1 registered downstream node.
* **Implement:** none (verification only). The AC-12 spec wording says "post-merge" but running it pre-merge against the registered nodes proves the broadcast path will work; the post-merge run is the formal acceptance.
* **Files:** none.
* **Verify:** output contains the deletion entry for ≥1 node. If no nodes are registered or none track the file, document that in the PR body as a known limitation (the change is still correct; downstream propagation is just a no-op at this moment).
* **Commit:** no commit.

## Risks

* **Permissions-log re-derivation breaks JSON.** Mitigation: every edit followed by `jq . .claude/permissions-log.json`. Worst case: revert the file and reapply edits via `jq '.[].rationale |= …'` instead of hand-editing.
* **Targeted bats run misses a regression.** Mitigation: Step 9 is the load-bearing full-suite gate; never skip.
* **Hook-removal trips a live** `cat`**/**`cp` **command needed mid-implementation.** Mitigation: Step 3 (hook removal) deliberately precedes Steps 5–8 so downstream edits run without `ALLOW_OUTSIDE_WORKSPACE=1` prefixes.
* **Concurrent-edit guard fires on Linear during plan/PR/ship.** Mitigation: standard verify-then-`ALLOW_CONCURRENT_EDIT_OVERRIDE=1` protocol; already 8× this BTS-602 lifecycle, well-rehearsed.
* **AC-12 broadcast surface is registry-dependent.** If no registered node tracks the file or the registry is empty, AC-12 verification is a no-op; that's a limitation of the substrate, not a spec failure.

## Definition of Done

- [ ] All 12 acceptance criteria from spec pass
- [ ] All existing tests still pass (full bats suite green; test-count delta matches expected)
- [ ] `module-manifest.sh validate --json` returns drift_count: 0 with total exactly 1 less than pre-change
- [ ] `jq . .claude/permissions-log.json` parses cleanly
- [ ] `bash -n .ccanvil/scripts/ccanvil-sync.sh` parses cleanly
- [ ] No grep hits for `guard-workspace` in hub-tracked files (excluding archived spec, archived stasis, runtime artifacts like `.ccanvil/state/`)
- [ ] Live cat /etc/hosts (or equivalent) runs without BLOCKED output
- [ ] Broadcast dry-run lists the deletion (or known-limitation noted)
- [ ] Code reviewed (run /review)
