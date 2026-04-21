---
name: recall
description: Re-hydrate context after a reset — read the last /stasis snapshot and report current project state.
---

Read the current state of the project to resume work after a context reset. `/recall` is the inverse of `/stasis`: it reads the snapshot that `/stasis` wrote, re-runs the deterministic state queries, and produces a cold-start briefing.

## Data gathering (deterministic)

0a. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh validate` and report any staleness or mismatches before reading documents.
0b. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh recommend` and display the recommended next action.
0c. Run `.ccanvil/scripts/operations.sh resolve backlog.list` to get routing info. If the mechanism is `bash`, execute the command from `invocation.command` (e.g., `.ccanvil/scripts/docs-check.sh list-specs`). If the mechanism is `mcp`, call the specified MCP tool with the given params. Report counts by status (Draft, Ready, In Progress, Complete).
0d. Check the current branch name (`git branch --show-current`). Report whether it follows the `claude/<type>/<name>` naming convention.

1. Read `docs/stasis.md` if it exists — this contains the last session's progress and next steps.
2. Run `git log --oneline -10` to see recent commits.
3. Run `git diff --stat` to see any uncommitted changes.
4. Run `git diff --cached --stat` to see any staged changes.
5. Read `docs/spec.md` if it exists — this is the current feature specification.

6. If `docs/stasis.md` has a `## Determinism Review` section with candidates_found > 0, read it and prepare to surface those items.
7. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh audit-session --since <last-stasis-commit>` (extract the commit from stasis metadata or use the last 10 commits) and note any new findings.

8. If `.ccanvil/scripts/docs-check.sh` exists, run `.ccanvil/scripts/docs-check.sh idea-count` and note any untriaged ideas.

## Briefing

Then provide a brief summary:
- Lifecycle state (from steps 0a/0b — aligned/stale/mismatched/no-active-spec + recommended action)
- **Spec backlog** — count of specs by status from step 0c, and which spec (if any) is active on the current branch
- **Ideas** — untriaged idea count from step 8 (if > 0, note: "N untriaged ideas — run /idea triage")
- **Branch** — current branch name and whether it follows convention (from step 0d)
- **Outstanding determinism improvements** — if the previous stasis's `## Determinism Review` had candidates, list them under this heading before the regular summary
- **Post-stasis audit findings** — if `audit-session` found patterns since the last stasis, list them here
- What was accomplished in previous sessions
- Current state (clean/dirty, passing/failing tests)
- What the next step should be based on stasis and spec

Do NOT start implementing anything. Just orient and report.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
