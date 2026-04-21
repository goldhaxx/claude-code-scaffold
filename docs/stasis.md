# Stasis

> Feature: session-2026-04-22-stasis-recall-ship
> Last updated: 1776809739
> Plan hash: n/a (multi-feature session — stasis-recall shipped, init-mature-project spec drafted)
> Session objective: Ship BTS-75 (stasis/recall rename) end-to-end including downstream propagation; dogfood `/stasis` on the same session that created it.

## Accomplished

- **Triaged 3 untriaged ideas from prior session.** `2609` (checkpoint evolution) → promoted, became BTS-75. `3bad` (bats-suite speedup) → promoted, became BTS-76. `27b5` (spec-lifecycle-directories) → merged into BTS-22.
- **Shipped BTS-75 / PR #39 (`b56e781`)** — full rename of `checkpoint`/`catchup` → `stasis`/`recall`. 14 commits on `claude/feat/stasis-recall`, 16-step plan, 37 of 38 AC satisfied, 601/601 tests green through every step. Committed: template rename, docs-check.sh internals, operations.sh ops, CI workflow + manifest.lock cleanup, command/skill file rename, new `legacy-refs-scan` subcommand, ccanvil-sync.sh migration + broadcast hook, `/recall` skill, `/stasis` skill, rules, guide/README/hub/meta sweep, AC-29 grep guard with allowlist.
- **PR #39 squash-merged into main.** Local main reset cleanly; `6081f9d` captures the ideas.md drift.
- **All 7 downstream nodes fully propagated.** Broadcast + per-node `pull-apply accept-new`/`delete` handled structural changes (new `/stasis` + `/recall` skills, deleted `checkpoint.md` template + `catchup.md` command). `migrate-stasis-artifact` hook ran on unifi-toolbox successfully (first real-world use of the migration).
- **Linear BTS-75 marked Done**, title updated to "Stasis & Recall (full rename)", PR #39 linked.
- **Captured idea `5784`** about Claude's habit of running the bats suite twice back-to-back — root-caused to output-capture pattern, proposed wrapper fix.
- **Exposed mature-project gap in `/ccanvil-init`** (via docint). Wrote `docs/specs/init-mature-project.md` — 26 AC across 8 groups (mode detection, mode-aware defaults, CLAUDE.md delimiter insertion, conditional git lifecycle, skip-if-exists, idempotency, report-first flow, bats coverage, docs).
- **Patched `/stasis` skill's pre-flight criterion in-session.** First dogfood run halted on `no-active-spec` (a benign between-features state). Patched `.claude/skills/stasis/SKILL.md` to distinguish benign vs corruption states before re-running.

## Current State

- **Branch:** `main` (at `6081f9d`, in sync with `origin/main` at time of stasis)
- **Tests:** 601/601 bats passing at PR #39 HEAD; no test runs since (only doc writing + skill patch)
- **Uncommitted changes:** 
  - Modified: `.claude/skills/stasis/SKILL.md` (in-session patch — halt criterion)
  - New: `docs/specs/init-mature-project.md`
  - New: `docs/stasis.md` (this file)
- **Build status:** clean; no CI failures

## Blocked On

- **Docint `/ccanvil-init` is paused** awaiting the mature-project fix shipping. User intentionally cancelled the init prompt; no action needed until after init-mature-project lands.

## Next Steps

1. **Activate `init-mature-project`**: `bash .ccanvil/scripts/docs-check.sh activate init-mature-project`, then `/plan` → TDD cycles → `/pr`. 26 AC, ~10-12 TDD steps, single branch.
2. **Ship the stasis-skill halt-criterion patch** — it's currently uncommitted. Options: (a) fold into `init-mature-project` PR as a drive-by fix, (b) ship as its own micro-PR, (c) commit directly to main with `ALLOW_MAIN=1` (cleanest given it's a ~4-line skill doc change).
3. **Re-broadcast after init-mature-project merges** so downstream nodes get the updated `/ccanvil-init` skill and the `retrofit-check` subcommand.
4. **Triage idea `5784` (bats double-run pattern)** next session — aligns with BTS-76 (bats speedup) and could merge into that ticket.

## Context Notes

- **The mature-project gap in `/ccanvil-init` is real and recurring.** Every time a user tries to retrofit ccanvil onto an established project they hit one of: `git init` re-running, CLAUDE.md clobbered, pre-push hook overwritten, `docs/spec.md` destroyed. The spec I wrote addresses all five paths (fresh / source-no-git / mature-repo / partial-ccanvil / already-initialized).
- **AC-34 of stasis-recall was accepted as-is.** The "node has new artifact but hub content still references old" scenario is detected via `legacy-refs-scan` invoked by `/stasis` (AC-37 coverage) rather than by a dedicated warning from ccanvil-sync.sh. Same coverage, less sync noise. Future sessions: treat this as settled — don't re-litigate.
- **A direct-to-main commit happened this session** (`6081f9d` — idea capture mid-merge). Justified because the idea was captured after the stash-push, couldn't be part of the squash-merge PR, and didn't warrant its own PR. `ALLOW_MAIN=1` is the documented escape hatch for these boundary writes. Not a pattern to repeat casually — but a legitimate exception for session-boundary artifacts.
- **`/stasis` pre-flight halt criterion had a bug.** Original wording: "any non-aligned state → STOP" incorrectly grouped `no-active-spec` (benign between-features) with corruption states (`stale-plan`, `mismatched`, `unlinked`). Fixed in-session. Future enhancement: extend the skill to also classify which validate states are recoverable vs not.
- **Downstream broadcast took two passes to settle.** Pass 1 (broadcast auto-updates + migration hook): 6/7 nodes synced ideas.md, unifi skipped on dirty tree. Pass 2 (after user cleaned unifi): all 7 synced. Pass 3 (explicit per-node pull-apply): structural changes (new skills, deleted legacy files) accepted. This is expected behavior for `new`/`removed` actions — they require explicit confirmation per file, broadcast doesn't auto-accept. Worth documenting.
- **The session ran in `max` effort mode from the /effort command.** Model pushed back on the user's initial "minimal scope" proposal for init-mature-project — this was correct. Minimal fix would have shipped a half-solution requiring follow-up.

