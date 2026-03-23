Create a draft pull request from the current feature branch.

## Pre-flight checks

1. Verify you are NOT on the default branch (main/master). If so, STOP with: "Cannot create PR from the default branch. Activate a spec first to create a feature branch."
2. Run the project's test suite. If tests fail, STOP — show failures and do not create PR.
3. Run `scripts/docs-check.sh validate` (if it exists). If result is not `aligned` and not `no-active-spec`, STOP — show the validation result.

## Optional: Code review gate

4. Read `.claude/scaffold.json` and check if `features.pr_review` is `true`.
5. If `pr_review` is enabled AND arguments do NOT include `--skip-review`:
   - Spawn the code-reviewer sub-agent (use the `code-reviewer` agent definition).
   - If the reviewer finds CRITICAL issues, STOP — show the issues and do not create PR.
   - If the reviewer finds WARN-level issues, collect them for the PR body "Review Notes" section.
6. If `--skip-review` was passed, skip the review step.

## Build the PR

7. Determine the PR title:
   - If `docs/spec.md` exists, use the feature_id: `feat(<feature-id>): <short description>`
   - Otherwise, generate from the branch name and recent commits.
8. Build the PR body using this structure:
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
9. Push the current branch with `-u` flag.
10. Create the draft PR:
    ```bash
    gh pr create --draft --title "<title>" --body "$(cat <<'EOF'
    <body>
    EOF
    )"
    ```
11. Show the PR URL to the user.

## Arguments

- `--skip-review`: Skip the code review gate even if `pr_review` is enabled in scaffold.json.

## Rules

- PRs are always created as drafts. Human review is mandatory before merge.
- Never create a PR from main/master.
- Always run tests and validation before creating the PR.
- Include `docs/assumptions.md` content in the PR body so reviewers see what judgment calls were made.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
