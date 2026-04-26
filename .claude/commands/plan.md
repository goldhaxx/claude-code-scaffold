Create an implementation plan for the feature described in the user's message (or in `docs/spec.md` if no message provided).

## Steps

0. **BTS-20: lifecycle-state pre-flight.** Run `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` and read `.state`. /plan is legal only when state is `spec-activated` (drafting first plan) or `plan-written` (re-planning after spec edit). On any other state — `no-active-spec`, `session-wrap`, `blocked`, `uninitialized` — STOP with the envelope's `.blockers[]` (when populated) or a clear message naming the current state and the legal entry conditions. This fails fast instead of /plan reading `docs/spec.md` silently and erroring late on missing content.
1. Read `.ccanvil/templates/plan.md` for the plan format guide.
2. If `docs/spec.md` has content (not just the placeholder comment), read it for acceptance criteria.
3. Extract the `feature_id` from spec.md's metadata (the `> Feature:` line).
4. Compute the spec's content hash: run `.ccanvil/scripts/docs-check.sh status` and read `.spec.content_hash` from the JSON output.
5. Analyze the codebase to identify affected files and existing patterns.
6. Write a plan to `docs/plan.md` following the template format. In the metadata blockquote, include:
   - `> Feature: <feature_id>` (copied from spec)
   - `> Created: <epoch>` (using `date +%s`)
   - `> Spec hash: <hash>` (from step 4)
5. Each step should be small enough to complete in one TDD cycle (~5-15 minutes).
6. Order steps so each builds on the previous — earlier steps establish foundations, later steps add features.

6a. **Live-API validation gate (BTS-171).** If any plan step flags a live-API contract uncertainty — phrasings like `live API`, `live endpoint`, `exact filter shape`, `may not work`, `if the live API rejects`, `verify against live`, or equivalent — explicitly enumerate the live command that proves the contract and require its execution BEFORE the implementation step is considered complete (i.e., before commit and before `/review`). Stubs accept any shape; only live calls verify contract. See `.claude/rules/tdd.md#live-api-validation-gate` for the rule and prior incidents (BTS-115, BTS-170).

7. If any step adds, removes, or modifies preset infrastructure (commands, rules, agents, skills, hooks, scripts, or sync behavior), add a final step to update documentation. Read these files only when this step applies:
   - **Hub-wide changes** (modifying hub-shared files): update the relevant file in `.ccanvil/guide/` (hub section, above `<!-- NODE-SPECIFIC-START -->`). If conventions or "do not" rules changed, update the hub section of `CLAUDE.md` (below `<!-- HUB-MANAGED-START -->`).
   - **Local-only changes** (adding project-specific commands, rules, agents): update the node-specific section of the relevant `.ccanvil/guide/` file (below `<!-- NODE-SPECIFIC-START -->`). If the project's tech stack, commands, or architecture changed, update the node section of `CLAUDE.md` (above `<!-- HUB-MANAGED-START -->`).

Do NOT implement anything. Plan only.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