## Determinism Review

- **operations_reviewed:** ~42 (triage ceremonies, 14 TDD cycles for stasis-recall, 7-node broadcast + per-node pull-apply loop, spec writing, skill dogfood + patch)
- **candidates_found:** 5
- **`bats` suite double-run pattern**: Claude habitually ran `bats hub/tests/ | grep '^not ok'` then `bats hub/tests/ | tail -2` as separate commands, paying ~2min cost twice. Should be a single `bats hub/tests/ 2>&1 | tee /tmp/bats.out | grep -E '^not ok|[0-9]+\\.\\.[0-9]+'` pattern, or a wrapper script `bats-run.sh` that emits `{failed, passing_count}` JSON. Captured as idea `5784`. Impact: **high** — recurs every TDD cycle.
- **`legacy-refs-scan` with no allowlist awareness**: produced 157 raw matches during /stasis invocation, most of them already-allowlisted (hub/specs archives, the scanner implementation itself, this branch's live feature docs). `/stasis` can't use the output without post-filtering. Should gain `--respect-allowlist <path>` flag that reads `hub/tests/legacy-refs-allowlist.txt` and skips matches covered by it, so Cross-Session Patterns sees only real drift. Impact: **medium**.
- **`permissions-audit.sh check` output shape**: the `jq -c` wrapping in /stasis failed — script output isn't consistent JSON in all paths. Either the script should always emit JSON, or /stasis should `--json` flag it. Impact: **low** (human-readable output is still usable).
- **`context-budget.sh check` JSON shape**: returned `{total_tokens: null, budget_pct: null, status: null}` — the script emits text by default and JSON only with `--json` (or something equivalent). /stasis invoked the wrong variant. Fix: /stasis should call `context-budget.sh check --json` OR the script should default to JSON when stdout isn't a TTY. Impact: **low**.
- **`audit-session` reports `line: 0`** for every match instead of the real source line number. Makes findings harder to act on. Impact: **medium** (findings are still classifiable by file + pattern, but precise line references would matter when the file grows).

## Cross-Session Patterns

- **First stasis — no prior state to compare.** `git show HEAD~1:docs/stasis.md` failed (path removed in lifecycle cleanup of PR #39).
- **`legacy-refs-scan`** returned 157 matches. All matches on inspection are covered by `hub/tests/legacy-refs-allowlist.txt` (scanner implementation, hub/research archives, hub/specs archives, this branch's in-progress feature docs). **No real drift.** Next `/stasis` should be compared against this baseline.
- **Recurring friction pattern across multiple sessions:** git flow missteps on session-boundary writes (the 2026-04-21 session fixed it at the script level via PR #38; this session still had one `ALLOW_MAIN=1` direct-to-main commit for idea capture; still legitimate but the pattern deserves watching).

## Security Review

**PASS.** No new code in this session touched auth, secrets, or external API surface. Changes were:
- Documentation rewrites (rules, guide, README, hub/meta)
- Skill files (`/stasis`, `/recall`) — read-only from a secrets perspective
- Shell scripts (`docs-check.sh legacy-refs-scan`, `ccanvil-sync.sh migrate-stasis-artifact`) — no network, no credentials, no env-var exfil paths
- Template filename rename
- No `.env`, token, or credential file touched; no URL changes to external services; no MCP config changes.

## Memory Candidates

- **Feedback (new):** "Do the work once to get it right the first time, no need to revisit." Applied when evaluating scope for `init-mature-project`. **Why:** repeated half-measures across this session's surface area would have compounded maintenance debt. Consistent with the stasis-recall comprehensive-rename decision from the prior session. **How to apply:** when a feature request has a small "surface bug" fix and a larger "first-principles" fix, default to the first-principles path unless the user explicitly asks for the minimal patch.
- **Project fact:** ccanvil's `/ccanvil-init` historically assumed greenfield; mature-project retrofit is a first-class use case now being specced (init-mature-project). Past assumptions that "if it's not registered in the hub registry, just run /init" are wrong — existing git history and custom CLAUDE.md rules need preserving.
- **Pattern validated:** direct-to-main `ALLOW_MAIN=1` commits for session-boundary writes (idea captures between squash-merge and re-sync) are acceptable exceptions to the "never commit to local main" invariant. Keep it rare; keep it one-liners.
- **Reference:** Linear BTS-75 (Stasis & Recall) is Done. BTS-76 (bats-suite speedup) and BTS-72 (/merge for local-only repos) are the remaining promoted-but-unshipped items in the ccanvil backlog.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
