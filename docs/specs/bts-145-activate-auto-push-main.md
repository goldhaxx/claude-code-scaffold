# Feature: cmd_activate auto-push-main

> Feature: bts-145-activate-auto-push-main
> Work: linear:BTS-145
> Created: 1777081272
> Status: Complete

## Summary

Three consecutive sessions have flagged the same recurring friction: write spec on main → commit on main → activate fails with "local main is AHEAD of origin/main" → manually push → re-activate. 11 redundant `git push origin main` invocations across three sessions. Per `.claude/rules/deterministic-first.md`: same input → same correct response → it should be a script. Modify `cmd_activate` so that when the sync check trips on AHEAD AND the current branch is `main`, the script auto-pushes `origin main` and then proceeds with activation. Bypassable via `--no-auto-push`. The BEHIND case stays unchanged (auto-pull is a different, more dangerous primitive).

## Job To Be Done

**When** I activate a spec from main after committing the draft locally,
**I want to** the activate command to push main itself instead of erroring out,
**So that** spec → activate is one step, not three (write spec, push main, retry activate).

## Acceptance Criteria

- [ ] **AC-1:** Default `cmd_activate <id>` on a clean main with unpushed commits pushes `origin main` automatically, then completes activation successfully (branch created, draft PR opened, exit 0).
- [ ] **AC-2:** `cmd_activate <id> --no-auto-push` preserves the current behavior — errors out with "local main is AHEAD" and exits non-zero.
- [ ] **AC-3:** When on a non-main branch with unpushed commits, auto-push does NOT fire — the existing AHEAD error path applies. Auto-push only triggers when `git branch --show-current` returns `main`.
- [ ] **AC-4:** Auto-push failure (e.g., bad remote URL, network issue) surfaces a clean error and does NOT proceed with activation. Stderr names the failure mode and shows the manual-resolution path.
- [ ] **AC-5:** `--force-sync` flag continues to bypass the entire sync check (preserves current semantics; no interaction with auto-push).
- [ ] **AC-6:** BEHIND case (local main is behind origin/main) is unchanged — auto-push does NOT fire on behind. The user still gets the existing BEHIND error with `git pull --ff-only` guidance.
- [ ] **AC-7:** When auto-push fires, stderr emits a marker line `AUTO-PUSH: local main is ahead of origin; pushing first...` followed by `AUTO-PUSH: success.` on completion. Visibility lets the user trace what happened.
- [ ] **AC-8:** New bats cases in `hub/tests/activate-push-guard.bats` covering AC-1 / AC-2 / AC-3 / AC-4 / AC-6; full bats suite stays green (no regressions in the existing 1051 cases).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `--no-auto-push` flag to `cmd_activate`, insert auto-push branch in the AHEAD path |
| `hub/tests/activate-push-guard.bats` | Modified — add 5+ new bats cases covering AC-1..AC-7 |

## Dependencies

- **Requires:** BTS-122 (`cmd_sync_check`) — already in place; we delegate the AHEAD/BEHIND distinction to it.
- **Blocked by:** Nothing.

## Out of Scope

- **Auto-pull on BEHIND** — different primitive, different risk profile (pulling silently could pull in regressions or merge conflicts). Capture as a follow-on if it ever becomes a recurring pattern.
- **Auto-push on non-main branches** — explicitly NOT in scope per AC-3. Unpushed commits on a feature branch are local-only by intent in many workflows; pushing them silently would surprise the user.
- **Configurable default branch name** — script already hardcodes `main` throughout (`git fetch origin main`, `main..origin/main`). Master-branch support is a separate concern.
- **Network-flake retry logic** — single push attempt; if it fails, the user fixes manually. Matches the BTS-119 posture ("never block forward progress on network flakes" applies to the sync check itself, not to mutations).

## Implementation Notes

- Insert the auto-push branch after `cmd_sync_check` returns 1 (AHEAD) but before the existing error block. Same `force_sync` short-circuit applies — if `--force-sync` was passed, sync_check isn't run at all and auto-push doesn't enter the picture.
- Detection: `git -C "$repo_root" branch --show-current 2>/dev/null` — equality check against `"main"`.
- Auto-push command: `git -C "$repo_root" push origin main`. Capture exit code; on success, set `sc_rc=0` to bypass the error block. On failure, exit 1 with a manual-resolution message naming the feature_id (`bash .ccanvil/scripts/docs-check.sh activate <id>` retry hint).
- The arg parser already supports flag-positional interleaving — `--no-auto-push` slots in via the same `case` pattern as `--force-sync`. Default `auto_push=true`.
- Test pattern: extend `hub/tests/activate-push-guard.bats` (already covers the AHEAD guard contract). Use the existing `seed_repo_with_origin --docs-specs` helper. New cases create a local-only commit on main (matches AC-17's pattern), then run activate with various flag combos and assert post-conditions:
  - AC-1: `git -C "$REPO" log origin/main..main` is empty after the call (auto-push happened)
  - AC-2: same setup + `--no-auto-push` → exit 1, AHEAD error
  - AC-3: checkout a feature branch, commit there, run activate → AHEAD error (no auto-push)
  - AC-4: simulate push failure by removing the bare remote dir mid-test → exit 1, error names the failure
  - AC-6: simulate BEHIND by committing directly to the bare remote → activate exits 2, no auto-push attempt

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
