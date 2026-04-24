# Feature: Fix stale recommend after stasis+compact+recall cycle

> Feature: bts-113-stale-recommend
> Work: linear:BTS-113
> Created: 1777054322
> Status: Draft

## Summary

`docs-check.sh recommend` returns `"/compact to wrap session"` at the start of every post-recall session because the lifecycle state `{stasis present, spec absent, plan absent, aligned}` matches both "session about to end" and "session just beginning after compact+recall". Observed live 4+ times. Fix: write a deterministic filesystem marker (via PreCompact hook or equivalent) that `recommend` uses to break the tie. After compact has run, recommend should surface the actual next action — start next feature, triage ideas, or run `/radar` — not repeat `/compact`.

## Job To Be Done

**When** I start a new session after `/compact` + `/recall`,
**I want to** have `recommend` surface a meaningful next action instead of looping me back to `/compact`,
**So that** the end-of-session → start-of-session handoff surfaces forward momentum, not already-done work.

## Acceptance Criteria

- [ ] **AC-1:** After a fresh `/compact` + `/recall` cycle (stasis committed, no active spec, no plan), `docs-check.sh recommend` returns something other than `"/compact to wrap session"`. It MUST return a forward-momentum action such as: `"Start next feature — run /radar"`, `"N untriaged ideas — run /idea triage"`, or `"Ship <next-spec-id> — run docs-check.sh activate"`.
- [ ] **AC-2:** At end-of-session (stasis just written, compact NOT yet run), `docs-check.sh recommend` still returns `"/compact to wrap session"` — the pre-compact path is preserved.
- [ ] **AC-3:** The deterministic signal used to break the tie is machine-observable: a filesystem marker file (e.g., `.ccanvil/state/last-compact-ts`) with epoch timestamp. `recommend` compares `stasis.last_updated` against this marker. If marker exists AND `marker > stasis.last_updated`, compact already happened → suggest forward action. Otherwise → suggest compact.
- [ ] **AC-4:** The marker is written by a PreCompact hook (or the best-available equivalent mechanism). The hook is registered in `.claude/settings.json` or `.claude/hooks/` per ccanvil convention.
- [ ] **AC-5:** Forward-action logic follows a clear hierarchy:
  - If `idea-count .new > 0` → suggest `/idea triage`.
  - Else if backlog has any `Ready` spec → suggest `docs-check.sh activate <id>`.
  - Else → suggest `/radar` (strategic briefing before starting new work).
- [ ] **AC-6:** Edge: marker file absent (first session, fresh clone, or hook failed to fire) → fall back to current behavior (suggest `/compact` if stasis+no-active-spec). No crashes, no errors.
- [ ] **AC-7:** Edge: marker file present but stale (e.g., stasis committed AFTER last compact) → detect the stasis-is-newer condition and correctly recommend `/compact` again.
- [ ] **AC-8:** Bats coverage for all 4 branches of the decision: (fresh session post-compact with ideas) / (fresh session post-compact without ideas) / (end-of-session pre-compact) / (no marker fallback).
- [ ] **AC-9:** `.ccanvil/state/` directory is added to `.gitignore` if not already — the marker is session-local, never committed.
- [ ] **AC-10:** Mechanism documented in `.ccanvil/guide/` (likely `session-management.md` or `command-reference.md`) so the hook's role is discoverable.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified (`cmd_recommend` updated) |
| `.claude/hooks/post-compact-marker.sh` | New (PreCompact hook) |
| `.claude/settings.json` | Modified (hook registration) |
| `.gitignore` | Modified (add `.ccanvil/state/` if absent) |
| `.ccanvil/guide/session-management.md` | Modified (document mechanism) |
| `hub/tests/recommend-freshness.bats` | New |

## Dependencies

- **Requires:** Claude Code PreCompact hook support (present via `xIslandHooks` in current environment; verify it fires for ccanvil's hook mechanism).
- **Blocked by:** Nothing.
- **Blocks:** Nothing immediately, but improves day-one UX for all ccanvil sessions.

## Out of Scope

- Refactoring the full `recommend` state machine. Only the stasis+no-active-spec branch is being fixed here.
- Adding new end-of-session recommendations beyond `/compact`. The pre-compact path stays as-is.
- Communicating "compact ran" to other tools outside `recommend`. Single consumer for now.
- If ccanvil's hook mechanism doesn't support PreCompact, fall back to **option (ii)** from the umbrella: inspect git HEAD message + parent. Document the fallback in the PR and file a separate ticket for proper hook support.

## Implementation Notes

- **Deterministic signal (chosen):** a filesystem marker. PreCompact hook touches `.ccanvil/state/last-compact-ts` with `date +%s`. `recommend` compares this timestamp against `stasis.last_updated` (already surfaced in `docs-check.sh status` JSON).
- **Decision logic:**
  ```
  if stasis exists AND no active spec:
    marker_ts = read .ccanvil/state/last-compact-ts if exists
    stasis_ts = stasis.last_updated

    if marker_ts AND marker_ts >= stasis_ts:
      return forward_action()  # /idea triage | /radar | next feature
    else:
      return "/compact to wrap session"

  forward_action():
    if idea-count.new > 0: return "/idea triage"
    else: return "/radar to brief the next feature"
  ```
- **PreCompact hook shape (`.claude/hooks/post-compact-marker.sh`):**
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  mkdir -p .ccanvil/state
  date +%s > .ccanvil/state/last-compact-ts
  ```
  Registered in `.claude/settings.json` under `hooks.PreCompact` (or whatever the canonical key is — verify during planning).
- **Risk: hook doesn't fire.** If Claude Code's PreCompact hook wiring is unreliable or unsupported, the marker is never written and `recommend` keeps suggesting `/compact`. Mitigation: AC-6 fallback preserves current behavior if marker missing. Also: log a `WARN:` if the marker is older than some threshold (e.g., 30 days), suggesting hook breakage.
- **Observability:** `docs-check.sh status` should expose `last_compact_ts` in its JSON output (alongside `stasis.last_updated`) so `/recall` can display it. Small additive surface; low risk.
- **Strict-mode / formatting:** new bats file uses BTS-127 strict-mode convention. New error output (if any) follows BTS-122 `_assert_error_format` shape.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
