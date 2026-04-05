Create a well-structured git commit from the current changes.

## Steps

1. Run `git status` to see all changed and untracked files.
2. Run `git diff --stat` and `git diff --cached --stat` to understand what changed.
3. If arguments include `--no-test`, skip to step 5.
4. Run the project's test suite. If tests fail, STOP — show the failure output and do not commit. Fix the issue first.
5. Stage relevant files. Prefer staging specific files by name over `git add -A`. Never stage `.env`, credentials, or secret files.
6. Analyze the staged diff to determine the change type and scope:
   - **type**: feat, fix, refactor, test, docs, chore, perf
   - **scope**: the module or area affected (optional but preferred)
   - **description**: concise "why" not "what", lowercase, no period
7. Present the proposed commit message to the user for approval:
   ```
   type(scope): description
   ```
8. If approved, create the commit using a HEREDOC for the message:
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): description

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
9. Run `git status` after commit to confirm success.

## Rules

- One logical change per commit. If the diff contains multiple unrelated changes, ask the user which to commit first.
- The commit message must follow conventional commit format: `type(scope): description` or `type: description`.
- Always include the `Co-Authored-By` trailer.
- Never commit with failing tests (unless `--no-test` was passed).
- Never commit files that contain secrets (.env, credentials, *.pem, *.key).

## Arguments

- `--no-test`: Skip running the test suite before committing. Use for documentation-only changes.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
