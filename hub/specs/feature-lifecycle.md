# Feature: Codified feature lifecycle with draft PR and doc cleanup

> Feature: feature-lifecycle
> Created: 1775614129
> Status: In Progress

## Summary

Codify the full feature lifecycle into a deterministic, documented flow: Spec → Activate (branch + draft PR) → Plan → Implement → Finalize (cleanup + mark PR ready) → Merge. Currently, PRs are created after all code is written, and lifecycle docs (spec.md, plan.md, checkpoint.md) leak onto main requiring manual cleanup. This feature closes both gaps by shifting PR creation to activation time and adding automatic doc cleanup at completion.

## Job To Be Done

**When** I activate a spec and begin working on a feature,
**I want** a draft PR created immediately that tracks my progress, and automatic cleanup of lifecycle docs when the work is complete,
**So that** the team sees intent from the start, the branch is always merge-ready when finalized, and I never manually clean up stale docs.

## Acceptance Criteria

### Activate creates draft PR

- [ ] **AC-1:** `docs-check.sh activate <feature-id>` creates a draft PR on GitHub after creating the branch and committing the spec. PR title follows `feat(<feature-id>): <first-line-of-spec-summary>`. PR body includes the spec's summary and acceptance criteria.
- [ ] **AC-2:** If `gh` CLI is not available or not authenticated, activate still succeeds (branch + commit) but prints a warning: `"NOTE: Draft PR not created — gh CLI not available. Run /pr to create manually."`
- [ ] **AC-3:** If the repo has no GitHub remote, activate skips PR creation silently (local-only workflow).

### Complete cleans up lifecycle docs

- [ ] **AC-4:** `docs-check.sh complete <feature-id>` removes `docs/spec.md`, `docs/plan.md`, and `docs/checkpoint.md` after marking the spec as Complete. The archived spec in `docs/specs/` is preserved.
- [ ] **AC-5:** Complete commits the doc removal with message: `docs(lifecycle): complete <feature-id> — clean up lifecycle docs`
- [ ] **AC-6:** Complete marks the draft PR as ready for review using `gh pr ready` (if gh is available and a PR exists for the current branch).

### /pr skill repurposed

- [ ] **AC-7:** The `/pr` skill becomes a "finalize PR" command: it runs tests, validates docs, cleans up lifecycle docs (if not already done by complete), and marks the PR as ready. If no PR exists yet (e.g., gh was unavailable at activate time), it creates one.
- [ ] **AC-8:** The `/pr` skill no longer creates a PR from scratch on a clean branch — that's activate's job. If called on a branch with no commits beyond the spec activation, it warns: `"No implementation commits yet. Continue building before running /pr."`

### CI safety net

- [ ] **AC-9:** The CI workflow template checks for the presence of `docs/spec.md`, `docs/plan.md`, or `docs/checkpoint.md` on PRs targeting main. If any exist, the check fails with: `"Lifecycle docs must be cleaned up before merge. Run docs-check.sh complete <feature-id>."`

### Lifecycle documentation

- [ ] **AC-10:** The workflow rule (`.claude/rules/workflow.md`) documents the full lifecycle: Spec → Activate → Plan → Implement → Finalize → Merge, replacing the current ad-hoc description.
- [ ] **AC-11:** The command reference (`.ccanvil/guide/command-reference.md`) documents the enhanced activate and complete behaviors.

### Tests

- [ ] **AC-12:** All existing tests pass (378+).
- [ ] **AC-13:** New tests: activate creates draft PR (mocked gh), activate succeeds without gh, complete removes lifecycle docs, complete commits cleanup, CI check detects stale docs, CI check passes when docs are clean.

## Affected Files

| File | Change |
|------|--------|
| `preset/.ccanvil/scripts/docs-check.sh` | Enhance `cmd_activate` (draft PR) and `cmd_complete` (doc cleanup + commit + PR ready) |
| `preset/.claude/commands/pr.md` | Repurpose as finalize/ready command |
| `preset/.ccanvil/templates/github/workflows/ci.yml` | Add lifecycle docs check |
| `preset/.claude/rules/workflow.md` | Document full lifecycle flow |
| `preset/.ccanvil/guide/command-reference.md` | Update activate/complete docs |
| `hub/tests/docs-check.bats` | New tests for enhanced activate/complete |

## Dependencies

- **Requires:** `gh` CLI for PR creation (graceful degradation when unavailable)

## Out of Scope

- Auto-merge after PR is marked ready (user or CI handles merge)
- Branch deletion after merge (GitHub auto-delete setting or manual)
- Enforcing linear history or squash-only merges (repo-level setting)
- Modifying the spec or plan templates

## Implementation Notes

- `cmd_activate` draft PR: push branch with `git push -u origin <branch>`, then `gh pr create --draft`. Extract summary from spec for PR body. Wrap in `if command -v gh` guard.
- `cmd_complete` doc cleanup: `rm -f docs/spec.md docs/plan.md docs/checkpoint.md`, then `git add` + `git commit`. Call `gh pr ready` if PR exists for current branch.
- CI check: simple bash step — `if ls docs/spec.md docs/plan.md docs/checkpoint.md 2>/dev/null; then exit 1; fi`
- The `/pr` skill becomes a superset: test → validate → cleanup → push → ready. If PR doesn't exist, create it (handles the "gh was unavailable at activate" case).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
