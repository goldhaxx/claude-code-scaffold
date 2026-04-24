# Feature: Lifecycle Gate Audit — Harden Pre-Activate & Reciprocal Guards

> Feature: bts-122-lifecycle-gate-audit
> Work: linear:BTS-122
> Created: 1777047608
> Status: In Progress

## Summary

Audit and harden the pre/post-feature-work lifecycle gates (`cmd_activate`, `cmd_land`, `cmd_pr_cleanup`, and the `/pr` skill). The current `cmd_activate` push-guard (`docs-check.sh:750`) correctly rejects local-ahead drift but uses the *cached* `origin/main` ref (no fetch) and has no symmetric local-behind detection. That creates a window where activate greenlights a stale baseline — feature branches are cut off drifted main and produce avoidable merge conflicts. This ship closes that window at activate time, adds a matching feature-branch-behind-base guard at `/pr` finalization, and documents current working-tree + reciprocal-guard behavior at `cmd_land` so subsequent hardening ships have a definite baseline.

## Job To Be Done

**When** I activate a spec on main or finalize a PR for merge,
**I want** the lifecycle script to verify the relevant branch is in sync with origin (fetched, not cached) before creating the branch or marking the PR ready,
**So that** I cannot accidentally start work from a stale baseline or ship a PR that will merge-conflict after the next pull.

## Acceptance Criteria

- [ ] **AC-1:** `cmd_activate` runs `git fetch origin main` (with a 5s timeout via `git -c fetch.pruneTags=false -c http.lowSpeedTime=5 fetch`) before comparing `main` to `origin/main`. Asserted via a bats test that seeds a fresh remote commit on a bare repo after the local clone, then runs activate — the guard must detect the local-behind state, not the pre-fetch cached state.
- [ ] **AC-2:** When `main` is behind `origin/main`, `cmd_activate` halts with exit 1 and an error message containing `behind` and `git pull --ff-only origin main`. Escape hatch `--force-local-ahead` is renamed to `--force-sync` and also bypasses the behind check (since its existing purpose — "I know my main has drifted and I want it anyway" — is symmetric). Old flag name kept as an alias for backward compatibility; bats test covers both forms.
- [ ] **AC-3:** When `git fetch origin main` fails (offline, auth error, network partition), `cmd_activate` emits `WARN: offline — skipping sync check` on stderr and proceeds using the cached ref. Exit status is 0 from the fetch failure itself; guard still evaluates against the stale ref. Asserted via a bats test that points `origin` at a non-existent path.
- [ ] **AC-4:** When the target branch `claude/<type>/<feature-id>` already exists locally, `cmd_activate` halts with exit 1 and an error message naming the branch and suggesting `git branch -D <name>` or `git checkout <name>` for resume. Asserted via a bats test.
- [ ] **AC-5:** `/pr` skill pre-flight gains step "verify feature branch is not behind base" — runs `git fetch origin main` then checks `git rev-list origin/main..HEAD` is non-empty and `git rev-list HEAD..origin/main` is empty. If behind, halt with remediation instructions (`git rebase origin/main` or `git merge origin/main`). Implemented as new `docs-check.sh pr-guard` subcommand invoked from the skill; asserted via a bats test that seeds a behind-base feature branch.
- [ ] **AC-6 (audit):** Document the current `cmd_activate` working-tree check (`docs-check.sh:830-852`) scope in a new comment block: allows `docs/specs/*`, `docs/spec.md`, `docs/roadmap.md`; rejects everything else. Add one bats test asserting `.env.example` or `README.md` uncommitted changes fail the guard with exit 1 — the check was introduced in `safe-init` and has no current regression coverage.
- [ ] **AC-7 (audit):** Document current `cmd_land` sync behavior in a new comment block: fetches origin before `git reset --hard origin/main`. Add one bats test asserting that when `origin/main` is unreachable (network failure), `cmd_land` prints a `WARN:` line and exits 0 without resetting (graceful degradation), rather than resetting to whatever stale ref exists.
- [ ] **AC-8 (error format):** Every guard error message follows the shape: line 1 `ERROR: <what happened>`, blank line, then 1–3 remediation bullets prefixed with two spaces. A bats test exercises each guard's error path and asserts the shape via a shared regex helper.
- [ ] **AC-9 (edge):** When `cmd_activate` runs in a repo with no `origin` remote at all (fresh local-only repo), all sync checks are no-ops and the guard passes. Covered by the existing `activate-push-guard.bats` AC-19 test; extended to also assert no spurious `WARN:` lines print.
- [ ] **AC-10 (regression):** All 864 existing bats tests remain green after the refactor. A consolidated `scripts/pre-flight.sh` helper (if introduced) is used by both `cmd_activate` and the new `pr-guard` path; the existing `activate-push-guard.bats` AC-17/18/19 assertions still pass with the refactored guard.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified: `cmd_activate` adds fetch + behind check + offline fallback + branch-exists check; new `cmd_pr_guard` |
| `.ccanvil/scripts/pre-flight.sh` | New: shared helper (optional — refactor commit if gates diverge) |
| `.claude/commands/pr.md` | Modified: invoke `docs-check.sh pr-guard` in pre-flight block |
| `hub/tests/activate-push-guard.bats` | Modified: extended for AC-1/2/3/4/6/9/10 |
| `hub/tests/lifecycle-gate-audit.bats` | New: AC-5, AC-7, AC-8 |

## Dependencies

- **Requires:** `git fetch` already permissive in `.claude/settings.json` (confirmed — `Bash(git fetch:*)` allowed).
- **Blocked by:** none.

## Out of Scope

- **Multi-remote support** (BTS-122 gap #6): guard still hard-codes `origin`. Defer to separate ticket — niche, unclear demand.
- **Non-`main` default branch support** (gap #7): guard still hard-codes `main`. Defer — ccanvil's convention is main-only; deviation requires a design-level decision.
- **Stasis-commits-on-main architectural rethink** (gap #10): moving stasis commits off main (to a dedicated branch or git notes) is architectural. Defer to a separate spec that evaluates `session-log` branch vs. `git notes` vs. status quo. `--force-local-ahead`/`--force-sync` remains the escape hatch until then.
- Rewriting `cmd_land`'s safety-net logic (BTS-119 shipped it; separate ticket for that path).

## Implementation Notes

- Follow BTS-119's script-skill split pattern: put all git + decision logic in `docs-check.sh`, consume exit codes from the skill. `/pr`'s pre-flight becomes a single `docs-check.sh pr-guard || exit 1` call.
- Reuse the `parse_metadata` + `jq` pattern already in `docs-check.sh` for any metadata reads.
- The behind-detection check uses the same `rev-list origin/main..main` shape inverted (`main..origin/main`) to stay consistent with the existing ahead check — one less mental model for readers.
- For the offline fallback, follow the BTS-119 "never block forward progress" pattern: network failures degrade with a `WARN:` not a halt. Exception: when the user explicitly invokes `--sync` (reserved for future opt-in), fetch failure becomes fatal.
- `--force-sync` alias: keep `--force-local-ahead` wired up as a silent synonym; a future ship can deprecate it. Do not emit a deprecation warning this ship — noise tax on existing scripts.
- Consolidating the fetch+compare helper into `pre-flight.sh` is optional. Ship it only if the same code lands in both `cmd_activate` and `cmd_pr_guard` — otherwise defer to avoid premature abstraction (per `CLAUDE.md`).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
