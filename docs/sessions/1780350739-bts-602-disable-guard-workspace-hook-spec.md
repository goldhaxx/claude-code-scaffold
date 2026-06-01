# Feature: Disable [guard-workspace.sh](<http://guard-workspace.sh>) workspace-fence hook

> Feature: bts-602-disable-guard-workspace-hook
> Work: linear:BTS-602
> Created: 1780341642
> Subject: Disable [guard-workspace.sh](<http://guard-workspace.sh>) workspace-fence hook
> Status: In Progress

## Summary

Remove `.claude/hooks/guard-workspace.sh` and all infrastructure that maintains it. The PreToolUse Bash hook blocks file-mutation verbs (`rm`, `cp`, `mv`, `chmod`, `chown`, `bash`, `find`, `sort`, `cat`) when any absolute or `~/`-prefixed path argument falls outside `$HOME/projects/`. Every recorded fire has misclassified normal work and forced an `ALLOW_OUTSIDE_WORKSPACE=1` retry — pure friction, no security uplift in this single-user dev environment. The hook already carries seven false-positive carve-outs (BTS-151/153/157/169/173/210/234) and four dedicated bats files maintaining them; the carve-out tail itself is the evidence the design fights normal usage. Structural protection from `guard-destructive.sh` (catastrophic chmod modes, destructive git verbs, clean-force) is retained.

## Job To Be Done

**When** Claude or the operator runs a routine file-mutation command that incidentally contains a path-shaped token,
**I want to** have the command run without `BLOCKED` output or `ALLOW_OUTSIDE_WORKSPACE=1` retry,
**So that** ordinary lifecycle work proceeds without false-positive friction and the carve-out maintenance burden disappears.

## Acceptance Criteria

- [ ] **AC-1:** `.claude/hooks/guard-workspace.sh` does not exist after the change.
- [ ] **AC-2:** `.claude/settings.json` contains no entry whose `command` references `guard-workspace.sh` — the PreToolUse Bash hook block currently at line 174 is removed.
- [ ] **AC-3:** The four dedicated test files are deleted: `hub/tests/guard-workspace-slashword-exemption.bats`, `guard-workspace-apostrophe-tolerance.bats`, `guard-workspace-jq-exemption.bats`, `guard-workspace-prose-tolerance.bats` (54 tests total).
- [ ] **AC-4:** `hub/tests/guard-hooks.bats` retains coverage for `guard-force-push.sh` and `guard-destructive.sh` but removes every test case that sources or exercises `guard-workspace.sh`. `grep -c guard-workspace hub/tests/guard-hooks.bats` returns 0; the `WORKSPACE_HOOK` shared-setup variable is also removed.
- [ ] **AC-5:** `.ccanvil/manifest-allowlist.txt` no longer contains `.claude/hooks/guard-workspace.sh`, and its line count decreases by exactly 1 versus the pre-change file. `bash .ccanvil/scripts/module-manifest.sh validate --json` returns `drift_count: 0` with `coverage.covered == coverage.total`, and `coverage.total` is exactly 1 less than the pre-change `coverage.total` (relative delta, not absolute count — independent of any other manifest-touching ships landing in the interim).
- [ ] **AC-6:** `.ccanvil/scripts/ccanvil-sync.sh` references to the workspace-fence (the `workspace-fence-bypass-required` contract line, the launchd-install comment about cp + launchctl) are removed or rewritten — no stale references to a non-existent hook remain.
- [ ] **AC-7:** `.ccanvil/guide/hooks.md` no longer lists `guard-workspace.sh` in its hook table (line 93 row removed); `.ccanvil/guide/configuration.md` line 159 prose updated so the workspace-fence is no longer cited as a current example.
- [ ] **AC-8:** `.claude/permissions-log.json` rationales that cited `guard-workspace.sh` as the structural gate (entries for `chmod`, `chown`, `cp`, `env`, `find`, `mv`, `rm`, `sort`, `bash`, `cat`, plus the `ALLOW_DESTRUCTIVE=1`/`ALLOW_MAIN=1` env-prefix entries) are re-derived to remove the false claim of hook-based path-fencing. New rationale shape: pre-allowed; operator vigilance + git-as-recovery-substrate are the boundary, not a workspace-fence hook.
- [ ] **AC-9:** `.claude/hooks/guard-destructive.sh` comments that reference `guard-workspace` (currently lines 28 and 145) are updated or removed — no anchors point to a deleted hook.
- [ ] **AC-10:** Full bats suite passes: `bash .ccanvil/scripts/bats-report.sh --parallel` exits 0. Total test-count delta matches the removed cases (AC-3 + AC-4); no unrelated regressions.
- [ ] **AC-11:** Edge: a Bash command that previously tripped the fence (e.g., `cat /etc/hosts`, `cp ~/Downloads/foo.txt .ccanvil/`) completes without `BLOCKED` output and without requiring an `ALLOW_OUTSIDE_WORKSPACE=1` prefix. Verified by running one such command after the change.
- [ ] **AC-12:** Downstream nodes inherit the removal via the registry broadcast — verified by running `bash .ccanvil/scripts/ccanvil-sync.sh broadcast --dry-run` from the hub post-merge and confirming the output lists `.claude/hooks/guard-workspace.sh` as a deletion for at least one registered downstream node. (`stack-list` is NOT a valid alternative — it enumerates stack profiles, not deletion candidates.)

## Affected Files

| File | Change |
| -- | -- |
| `.claude/hooks/guard-workspace.sh` | Deleted |
| `.claude/settings.json` | Modified — drop PreToolUse Bash block at line 174 |
| `hub/tests/guard-workspace-slashword-exemption.bats` | Deleted |
| `hub/tests/guard-workspace-apostrophe-tolerance.bats` | Deleted |
| `hub/tests/guard-workspace-jq-exemption.bats` | Deleted |
| `hub/tests/guard-workspace-prose-tolerance.bats` | Deleted |
| `hub/tests/guard-hooks.bats` | Modified — drop workspace-fence test cases (BTS-146/147/151/153/157) and the `WORKSPACE_HOOK` variable |
| `.ccanvil/manifest-allowlist.txt` | Modified — drop the `.claude/hooks/guard-workspace.sh` line |
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — clean up workspace-fence references near lines 4692 + 4702 |
| `.ccanvil/guide/hooks.md` | Modified — drop hook-table row |
| `.ccanvil/guide/configuration.md` | Modified — line 159 prose update |
| `.claude/permissions-log.json` | Modified — re-derive \~13 rationales citing guard-workspace as structural gate |
| `.claude/hooks/guard-destructive.sh` | Modified — drop comment references at lines 28, 145 |

## Dependencies

* **Requires:** none. Self-contained hub-side change.
* **Blocked by:** none.

## Out of Scope

* Removing `guard-destructive.sh`, `guard-force-push.sh`, or `protect-main.sh` — those gate genuinely catastrophic operations and stay in place.
* Designing a successor read-fence for exfiltration risk (BTS-150 / BTS-153 problem space). If a successor is warranted, scope it in a separate spec.
* Removing the `ALLOW_OUTSIDE_WORKSPACE=1` env-prefix permission from `.claude/settings.json` — becomes a no-op token but harmless to retain for in-flight scripts; deferred to a follow-up sweep.
* BTS-603 (settings.json consolidation) — runs separately; this change may incidentally reduce settings.json size, but that is not its acceptance criterion.
* Downstream node propagation beyond verifying one pull dry-run; each node owns its own `ccanvil-pull` cadence.

## Implementation Notes

* **Carve-out anchors retire with the hook.** The BTS-151/153/157/169/173/210/234 carve-outs disappear. The `@anchor: BTS-157 (sort -o gate — handled in guard-workspace)` comment in `guard-destructive.sh:28` becomes false; either flip it to acknowledge `sort -o` is an unmitigated gap, or capture a fresh BTS for that gap and link.
* **Permissions-log re-derivation is a bulk pass.** Wording should be consistent across all affected entries. The new shape: "Pre-allowed; the operator/operator-vigilance + git-as-recovery-substrate are the boundary, not a workspace-fence hook. Catastrophic forms remain gated by [guard-destructive.sh](<http://guard-destructive.sh>)."
* **Manifest drift convergence is one cycle.** Removing the hook + allowlist entry should converge in a single `module-manifest.sh validate` pass — no inline marker churn because the markers leave with the file.
* **Test-count delta to verify in AC-10:** dedicated files contribute 54 tests; the `guard-hooks.bats` workspace-fence subset is \~52 by current grep, exact count to be confirmed during implementation. Expected total drop: \~106 (suite 2572 → \~2466).
* **Rollback contingency.** The hook + tests stay in git history; a future re-enable restores from the pre-removal commit. No data migration involved.
* **TDD posture.** This is a deletion spec; tests are removed, not added. The TDD cycle for each AC is: confirm the test-or-reference exists pre-change → delete → confirm absence + suite green. The `/plan` step will decompose this into per-file TDD-shaped steps.
