# Implementation Plan: Lifecycle Gate Audit

> Feature: bts-122-lifecycle-gate-audit
> Work: linear:BTS-122
> Created: 1777047724
> Spec hash: 12a47f74
> Based on: docs/spec.md

## Objective

Harden `cmd_activate`'s sync guard (fetch-before-compare + local-behind detection + offline fallback + existing-branch check), add a matching `cmd_pr_guard` for `/pr` finalization, and lock the working-tree and `cmd_land` audit behaviors in bats tests so subsequent hardening ships inherit a complete regression baseline.

## Sequence

### Step 1: Extract `cmd_sync_check` helper + bats coverage (AC-1, 3, 9)
- **Test:** New `hub/tests/lifecycle-gate-audit.bats`. Assertions: exit 0 when synced (ahead=0, behind=0); exit 1 when ahead with list of hashes on stderr; exit 2 when behind with `git pull --ff-only` hint; exit 0 with `WARN: offline — skipping sync check` when remote unreachable; exit 0 no-op when `origin/main` ref absent. One scenario seeds a new remote commit post-clone so the fetch actually changes the comparison.
- **Implement:** `cmd_sync_check <repo-root> [--quiet]` in `docs-check.sh`. Runs `git fetch origin main` with `-c http.lowSpeedLimit=1 -c http.lowSpeedTime=5` timeout; degrades to `WARN:` on non-zero fetch exit. Emits `AHEAD: <hashes>` on stderr + exit 1, `BEHIND: <short-base>..origin/main` + exit 2, clean otherwise. Pure logic — no side effects beyond the fetch and stdout/stderr.
- **Files:** `.ccanvil/scripts/docs-check.sh` (new helper + dispatch entry `sync-check)`); `hub/tests/lifecycle-gate-audit.bats` (new).
- **Verify:** `bats hub/tests/lifecycle-gate-audit.bats` green.

### Step 2: Wire `cmd_sync_check` into `cmd_activate` + add `--force-sync` alias (AC-2, 8)
- **Test:** Extend `hub/tests/activate-push-guard.bats` with (a) seeded-behind test — fresh commit on bare remote, local fetches, activate halts with exit 1 and "behind" + "git pull --ff-only"; (b) `--force-sync` bypasses both ahead and behind; (c) `--force-local-ahead` still works as alias (AC-17/18 regression); (d) error-format shape: `^ERROR:` + blank line + bullet lines starting with `  ` (two spaces).
- **Implement:** Replace the inline `git rev-list origin/main..main` block with `cmd_sync_check "$repo_root"`. Branch on exit code: 0 proceed, 1 or 2 halt unless `force_local_ahead||force_sync`. Add `--force-sync` as a new arg that sets the same flag. Update error messages to AC-8 format.
- **Files:** `.ccanvil/scripts/docs-check.sh` (modify `cmd_activate` lines 750-797); `hub/tests/activate-push-guard.bats`.
- **Verify:** Both bats files green.

### Step 3: Add existing-branch guard to `cmd_activate` (AC-4)
- **Test:** New bats case — pre-create `claude/feat/bts-122-lifecycle-gate-audit` locally, run activate, assert exit 1 + error message containing the branch name + `git branch -D` + `git checkout`.
- **Implement:** Before `git -C "$repo_root" checkout -b "$branch_name"`, check `git -C "$repo_root" rev-parse --verify "$branch_name" >/dev/null 2>&1` — if the branch exists, halt with AC-8-shaped error.
- **Files:** `.ccanvil/scripts/docs-check.sh` (insert before line 866); `hub/tests/activate-push-guard.bats`.
- **Verify:** `bats hub/tests/activate-push-guard.bats` green.

### Step 4: Lock working-tree guard behavior (AC-6)
- **Test:** New bats case in `activate-push-guard.bats` — seed `README.md` uncommitted change in the repo, run activate, assert exit 1 + "uncommitted changes" message. Verify allowed paths (`docs/specs/*`, `docs/spec.md`, `docs/roadmap.md`) still pass through.
- **Implement:** No source change needed — the check exists at lines 830-852. Add a comment block documenting scope + link to BTS-122 spec. If bats test reveals a gap (e.g., nested paths), fix it.
- **Files:** `.ccanvil/scripts/docs-check.sh` (comment block only); `hub/tests/activate-push-guard.bats`.
- **Verify:** bats green.

