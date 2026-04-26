# Feature: lifecycle adapter for local-only (no-remote) repos

> Feature: bts-72-local-only-repo-lifecycle
> Work: linear:BTS-72
> Created: 1777181565
> Status: Complete

## Summary

Today's `/pr` skill orchestrates `git push`, `gh pr create`, `gh pr ready`, and downstream `gh pr merge --squash` — every step assumes a GitHub remote and `gh` auth. Local-only repos (no `origin` configured, or repos not on GitHub) hit hard failures partway through. `cmd_land` has piecemeal `git remote get-url origin` checks but no centralized "what kind of repo is this" classifier. Add a substrate primitive `docs-check.sh detect-repo-type` returning a deterministic `{type: github|other-remote|local, has_remote, remote_url}` envelope, then branch `/pr` skill prose AND `cmd_land` on the result. Local-only `/pr` performs an in-place `git merge --no-ff` to main + branch deletion (no PR, no push). Local-only `/land` is a near-no-op (verifies on main + emits AUTO-CLOSE marker for Linear-routed specs since work-ref tracking is provider-orthogonal to repo-type).

## Job To Be Done

**When** I'm running ccanvil's lifecycle (`/pr`, `/land`) on a local-only repo (no remote, or non-GitHub remote),
**I want** the same `spec → activate → implement → /pr → /land → on-main` outcome as on a GitHub-backed repo,
**So that** local-dev projects without a GitHub origin get the full ccanvil lifecycle without me having to know which steps to skip or which commands to substitute.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `docs-check.sh detect-repo-type` invoked in a repo with `origin` pointing to a `github.com` URL emits JSON `{type: "github", has_remote: true, remote_url: "<url>"}` and exits 0.
- [ ] **AC-2:** Invoked in a repo with `origin` pointing to a non-GitHub URL (e.g., `gitlab.com/...`, `git@bitbucket.org:...`) emits `{type: "other-remote", has_remote: true, remote_url: "<url>"}`. Out-of-scope for full GitLab/Bitbucket integration; classifier just reports the state.
- [ ] **AC-3:** Invoked in a repo with NO `origin` configured emits `{type: "local", has_remote: false, remote_url: ""}`.
- [ ] **AC-4:** Invoked outside a git repo entirely exits 2 with `detect-repo-type: not in a git repository`.
- [ ] **AC-5:** `cmd_land` on a local-only repo (post-merge state: feature already merged into main, on main) detects the type, skips the `git fetch origin` + `git reset --hard origin/main` block. Output contains `Already on main. No remote configured.` Note: the AUTO-CLOSE marker does NOT fire on the local-only already-on-main path — `cmd_land_recover_branch` parses the squash-merge `(#NN)` suffix and queries `gh` to recover the branch name. Local-only repos have no gh PR, so recovery silently no-ops. Documented gap; capture follow-up to parse local merge-commit subject for branch recovery if the friction surfaces. The on-feature-branch path (AC-6) is the canonical local-only land flow and DOES fire the marker.
- [ ] **AC-6:** `cmd_land` on a local-only repo where the user invokes from the FEATURE branch (not yet merged): detects type, performs in-place `git checkout main; git merge --no-ff <branch>; git branch -d <branch>` (no fetch, no reset), emits AUTO-CLOSE marker, ends with the user on main and the feature branch deleted.
- [ ] **AC-7:** `/pr` skill prose documents the local-only branch in Step 7 (push and finalize): when `detect-repo-type.type == "local"`, perform the in-place merge instead of `git push` + `gh pr create`. Drift-guard test asserts the literal phrase `local-only` appears in the skill's push/finalize section.
- [ ] **AC-8:** Drift-guard — `cmd_detect_repo_type` is registered in the dispatch case via `grep -q "detect-repo-type)" docs-check.sh`.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/docs-check.sh` | Modified — add `cmd_detect_repo_type` + branch `cmd_land` on detection; consolidate scattered `git remote get-url origin` checks where structurally clean |
| `.claude/skills/pr/SKILL.md` | Modified — Step 7 (push and finalize) branches on detection; local-only path documented |
| `hub/tests/detect-repo-type.bats` | New — AC-1 through AC-4 tests via `git init` fixtures |
| `hub/tests/land-local-only.bats` | New — AC-5 through AC-6 tests via `git init` fixtures |

## Dependencies

- **Requires:** existing `cmd_land`, `cmd_auto_close_emit`, and `cmd_land_recover_branch` substrates (already in place).
- **Blocked by:** none.

## Out of Scope

- **`/merge` alias.** The original ticket asked "keep `/pr` for GitHub and add `/merge`?" Unifying into `/pr` is the proportionate choice — one orchestration surface, one detection branch. A `/merge` alias is one-line skill metadata if needed later; not in this ship.
- **Other-remote (GitLab, Bitbucket) integration.** AC-2 detects and labels but does not implement an MR/glab equivalent. Local-only is the immediate case; non-GitHub remotes are explicitly captured as `other-remote` and surface a `/pr: non-GitHub remote detected — manual flow required` warning. Capture as follow-up if a real GitLab user surfaces.
- **`gh auth status` integration.** Detection is repo-config based, not credential-based. A user with a GitHub remote but expired `gh` auth gets the GitHub flow which then fails at `gh pr create` — that's an existing, explicit failure mode (orthogonal to repo-type detection).
- **GitHub-flow refactor.** The existing GitHub path stays exactly as-is. This ticket adds a parallel local-only path; it does not refactor the GitHub orchestration.
- **`docs-check.sh activate` branching.** Activate creates a draft PR via `gh pr create`. On a local-only repo, this currently fails. Out of scope here — capture as follow-up. The friction shows up first at `/pr`, which this ticket fixes; activate's failure is a separate surface.

## Implementation Notes

- **`cmd_detect_repo_type` shape.** Pure read-only inspection. Calls `git rev-parse --is-inside-work-tree` (exit 2 on not-in-repo), then `git remote get-url origin`. Classifier:
  ```bash
  if not in repo: exit 2
  if remote_url is empty: type=local, has_remote=false
  elif remote_url contains "github.com": type=github
  else: type=other-remote
  ```
  Emits one JSON line via `jq -n`. Idempotent.
- **`cmd_land` branching pattern.** At entry, call detection once; cache type. Where current code says `if git remote get-url origin >/dev/null 2>&1`, replace with `if [[ "$repo_type" != "local" ]]`. Where the detection-aware code emits a "no remote" message, route through to AUTO-CLOSE emission unchanged. Local-only-on-feature-branch path: `git checkout main; git merge --no-ff <branch>; git branch -d <branch>` followed by AUTO-CLOSE emission. No `gh` calls, no fetch.
- **`/pr` skill prose pattern.** Step 7 (push and finalize) gains a detection branch:
  ```bash
  REPO_TYPE=$(bash .ccanvil/scripts/docs-check.sh detect-repo-type | jq -r '.type')
  case "$REPO_TYPE" in
    github)        # existing flow: git push, gh pr ready/create, set body
    local)         # in-place merge: git checkout main; git merge --no-ff <branch>; git branch -d <branch>
    other-remote)  # warn + halt: "non-GitHub remote, manual flow required"
  esac
  ```
- **Test fixture pattern.** Bats setup: `mktemp -d` + `git init` + `git -c user.email=x@x -c user.name=x commit --allow-empty -m initial` to materialize an actual repo. For AC-1, add `git remote add origin git@github.com:foo/bar.git`. For AC-2, `git@gitlab.com:foo/bar.git`. For AC-3, no remote. Each test scopes its own tmpdir.
- **No live-API risk.** All shell-logic substrate. /review may surface concerns on the bigger cmd_land diff; not auto-skipping.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
