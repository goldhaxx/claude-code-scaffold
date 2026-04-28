---
name: spec
description: "Write a feature specification with acceptance criteria. The first step after deciding to act on an idea."
manifest:
  id: spec
  purpose: Write a feature specification with binary-testable acceptance criteria; first step after deciding to act on an idea
  routes-by: /spec
  input:
    - "positional: <work-ref> (e.g. BTS-130, idea-29, linear:BTS-130)"
    - "positional: <description>"
    - "alt-form: idea <num> [description]"
  output:
    - "file: docs/specs/<feature-id>.md (always — local archive)"
    - "artifact: Linear Document (when integrations.routing.spec=linear)"
    - "state-transition: linked Linear ticket → Todo (when work-ref is linear:<id>)"
  caller:
    - .claude/commands/plan.md
    - .claude/commands/activate.md
    - .claude/skills/recall/SKILL.md
    - .claude/skills/radar/SKILL.md
    - .claude/skills/stasis/SKILL.md
    - .ccanvil/scripts/docs-check.sh
  depends-on:
    - operations.sh
    - docs-check.sh
    - linear-query.sh
  side-effect:
    - writes-spec-archive
    - dispatches-linear-document
    - transitions-linear-ticket
  failure-mode:
    - "unresolvable-work-ref | exit=1 | visible=stderr-error | mitigation=run-/idea-first"
    - "active-spec-in-flight | exit=1 | visible=warn-prompt | mitigation=/pr-and-/land-first"
  contract:
    - never-creates-branch
    - never-implements
    - work-ref-required
    - one-spec-per-feature-branch
  anchor:
    - BTS-130 (origin spec skill)
    - BTS-204 (provider-aware artifact-write)
    - BTS-213 (route-aware Linear dispatch)
    - BTS-240 (reference manifest seed)
---

# Spec Skill

Write a specification for the feature described in the arguments. Every spec requires a **work reference** — a provider-namespaced identifier (`BTS-130` on a Linear node, `idea-29` on a local node) that links the spec to its source-of-truth across Linear / GitHub / etc.

## Usage

- `/spec <work-ref> <description>` — write a spec with an explicit work reference
- `/spec idea <num> [description]` — write a spec from an existing idea (the idea UID serves as the work ref)
- `/spec BTS-130 <description>` — Linear-provider shorthand (resolves to `linear:BTS-130`)

A work ref is one of:

- A bare provider-native identifier (e.g., `BTS-130`, `PROJ-42`, `idea-29`) — resolved via the configured provider routing
- An explicit `<provider>:<id>` prefix (e.g., `linear:BTS-130`, `local:idea-29`) — overrides routing

## Steps

1. **Read the template:** Read `.ccanvil/templates/spec.md` for the specification format.

2. **Special-case `idea <num>` first:** If the first two args are literally `idea <N>`, the work ref is the idea UID `idea-<N>` (local) or the Linear identifier captured from the idea (Linear — fetch from the idea record). Do NOT run the generic resolver on the bare word `idea`; it will slug-match to the word "idea" on a local node and lose the `<N>`.

3. **Resolve the work reference:** For all other invocation forms (`/spec BTS-130 <desc>`, `/spec linear:BTS-130 <desc>`, `/spec idea-29 <desc>`), run `bash .ccanvil/scripts/operations.sh resolve work.resolve "<arg1>" --project-dir .` on the first user argument. Capture the resolved JSON (`{provider, id, slug, url}`).
   - If the command exits non-zero, **STOP** and tell the user: `/spec requires a work reference. Examples: /spec BTS-130 "describe the feature", /spec idea 29, /spec linear:BTS-130 "...". Run /idea <text> first to capture the work if it doesn't exist yet.` The script enforces format validation (bare Linear IDs must match TEAM-N; bare local IDs must contain a digit; whitespace rejected); descriptions that accidentally reach this step will fail fast.

4. **BTS-20: Check state via lifecycle-state.** Run `bash .ccanvil/scripts/docs-check.sh lifecycle-state --project-dir .` and read `.state`. If state is `spec-activated`, `plan-written`, or `implementing`, an active spec is already in flight on this branch — warn and ask before proceeding. The operator must `/pr` and `/land` (or revert) before drafting a new spec.

5. **If `idea <num>` mode (continued):** Run `bash .ccanvil/scripts/docs-check.sh idea-list` to get the idea body and use it as the feature description. Resolve the work ref via `operations.sh resolve work.resolve idea-<N>` (local) or the equivalent for Linear.

6. **Explore the codebase:** Search for relevant files, patterns, and existing tests that relate to this feature. Read the 3-5 most relevant files.