### Step 5: Document `cmd_land` sync behavior + lock offline degradation (AC-7)
- **Test:** New bats case in `lifecycle-gate-audit.bats` — feature branch with a merged PR simulation, origin points at a non-existent bare path → run `docs-check.sh land --force`. Assert exit 0, `WARN:` line on stderr, local main NOT reset to anything (current sha preserved if no origin/main available).
- **Implement:** Add comment block above `cmd_land` documenting: "fetches origin non-fatally; if fetch fails, log WARN: and skip the reset." If current behavior differs (`git reset --hard` runs unconditionally), add the guard — inspect lines 1157-1165 first. Current code's `|| true` at end of reset line already degrades silently; the change is adding an explicit `WARN:` on fetch failure so the user sees it.
- **Files:** `.ccanvil/scripts/docs-check.sh` (comment + WARN: on fetch fail in `cmd_land`); `hub/tests/lifecycle-gate-audit.bats`.
- **Verify:** bats green.

### Step 6: Add `cmd_pr_guard` subcommand (AC-5)
- **Test:** New bats case in `lifecycle-gate-audit.bats` — seed a feature branch, make an extra commit on bare origin/main, run `docs-check.sh pr-guard`, assert exit 1 + `rebase origin/main` + `merge origin/main` in error message. Inverse: when feature branch is ahead and up-to-date with base, exit 0.
- **Implement:** New `cmd_pr_guard()` in `docs-check.sh`. Fetches origin main, asserts `git rev-list HEAD..origin/main` is empty (base hasn't moved past feature), `git rev-list origin/main..HEAD` is non-empty (feature has commits). On behind-base, emit AC-8-shaped error and exit 1. On no-origin/no-remote, no-op success (mirrors AC-9 pattern). Dispatch entry `pr-guard)`.
- **Files:** `.ccanvil/scripts/docs-check.sh`; `hub/tests/lifecycle-gate-audit.bats`.
- **Verify:** bats green.

### Step 7: Wire `pr-guard` into `/pr` skill pre-flight (AC-5)
- **Test:** Manual/dogfood — the ship's own `/pr` invocation exercises the new gate. No bats needed (skill prose is not test-harnessed).
- **Implement:** Edit `.claude/commands/pr.md` — add step 3.5 "Run `bash .ccanvil/scripts/docs-check.sh pr-guard`. If exit non-zero, STOP and surface the error." Place between existing validate step and code-review gate.
- **Files:** `.claude/commands/pr.md`.
- **Verify:** When we run `/pr` at the end of this ship, the gate fires (or passes silently if branch is in sync).

### Step 8: Full suite regression + command-reference update (AC-10)
- **Test:** `bats hub/tests/` — must match prior baseline + new tests. Target: 864 + N new tests, 0 failures.
- **Implement:** Add rows to `.ccanvil/guide/command-reference.md` for `docs-check.sh sync-check` and `docs-check.sh pr-guard`. Add cross-reference from `/pr` skill row to the new pre-flight gate.
- **Files:** `.ccanvil/guide/command-reference.md`.
- **Verify:** All bats green; `docs-check.sh validate` returns `aligned`.

## Risks

- **Fetch timeout** — `http.lowSpeedTime=5` may be too aggressive on slow networks. Mitigation: the offline fallback emits `WARN:` and proceeds; no user-visible halt. Revisit if bug reports surface.
- **`--force-sync` vs `--force-local-ahead` confusion** — keeping both is a small tax. Mitigation: document in command-reference + add a comment at the arg-parser that `--force-local-ahead` is the legacy alias.
- **`cmd_pr_guard` false positives** on feature branches rebased before their base moved — `rev-list HEAD..origin/main` picks up the rebased commits. Mitigation: the test covers a genuine behind-base state only; rebased-but-current branches should still show empty `HEAD..origin/main`.
- **Plan-hash rebase** — if mid-TDD spec edits for code-review WARNs recur (pattern observed in BTS-128 and BTS-119), re-stamp `> Spec hash:` before `/pr`. Conditional candidate for `docs-check.sh rebase-plan-hash` if it happens a 3rd consecutive time.

## Definition of Done

- [ ] All 10 acceptance criteria from spec pass (verified by bats)
- [ ] All 864+ existing tests still pass
- [ ] `cmd_sync_check` and `cmd_pr_guard` registered in dispatch switch
- [ ] `.claude/commands/pr.md` invokes `pr-guard` in pre-flight
- [ ] Command-reference guide updated with new subcommands
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
