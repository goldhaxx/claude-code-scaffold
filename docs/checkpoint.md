# Checkpoint

> Feature: session-2026-04-21 (canonical-git-flow convergence)
> Last updated: 1776749883
> Plan hash: n/a (multi-feature session, three independent specs shipped)
> Session objective: Close out BTS-71/73/74 backlog, then first-principles redesign of ccanvil's git-flow interactions so local main never receives direct commits.

## Accomplished

- **BTS-73 shipped (PR #31, `cde4072`)** — `pull-plan` stack-origin classification. Files with `origin: stack:<id>` no longer flagged as removed-from-hub. Taxes `protect-db.sh` workaround reverted end-to-end.
- **BTS-71 shipped (PR #32, `97b4ead`)** — `docs-check.sh recommend` now returns `/compact to wrap session` (was `/clear and /catchup to resume`). Closes the last stale `/clear` reference missed by the `compact-over-clear` spec.
- **BTS-74 shipped in three PRs:** `#33 register-auto-commit` (a41eba1), `#34 take-hub-stack-reapply` (89444e6), `#35 relocate-subcommand` (09ff135). `ccanvil-sync.sh` now owns three previously-manual Claude operations.
- **Git-flow bug surfaced via observation.** Every merge this session required `git rebase --skip`. Root-cause analysis identified two cooperating bugs + one architectural miss.
- **PR #36 shipped (`5e6bd39`)** — `cmd_activate` allow-list expanded to include `docs/ideas.md`/`docs/roadmap.md`; `cmd_land` handles already-on-main by fast-forwarding to origin. Eliminates pre-activate commits and post-merge "Already on main" errors.
- **PR #37 shipped (`9ef9d83`)** — docs alignment for the new activate/land behavior.
- **PR #38 shipped (`7cfe103`)** — first-principles fix for the root cause. `.ccanvil/registry.json` is now gitignored machine-local state. `commit_hub_file` helper deleted. New `append_event` + `.ccanvil/events.log` audit trail. New `ccanvil-sync.sh events [--event T] [--node N] [--since EPOCH]` subcommand. 3 `commit_hub_file` call sites removed; 9 obsolete tests deleted from `clean-init-commits.bats`; 13 new tests in `registry-local-state.bats`. Net −129 lines.
- **Canonical GitHub flow now holds end-to-end.** Validated in-session: first post-PR-#38 broadcast ran clean — no hub commits, `git status` empty, `events.log` populated with 6 `broadcast_sync` entries.
- **Memory updated** (`project_git_flow_normalized.md`) to reflect the stronger invariant: broadcast no longer creates divergence.

## Current State

- **Branch:** main (at `7cfe103`, in sync with `origin/main`)
- **Tests:** 541/541 bats passing
- **Uncommitted changes:** none (tree clean)
- **Build status:** clean; all 6 downstream nodes broadcast-synced to `7cfe103`; events.log has 6 broadcast_sync entries

## Blocked On

- Nothing.

## Next Steps

1. **Triage open ideas** — 2 untriaged: spec-lifecycle-directories (move completed specs to a subdir) and bats-suite speedup.
2. **BTS-72 (`/merge` for local-only repos)** remains in backlog — last of this cycle's promoted ideas.
3. **Three-Layer Solution (dark code)** still on roadmap Horizon as `needs-research`.
4. **Optional second-order cleanup** — the `events` subcommand could gain a `--tail` flag or an `events --count-by-event` aggregation if audit querying gets heavy.

## Context Notes

- **One-time migration happened mid-session:** the rebase-skip that resolved the PR #38 divergence also wiped `.ccanvil/registry.json` from disk (not just the index). Re-registered all 6 nodes; first broadcast re-populated everything. Fresh clones on other machines will need the same one-time re-register. The PR body's upgrade notes mentioned this but understated the on-disk wipe.
- **Validated `land`'s divergence-refusal design:** after PR #38 merged, local had a stale `chore(registry)` broadcast commit (the last one ever, from before the fix). `land --force` correctly reported "Local has diverged from origin/main — resolve manually" instead of silently fast-forwarding. Manual `git pull --rebase` + `git rebase --skip` was the right move. Under the new flow, this exact scenario can no longer recur — so future "Local has diverged" messages should be treated as real signal, not ceremonial noise.
- **Node-side sync commits (`chore(sync): pull from hub @ <sha>`) still exist.** Those are correct: each downstream node is its own repo with its own PR flow. The "no commits to main outside PRs" principle applies to the hub; nodes have their own semantics.
- **Completed spec archives (`docs/specs/*.md`) still get status-flipped by activate/complete.** This produces small patches in every feature PR that re-modify the archive. Not currently problematic with the fixes in #36, but worth noting if we later revisit archive immutability.

## Determinism Review

- **operations_reviewed:** ~18 (three feature PRs with TDD cycles, git-flow analysis, registry redesign, memory updates, and end-to-end validation)
- **candidates_found:** 0
- **Notable non-findings:** most of this session's Claude work was exactly what transformers should do — semantic analysis (root-cause diagnosis, principle articulation, tradeoff evaluation) and cross-file code changes with test coverage. The few mechanical steps (bats tallies, grep-based verification of call sites) were already single commands. The "broadcast inline" divergence that I flagged as Claude-error in past sessions has been eliminated by PR #38, making the flow structurally deterministic rather than Claude-guarded.
- No candidates this session.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