7. **Derive the `feature_id`:** Use `<slug>-<kebab-name>` where `<slug>` comes from the resolved work ref's `slug` field and `<kebab-name>` is a kebab-case description of the feature. Example: work ref `BTS-130` + "Add cool thing" → `bts-130-add-cool-thing`. The slug prefix is required — it propagates into the filename and the branch name (via `activate`) so Linear's GitHub integration auto-link fires.

8. **Write the spec** to `docs/specs/<feature_id>.md` following the template format:
   - Every acceptance criterion must be independently testable (binary pass/fail)
   - Use Given/When/Then format for complex criteria
   - Include at least one error/edge case criterion
   - Reference specific files and patterns from the codebase
   - Keep under 100 lines
   - Set metadata: `> Feature: <feature_id>`, `> Work: <provider>:<id>`, `> Created: PLACEHOLDER`, `> Status: Draft`. Then run `bash .ccanvil/scripts/docs-check.sh stamp-spec <feature_id>` to replace the placeholder with the current epoch deterministically (BTS-141 — never substitute the epoch via inline shell-variable interpolation; the script owns the timestamp).

8a. **BTS-213: route-aware Linear dispatch.** After `stamp-spec`, check the
    spec routing and dispatch the stamped content into the Linear Document
    when routed away from local. Without this step, post-`/spec` lifecycle
    queries Linear, finds nothing, and silently reports `state: no-active-spec`.

    ```bash
    if [[ "$(bash .ccanvil/scripts/docs-check.sh route-of spec --project-dir .)" == "linear" ]]; then
      if ! bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature "$feature_id" --project-dir . \
           < "docs/specs/$feature_id.md"; then
        echo "WARN: /spec wrote local archive but Linear dispatch failed." >&2
        echo "Retry: bash .ccanvil/scripts/docs-check.sh artifact-write --kind spec --feature $feature_id --project-dir . < docs/specs/$feature_id.md" >&2
      fi
    fi
    ```

    The local archive write happens BEFORE the dispatch, so a Linear-side
    failure leaves `docs/specs/<feature_id>.md` intact for the operator to
    retry without recomposing the spec body. Continue-with-WARN (not exit):
    matches `cmd_activate`'s symmetric behavior — the local archive is the
    durable state, the auto-transition to Todo can still proceed, and the
    operator retries the printed recipe at their convenience.

9. **If from an idea:** Run `bash .ccanvil/scripts/docs-check.sh idea-update <num> promoted`

10. **BTS-136: auto-transition Linear ticket to Todo.** If the resolved work ref is `linear:<ID>`, dispatch the transition via `operations.sh resolve ticket.transition <ID> todo`. BTS-164 migrated this verb to `mechanism: http` — the resolver returns a complete `linear-query.sh save-issue` command in `.invocation.command`. Eval it:

    ```bash
    RESOLUTION=$(bash .ccanvil/scripts/operations.sh resolve ticket.transition <ID> todo --project-dir .)
    eval "$(echo "$RESOLUTION" | jq -r '.invocation.command')"
    ```

    On failure (network, missing `LINEAR_API_KEY`), append `{"op":"ticket.transition","args":{"id":"<ID>","role":"todo"},"ts":<epoch>}` to `.ccanvil/ideas-pending.log` so `/idea sync` replays it later. Silent for `local:<uid>` and other providers (no Todo semantics there).

11. **Report:** Display the spec summary and suggest next step: "Spec written to `docs/specs/<feature_id>.md`. When ready, run `docs-check.sh activate <feature_id>` to create a branch and begin work."

## Note on `activate` transitions (BTS-136)

When `docs-check.sh activate` is run on a spec carrying `Work: linear:<ID>`, it emits an `AUTO-TRANSITION: {"provider":"linear","id":"<ID>","role":"in_progress"}` marker on stdout — same pattern as `/land`'s `AUTO-CLOSE:`. The caller scans stdout for this marker, then runs `operations.sh resolve ticket.transition <ID> in_progress` and eval's the resolved command (BTS-164: now `mechanism: http`, no MCP indirection). On failure, append a pending log entry as above. Silent for non-linear providers.

## Rules

- Do NOT create a branch or activate the spec. That happens separately via `activate`.
- Do NOT write a plan. That comes after activation via `/plan`.
- Do NOT implement anything. Spec only.
- The spec goes in `docs/specs/<feature_id>.md`, NOT `docs/spec.md`. The `activate` command copies it to the active location.
- The work ref is REQUIRED. Unresolvable refs halt the skill with a clear error. Legacy specs without `Work:` are grandfathered by the validator — enforcement happens at creation time, not retroactively.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
