Finalize the current feature branch for merge.

This command ensures the branch is ready for merge: tests pass, docs are validated, lifecycle docs are cleaned up, and the PR is marked ready for review.

## Pre-flight checks

1. Verify you are NOT on the default branch (main/master). If so, STOP with: "Cannot finalize from the default branch. Activate a spec first to create a feature branch."
2. Run the project's test suite. If tests fail, STOP — show failures and do not proceed.
3. Run `.ccanvil/scripts/docs-check.sh validate` (if it exists). If result is not `aligned` and not `no-active-spec`, STOP — show the validation result.

## Optional: Code review gate

4. Read `.claude/ccanvil.json` and check if `features.pr_review` is `true`.
5. If `pr_review` is enabled AND arguments do NOT include `--skip-review`:
   - Spawn the code-reviewer sub-agent (use the `code-reviewer` agent definition).
   - If the reviewer finds CRITICAL issues, STOP — show the issues and do not proceed.
   - If the reviewer finds WARN-level issues, collect them for the PR body "Review Notes" section.
6. If `--skip-review` was passed, skip the review step.

## Clean up lifecycle docs

7. If `docs/spec.md`, `docs/plan.md`, or `docs/stasis.md` exist, remove them and commit:
   ```bash
   rm -f docs/spec.md docs/plan.md docs/stasis.md
   git add docs/spec.md docs/plan.md docs/stasis.md
   git commit -m "docs(lifecycle): clean up lifecycle docs before merge"
   ```

## Push and finalize PR

8. Push the current branch: `git push`
9. Check if a draft PR already exists for this branch:
   ```bash
   gh pr view --json state,url 2>/dev/null
   ```
   - **If PR exists:** Mark it ready with `gh pr ready`. Update the body if needed.
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

    ## Assumptions & Decisions
    <Contents of docs/assumptions.md if it exists and is non-empty, otherwise omit this section>

    ## Review Notes
    <WARN-level findings from code review if pr_review was enabled, otherwise omit this section>

    🤖 Generated with [Claude Code](https://claude.com/claude-code)
    ```
12. Show the PR URL to the user.

## Guard: no premature finalization

13. If the branch has no implementation commits beyond the spec activation commit, warn: "No implementation commits yet. Continue building before running /pr." and STOP.

## Arguments

- `--skip-review`: Skip the code review gate even if `pr_review` is enabled in ccanvil.json.

## Rules

- PRs are always created as drafts initially (via activate). /pr marks them ready.
- Never run /pr from main/master.
- Always run tests and validation before finalizing.
- After the PR is merged, run `docs-check.sh land` to switch to main, sync, and delete the branch.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
