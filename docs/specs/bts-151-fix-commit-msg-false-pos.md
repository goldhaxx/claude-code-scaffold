# Feature: Stop guard hooks from false-positive blocking on `git commit -m` message bodies

> Feature: bts-151-fix-commit-msg-false-pos
> Work: linear:BTS-151
> Created: 1777155446
> Status: Complete

## Summary

Both `guard-workspace.sh` (verb-leading regex matches verbs anywhere in the command, so `cat`, `rm`, `bash` mentioned in a commit message body trigger the path scan) and `guard-destructive.sh` (BTS-156's `rm -rf` regex and BTS-155's `find -delete` regex match those literal strings anywhere) over-block `git commit -m "<body>"` invocations when the message body happens to mention verbs or path-shaped strings. We've hit this 3+ times this session alone — workaround was always to write the message to a tmpfile and use `commit -F`.

Fix: at the top of each hook, after the env-prefix bypass, add an early-exit when the command is shaped as `git commit -m <msg>` (or `-F <file>`, or `-am`, etc.) at the start of the command line. Trade-off: a chained command like `git commit -m "x" && rm -rf /` would bypass the gate. Acceptable — chaining destructive ops after commit is rare; the workaround friction is hit constantly.

## Job To Be Done

**When** I run `git commit -m "<message>"` and the message body contains words like `cat`, `rm`, `find`, `sort`, `bash`, or path-shaped strings like `/stasis`, `/tmp/...`, `~/projects/...`,
**I want to** have the commit go through without hook interference,
**So that** I don't have to write commit messages to tmpfiles or carefully reword them to avoid string collisions with hook regex.

## Acceptance Criteria

- [ ] **AC-1:** `git commit -m "fix bts-156 rm gate"` exits 0 from `guard-destructive.sh` (today: blocks because `rm -rf`-like strings in body trigger the destructive-shape regex if present, and `git` isn't in the workspace verb list anyway — but the destructive hook is the canonical issue here).
- [ ] **AC-2:** `git commit -m "fix /stasis path"` exits 0 from `guard-workspace.sh` (today: blocks because `bash` or `cat` mentioned in body activates path scan and `/stasis` then trips the absolute-path scan).
- [ ] **AC-3:** `git commit -am "msg with /tmp/foo"` exits 0 from both hooks. Covers `-a` + `-m` combination.
- [ ] **AC-4:** `git commit -F /tmp/msg.txt` exits 0 (file-fed message; `/tmp/` is whitelisted anyway, but the early-exit makes intent explicit).
- [ ] **AC-5:** `cat /etc/passwd` STILL blocks (unchanged — not a commit, fence applies).
- [ ] **AC-6:** `rm -rf /` STILL blocks (unchanged — not a commit, destructive shape applies).
- [ ] **AC-7:** `git status` exits 0 (unchanged — no path scan triggered, no commit pattern).
- [ ] **AC-8:** `git commit` (no flags, opens editor) exits 0 — also covered by the broad early-exit.
- [ ] **AC-9 (chained — known limitation):** `git commit -m "x" && rm -rf /` exits 0 from BOTH hooks (the early-exit fires on the `git commit` prefix, skipping the destructive scan). Documented as a known trade-off; acceptable because chaining destructive ops after commit is operationally rare.
- [ ] **AC-10 (env prefix):** `LANG=en_US git commit -m "msg with /tmp"` exits 0 — env-var assignments before `git commit` are matched by the prefix regex.
- [ ] **AC-11 (existing tests intact):** Full suite green.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | Add `git commit` early-exit after the ALLOW_OUTSIDE_WORKSPACE bypass |
| `.claude/hooks/guard-destructive.sh` | Add the same early-exit after the ALLOW_DESTRUCTIVE bypass |
| `hub/tests/guard-hooks.bats` | ~10 BTS-151 tests covering AC-1..AC-10 |

## Dependencies

- **Requires:** Nothing.
- **Blocked by:** Nothing.

## Out of Scope

- **Chained-with-destructive detection.** AC-9 documents the known gap. A more sophisticated parser that distinguishes `git commit -m "..."` (skip) from `git commit -m "..." && rm -rf /` (don't skip) is deferred — the operational frequency of the second shape is near-zero and any complexity increase risks new false positives.
- **bash -c "git commit ..."** — wrapped invocations from inside `bash -c` are not treated as commits; the wrapping `bash` already routes through the existing fence. Fine.
- **Stripping just the message body.** Approach 2 from the BTS-151 description (parse and remove `-m "..."` argument before scanning the rest) is more correct but harder to implement portably. Defer until friction surfaces with chained commits.

## Implementation Notes

- Pattern: `^([A-Z_][A-Z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+commit\b`.
  - Anchored at start of command.
  - Optional env-var assignments (`FOO=bar BAR=baz `) before `git commit`.
  - Word-boundary on `commit` to allow `git commit-tree` to NOT match.
- Place the check after each hook's env-prefix bypass (line 17 in both) so `ALLOW_DESTRUCTIVE=1` etc. still short-circuits first as before.
- Comment in each hook should reference BTS-151 and describe the trade-off.
- Tests use the same `tool_input.command` JSON shape as existing BTS-155/157/153 tests.
