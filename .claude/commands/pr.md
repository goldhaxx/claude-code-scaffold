---
manifest:
  id: pr
  purpose: Finalize a feature branch for merge — verify tests pass, validate spec/plan docs, clean up lifecycle archive, mark PR ready for review
  routes-by: /pr
  input:
    - "flag: --skip-review (optional, bypasses code-reviewer gate)"
  output:
    - "github-state: PR moved from Draft to Ready"
    - "side-effect: lifecycle docs (docs/spec.md, docs/plan.md) removed; archive committed"
  depends-on:
    - bats-report.sh
    - docs-check.sh
    - code-reviewer
  side-effect:
    - mutates-pr-state-on-github
    - removes-lifecycle-docs
    - commits-cleanup
  failure-mode:
    - "on-default-branch | exit=1 | visible=stderr-error | mitigation=activate-spec-first"
    - "tests-failing | exit=1 | visible=test-output | mitigation=fix-and-retry"
    - "lifecycle-blocked | exit=1 | visible=blocker-list | mitigation=resolve-blockers-from-envelope"
    - "behind-base | exit=1 | visible=pr-guard-error | mitigation=rebase-on-main"
  contract:
    - never-runs-on-default-branch
    - never-marks-ready-with-failing-tests
    - cleanup-is-deterministic
  anchor:
    - BTS-118 (bats-report.sh integration)
    - BTS-122 (pr-guard behind-base check)
    - BTS-20 (lifecycle-state pre-flight)
    - BTS-240 (reference manifest seed)
---

Finalize the current feature branch for merge.

This command ensures the branch is ready for merge: tests pass, docs are validated, lifecycle docs are cleaned up, and the PR is marked ready for review.

## Pre-flight checks

1. Verify you are NOT on the default branch (main/master). If so, STOP with: "Cannot finalize from the default branch. Activate a spec first to create a feature branch."
2. Run the project's test suite via `bash .ccanvil/scripts/bats-report.sh --parallel --progress` (BTS-118 single-invocation discipline + BTS-383 streaming progress so 0-byte stderr during the run is impossible — per-file `[N/M]` completion lines + 30s-idle heartbeat eliminate the "is it hung?" failure mode). Never chain `bats | tail`, `bats | grep ok`, `bats | grep not ok` — that's 3× the wall-time. If tests fail (exit non-zero), STOP — show failures and do not proceed (BTS-383 `--json` mode also returns a `failures[]` envelope with per-test `{test_name, file, line_number, error_excerpt}` when callers prefer structured output).
3. **BTS-20: lifecycle-state pre-flight.** Run `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` and capture the envelope. If `.state == "blocked"`, STOP and surface `.blockers[]` to the operator. If `.state` is otherwise unexpected for a /pr context (e.g. `uninitialized`, or `no-active-spec` on a non-ccanvil PR is acceptable), use judgment per the surfaced blockers. Then run `bash .ccanvil/scripts/docs-check.sh pr-guard` (BTS-122) — separate concern, behind-base check. If pr-guard exits non-zero, STOP and surface the error. Fetch failures (offline) emit `WARN:` on stderr and pass — never block finalization on a network flake.

## Optional: Code review gate

4. Read `.claude/ccanvil.json` and check if `features.pr_review` is `true`.
5. If `pr_review` is enabled AND arguments do NOT include `--skip-review`:
   - Spawn the code-reviewer sub-agent (use the `code-reviewer` agent definition).
   - If the reviewer finds CRITICAL issues, STOP — show the issues and do not proceed.
   - If the reviewer finds WARN-level issues, collect them for the PR body "Review Notes" section.
6. If `--skip-review` was passed, skip the review step.

## Clean up lifecycle docs + transition archive

