# Background Task Incident Reference

> Tier 2 reference (BTS-387). Excluded from Claude Code auto-load; read on-demand by agent or operator following the background-task-discipline rule's `anchors.evidence` pointer.

This content was extracted verbatim from `.claude/rules/background-task-discipline.md` during the BTS-387 atomization audit. The atom file retains the 3-rule directive layer; this reference holds the rationale, anti-pattern catalog, and BTS-383 origin incident.

## Why (the 3 anti-patterns that compound)

Three anti-patterns compound when background tasks aren't budgeted:

- **Premature wait-loop firing.** `until ! ps aux | grep "<command>" | grep -v grep > /dev/null; do sleep N; done` has a race against subprocess startup. The grep sometimes runs before the command has spawned its workers, fires immediately, and the loop exits successfully — the agent then re-launches the command. Result: stacked invocations.
- **Output buffering misread as hang.** Buffered tools' output files stay at 0 bytes for the full run. Indistinguishable from a hung process via `ls -la`. The agent assumes hang and starts another run.
- **Wait-loops are themselves background tasks.** Each `until ...; do sleep ...; done` queued as background work becomes a phantom in the harness UI that may persist past the watched-for condition (especially when the loop's exit-condition was already met before the loop spawned).

Cumulatively: a single feature session can accumulate dozens of background task IDs, oversubscribe CPU at peak, and produce hours of operator-idle time watching commands appear-to-hang.

## How to apply (expanded)

### Waiting on a long-running command
- **Foreground first.** Run the command in the foreground (no `run_in_background`). The harness blocks on it; when it completes (or times out into background), you get a task-completion notification automatically. No polling needed.
- **If you need to keep working while it runs:** use `run_in_background: true`. The harness will notify you when it completes. Do not write a separate wait-loop to monitor it — the notification IS the wait mechanism.

### When buffered output looks hung
- Look at the running PID with `ps aux | grep <command>`. If CPU is non-zero or process state is `R`/`S`, it's working — buffering is the cause of empty output. Wait.
- Do not start a second invocation "to compare" or "find failures faster." Parallel runs of the same long command compete for the same resources and slow every run.

### Cleaning up zombies
- Use `TaskStop <task-id>` to terminate a specific background task by ID.
- Use `pkill -9 -f "<pattern>"` only when TaskStop fails and the process is genuinely orphaned. Verify after with `ps aux | grep <pattern>` returns 0.

### Anti-pattern catalog

| Anti-pattern | Replace with |
|---|---|
| `<long-cmd> &; until ! ps aux \| grep <long-cmd>; do sleep 5; done` | `<long-cmd>` (foreground; let harness notify on completion) |
| `<long-cmd>; <long-cmd>; <long-cmd>` (parallel duplicates "to find failures") | One invocation. Block. Read result. |
| `until [[ -s <file> ]]; do sleep 2; done; cat <file>` | Foreground the producing command, OR use `run_in_background: true` and wait for the notification |
| Running a slow validator after every Edit | Run after a logical commit boundary (3-5 edits typically) |

## Anchored on (ccanvil hub)

**Origin incident — BTS-383 (2026-05-08).** A single feature session accumulated 50+ background task IDs across ~6 hours of work. At peak, 10+ shells were running simultaneously — 3 parallel `bats-report.sh --parallel` runs + 5+ wait-loops + multiple `module-manifest.sh validate` invocations — oversubscribing the operator's CPU and producing 1-2 hours of operator-idle time watching tests appear-to-hang. A 40-minute zombie `until [[ -s <file> ]]; do sleep 2; done` was still alive when the operator surfaced the problem.

**Hub-specific buffering surfaces:**
- `.ccanvil/scripts/bats-report.sh --parallel` fully buffers stdout until completion.
- `.ccanvil/scripts/module-manifest.sh validate` fully buffers stdout until completion.
- BTS-383 ships `--progress` flags on both substrates to surface streaming heartbeats; until then, foreground discipline is the workaround.

**Hub backlog anchors:**
- BTS-383 — substrate spec for the streaming/incremental fixes
- BTS-118 — `bats-report.sh` substrate origin

## Out of scope

- Eliminating buffering at the substrate level (each project's test runner / validator owns its own progress-streaming work).
- Harness-level limits on max concurrent background tasks (would require harness changes).

## Related

- Test execution discipline (the project's `tdd.md` rule, where applicable)
- Deterministic-first principle (`deterministic-first.md`) — parent rationale: minimize subprocess work
