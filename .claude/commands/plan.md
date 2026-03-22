Create an implementation plan for the feature described in the user's message (or in `docs/spec.md` if no message provided).

## Steps

1. Read `docs/templates/plan.md` for the plan format guide.
2. If `docs/spec.md` has content (not just the placeholder comment), read it for acceptance criteria.
3. Extract the `feature_id` from spec.md's metadata (the `> Feature:` line).
4. Compute the spec's content hash: run `scripts/docs-check.sh status` and read `.spec.content_hash` from the JSON output.
5. Analyze the codebase to identify affected files and existing patterns.
6. Write a plan to `docs/plan.md` following the template format. In the metadata blockquote, include:
   - `> Feature: <feature_id>` (copied from spec)
   - `> Created: <epoch>` (using `date +%s`)
   - `> Spec hash: <hash>` (from step 4)
5. Each step should be small enough to complete in one TDD cycle (~5-15 minutes).
6. Order steps so each builds on the previous — earlier steps establish foundations, later steps add features.

7. If any step adds, removes, or modifies scaffold infrastructure (commands, rules, agents, skills, hooks, scripts, or sync behavior), add a final step to update documentation. Read these files only when this step applies:
   - **Hub-wide changes** (modifying scaffold-shared files): update the hub section of `GUIDE.md` (above `<!-- NODE-SPECIFIC-START -->`). If conventions or "do not" rules changed, update the hub section of `CLAUDE.md` (below `<!-- HUB-MANAGED-START -->`).
   - **Local-only changes** (adding project-specific commands, rules, agents): update the node-specific section of `GUIDE.md` (below `<!-- NODE-SPECIFIC-START -->`). If the project's tech stack, commands, or architecture changed, update the node section of `CLAUDE.md` (above `<!-- HUB-MANAGED-START -->`).

Do NOT implement anything. Plan only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /scaffold-pull. -->