7. Run the deterministic cleanup wrapper:
   ```bash
   bash .ccanvil/scripts/docs-check.sh pr-cleanup
   ```
   When `docs/spec.md` is present, this invokes `cmd_complete` — flipping the spec archive (`docs/specs/<id>.md`) from `In Progress` to `Complete`, removing the active lifecycle docs (`docs/spec.md`, `docs/plan.md`, `docs/stasis.md`), and committing on the feature branch. The archive transition rides the squash-merge into main — no manual `complete` follow-up needed.
   When no `docs/spec.md` exists (e.g., PR doesn't correspond to a ccanvil spec), it falls back to removing any lingering lifecycle docs + commit.
   If the call exits non-zero, STOP and surface the error — do not proceed to push.

## Push and finalize (branches on repo type — BTS-72)

7a. **Detect repo type** before pushing or invoking gh:
   ```bash
   REPO_TYPE=$(bash .ccanvil/scripts/docs-check.sh detect-repo-type | jq -r '.type')
   ```
   Three branches:
   - **`github`** → existing PR flow (steps 8–12 below).
   - **`local-only`** → no remote configured. Skip push + gh entirely. Run `bash .ccanvil/scripts/docs-check.sh land --force` from the feature branch to perform the in-place merge into main + branch deletion. End on main. STOP — there is no PR concept; the lifecycle is complete after the local merge.
   - **`other-remote`** → non-GitHub remote (GitLab, Bitbucket, GitHub Enterprise on non-`github.com`). Warn: `non-GitHub remote detected — manual flow required` and STOP. Operator handles the merge via the appropriate provider tool.

## Push and finalize PR (github path)

8. Push the current branch: `git push`
9. Check if a draft PR already exists for this branch:
   ```bash
   gh pr view --json state,url,number 2>/dev/null
   ```
   - **If PR exists:** Mark it ready with `gh pr ready`. Then assert the title matches the spec-derived expected form via `bash .ccanvil/scripts/docs-check.sh assert-pr-title <pr-number>` (BTS-178) — force-updates placeholder titles like `feat(auth-system)` so the squash-merge commit on main carries the correct subject. Update the body if needed.
   - **If no PR exists:** Create one using the flow below.
10. If creating a new PR, determine the title:
    - If the archived spec exists in `docs/specs/`, use: `feat(<feature-id>): <short description>`
    - Otherwise, generate from the branch name and recent commits.
11. Build the PR body:
    ```
    ## Summary
    <1-3 bullet points from spec or commit history>

    ## Test Plan
    <Test results summary — number passing, any notable coverage>

    ## Spec
    <Embedded spec excerpt — see step 11a>

    ## Assumptions & Decisions
    <Contents of docs/assumptions.md if it exists and is non-empty, otherwise omit this section>

    ## Review Notes
    <WARN-level findings from code review if pr_review was enabled, otherwise omit this section>

    🤖 Generated with [Claude Code](https://claude.com/claude-code)
    ```
11a. **BTS-204: embed canonical spec excerpt.** Read the spec via the
     provider-aware primitive so reviewers don't need to round-trip to
     Linear: `bash .ccanvil/scripts/docs-check.sh artifact-read --kind spec --feature <FEATURE_ID>`.
     Inline the result as a fenced markdown block under `## Spec`. One-time
     render at PR-creation time — not a sustained twin source. On
     local-routed nodes this reads `docs/spec.md`; on Linear-routed it reads
     the spec Linear Document. If the call returns empty (no active spec on
     the branch), omit the `## Spec` section.
12. Show the PR URL to the user.

## Guard: no premature finalization

13. If the branch has no implementation commits beyond the spec activation commit, warn: "No implementation commits yet. Continue building before running /pr." and STOP.

## Arguments

- `--skip-review`: Skip the code review gate even if `pr_review` is enabled in ccanvil.json.

## Rules

- PRs are always created as drafts initially (via activate). /pr marks them ready.
- Never run /pr from main/master.
- Always run tests and validation before finalizing.
- After the PR is merged, run `/land` — the canonical post-merge flow. It wraps `docs-check.sh land` (git mechanics) and auto-closes the linked Linear issue via the `ticket.transition` primitive (BTS-119). Running `docs-check.sh land` directly also works but skips the Linear auto-close; the transition will not fire and the issue stays open in Linear.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
