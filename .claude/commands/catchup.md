Read the current state of the project to resume work after a context reset.

0a. If `scripts/docs-check.sh` exists, run `scripts/docs-check.sh validate` and report any staleness or mismatches before reading documents.
0b. If `scripts/docs-check.sh` exists, run `scripts/docs-check.sh recommend` and display the recommended next action.

1. Read `docs/checkpoint.md` if it exists — this contains the last session's progress and next steps.
2. Run `git log --oneline -10` to see recent commits.
3. Run `git diff --stat` to see any uncommitted changes.
4. Run `git diff --cached --stat` to see any staged changes.
5. Read `docs/spec.md` if it exists — this is the current feature specification.

Then provide a brief summary:
- Lifecycle state (from steps 0a/0b — aligned/stale/mismatched + recommended action)
- What was accomplished in previous sessions
- Current state (clean/dirty, passing/failing tests)
- What the next step should be based on checkpoint and spec
- If `docs/checkpoint.md` has a "Determinism Notes" section, mention any outstanding items

Do NOT start implementing anything. Just orient and report.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
