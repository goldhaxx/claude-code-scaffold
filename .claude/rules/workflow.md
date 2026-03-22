# Workflow and Context Management Rules

## Session Discipline

- Each session has ONE objective. State it explicitly at the start.
- **Forward momentum:** After completing work, always close with an explicit directive — not just a summary. The user should never have to ask "what's next?" End with: one-line summary → clear next action (e.g., "Session complete. `/clear` → `/catchup` when ready for [next thing]."). If there's a choice, present options with a recommendation.
- If a session exceeds ~30 minutes of complex work, proactively suggest checkpointing.

## Before Writing Code

1. Search the codebase first: use grep/glob to find relevant patterns before reading files.
2. Read only the 3-5 most relevant files. Do not dump entire directories into context.
3. Check for existing tests that cover the area you're modifying.
4. If the task is ambiguous, ask one clarifying question before proceeding.

## Context Preservation

- When I say "checkpoint," write to `docs/checkpoint.md` (see `docs/templates/checkpoint.md` for format):
  - What was accomplished this session
  - Current state of the implementation
  - Failing tests (if any) and why
  - Exact next steps to resume
- **Lifecycle metadata:** When writing a checkpoint, include metadata in the blockquote:
  - `> Feature: <feature_id>` (copied from plan.md's metadata)
  - `> Last updated: <epoch>` (using `date +%s`)
  - `> Plan hash: <hash>` (run `scripts/docs-check.sh status` and read `.plan.content_hash`)
- **Plan before checkpoint:** If a spec exists but no plan, run `/plan` before checkpointing. Planning in warm context is cheaper than in cold context.
- **Determinism Review at checkpoint:** Before suggesting `/clear`, perform the warm-context determinism review and fill the `## Determinism Review` section in `docs/checkpoint.md`. The checkpoint flow order is:
  1. Write checkpoint content (accomplished, state, next steps)
  2. Walk through the determinism checklist (below) while you still have full session awareness
  3. Write the Determinism Review section with `operations_reviewed` and `candidates_found` counts
  4. Commit
  5. Close with forward directive: one-line summary + explicit next action + `/clear`
- **Determinism checklist** (review before clearing context):
  - (a) Did I run manual `cp`, `jq`, `shasum`, or `git -C` commands that a script should handle?
  - (b) Did I improvise a multi-step sequence that could be a single script call?
  - (c) Did I work around a missing feature in a script?
  - (d) Did I perform any operation more than once that should be automated?
  - Even if no candidates are found, write: "No candidates this session."
- When resuming after `/clear`, read `docs/checkpoint.md` first.

## Commit Practices

- Commit after each passing test cycle (red → green → refactor → commit).
- Message format: `type(scope): description` — e.g., `feat(auth): add JWT refresh token rotation`
- Types: feat, fix, refactor, test, docs, chore, perf
- Never commit with failing tests.

## Delegation

- Use sub-agents for: researching unfamiliar APIs, reading large files, exploring codebase structure.
- Keep the main session for: implementation decisions, writing code, running tests.
- When spawning a sub-agent, give it a specific question to answer, not an open-ended exploration.

## Scaffold Sync

- After adding a new rule, command, agent, or skill, consider whether it's project-specific or globally useful.
- **Classify new components at creation time:** When creating a new file in a tracked scaffold directory (`.claude/rules/`, `.claude/commands/`, `.claude/skills/`, `.claude/agents/`, `.claude/hooks/`), ask the user: "Is this project-specific (node-only) or should it sync with the scaffold (tracked)?" Then run the appropriate command: `./scripts/scaffold-sync.sh node-only <file>` or leave as tracked (default).
- Run `/scaffold-status` periodically to check for scaffold updates.
- Before starting a new project, pull latest scaffold changes into your current project first.
- When scaffold structure changes (new/modified commands, rules, agents, skills, hooks, or scripts), `GUIDE.md` must be updated to reflect the change — diagrams, tables, and descriptions must stay accurate.

## Error Recovery

- After 2 failed attempts at the same approach, STOP.
- Write what you've learned to `docs/checkpoint.md`.
- Suggest: "This approach isn't working. Let me outline alternatives."
- Do not keep trying variations of a failing strategy.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
