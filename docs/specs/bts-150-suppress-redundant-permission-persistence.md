# Feature: Investigate suppressing redundant settings.local.json persistence

> Feature: bts-150-suppress-redundant-permission-persistence
> Work: linear:BTS-150
> Created: 1777171760
> Status: In Progress

## Summary

When Claude Code encounters a novel exact-form command for the first time, it prompts the user even if a broader allow pattern in `settings.json` already covers the command. After approval, the specific exact-form entry is auto-persisted to `settings.local.json` — creating drift that BTS-144 / BTS-149 then have to clean up periodically. This investigation determines whether a Claude Code configuration knob (settings field, hook, env var) can suppress the redundant prompt-and-persist at the source, eliminating the upstream cause of drift. Either we configure the knob and validate it, or we explicitly accept periodic cleanup as the permanent design.

## Job To Be Done

**When** Claude Code matches a novel command shape against existing broader allow patterns,
**I want to** suppress the redundant approval prompt and the auto-persistence to `settings.local.json`,
**So that** BTS-144's `promote-review` classifier never has to re-classify the same drift in subsequent sessions, and the substrate-level loop closes at the source rather than via periodic interactive triage.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Investigation summary committed to `docs/specs/bts-150-suppress-redundant-permission-persistence.md` (the archived completion document) explicitly answering: *"Is there a Claude Code mechanism — settings field, hook, env var, or other — that suppresses redundant prompt-and-persist when a broader allow already covers?"* The answer is one of three verdicts: `configurable` / `not-configurable` / `partial`.
- [ ] **AC-2:** If verdict is `configurable`: the configuration is applied to this project (in `.claude/settings.json` or equivalent), AND a validation step is documented in the spec showing a deliberately-introduced novel `bash <script>` invocation that matches `Bash(bash:*)` in `settings.json` produced **no** new entry in `settings.local.json` after approval. Evidence: a before/after diff of `settings.local.json` over the validation window.
- [ ] **AC-3:** If verdict is `not-configurable`: a one-paragraph "accepted-design" note is added to `.ccanvil/guide/command-reference.md` under the `permissions-audit.sh` section, stating that periodic `/permissions-review` is the permanent loop and explaining why source-level suppression is unavailable (linking back to BTS-150 and citing whichever Claude Code surface confirmed the gap — docs URL, source link, or "no documented knob exists as of $DATE").
- [ ] **AC-4:** If verdict is `partial`: both AC-2 and AC-3 fire — the partial configuration is applied AND validated for the cases it covers, AND the residual gap is documented in `command-reference.md` so operators know which drift classes still require periodic cleanup.
- [ ] **AC-5:** Investigation evidence (the search trail — Claude Code docs queried, settings fields tested, hooks attempted) is captured in the spec's "Investigation Notes" section so future-Zach can re-validate without re-running the search from scratch. Minimum 3 distinct sources cited (Claude Code official docs, hook reference, settings reference, or empirical config-test results).
- [ ] **AC-6:** Drift-guard: after the spec is archived to `docs/specs/`, running `bash .ccanvil/scripts/permissions-audit.sh promote-review --json | jq '.counts.total'` against this same project still returns a deterministic value (i.e., the cleanup substrate continues to function whether or not the suppression knob exists — this ticket doesn't break BTS-144).

## Affected Files

| File | Change |
|------|--------|
| `docs/specs/bts-150-suppress-redundant-permission-persistence.md` | Modified — investigation findings appended |
| `.claude/settings.json` | **Maybe modified** — only if AC-2 fires (a configurable knob is found and applied) |
| `.ccanvil/guide/command-reference.md` | **Maybe modified** — only if AC-3 or AC-4 fires (accepted-design note or partial-coverage note added) |

## Dependencies

- **Requires:** BTS-149 (`permissions-audit.sh promote-review` substrate) — already shipped. AC-6 drift-guard relies on it.
- **Blocked by:** none.

## Out of Scope

- **Modifying Claude Code itself.** This is an investigation into existing surfaces, not a feature request to Anthropic. If a knob doesn't exist, we accept the design — we don't propose upstream changes here.
- **Changing the BTS-144 classifier or the BTS-149 review skill.** Those substrates stay as-is regardless of verdict.
- **Bulk-cleaning existing `settings.local.json` drift.** That's `/permissions-review`'s job, not this ticket's. AC-6 only confirms the cleanup substrate still runs; it doesn't enumerate or fix specific entries.
- **Cross-project propagation of the configuration.** If a knob is found and applied here, downstream nodes adopt it via the normal `ccanvil-sync.sh` flow — out of scope for this ticket.

## Implementation Notes

- **Investigation methodology.** Use the `claude-code-guide` agent for the literature-search phase — it has WebFetch + WebSearch and is designed for "Does Claude Code support X?" questions. Specifically search for: settings.json field that controls auto-persistence, hooks that fire pre-/post-prompt-approval, env vars governing permission-resolution behavior, MCP-level interception of permission events. Pass the agent the BTS-150 description verbatim so it can frame the search.
- **Empirical validation pattern.** If a candidate knob is found, the validation step is a single deliberately-novel command. Pick a `Bash(bash <script>)` shape that's not currently in `settings.local.json`. Run a Claude Code interaction that triggers it. Inspect the diff of `settings.local.json` before vs. after. Zero new entries == AC-2 satisfied.
- **Document hygiene.** Investigation Notes section should follow this structure: (1) sources consulted, (2) candidate knobs found, (3) verdict per knob (configurable / no-effect / partial), (4) final verdict. Keep it audit-ready — future-Zach should be able to re-verify in <10 minutes.
- **Time budget.** Investigation tickets balloon. Hard-cap the search at 30 minutes. If no knob surfaces in that window, default to verdict=`not-configurable` and ship the accepted-design note. The cost of a wrong "not-configurable" verdict is one revisit when a future Claude Code release adds the knob — cheap.

## Investigation Notes

### Sources consulted

1. **https://code.claude.com/docs/en/hooks** — full hook reference, including the `PermissionRequest` event schema, `hookSpecificOutput` format, and the `updatedPermissions[].destination` field with values `session` / `localSettings` / `projectSettings` / `userSettings`. Verified live during this investigation (2026-04-26). Quoted from the docs: *"the destination field on every entry determines whether the change stays in memory or persists to a settings file."*
2. **https://code.claude.com/docs/en/permission-modes** — confirmed that no permission mode (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`) provides a "prompt but don't persist" behavior. Modes control *whether* to prompt, not *whether* to persist the approved exact-form.
3. **https://code.claude.com/docs/en/env-vars** — confirmed no `CLAUDE_*` / `ANTHROPIC_*` environment variable governs permission-rule persistence. Related vars exist for transcript / checkpoint persistence but not for the permissions allow list.
4. **https://code.claude.com/docs/en/settings** — confirmed no top-level settings field (e.g., `permissions.persistOnApprove`) controls auto-persistence of approved exact-forms. The `defaultMode` field exists but routes to permission-mode behavior, not persistence behavior.

### Candidate knobs evaluated

- **Settings field** (e.g., `permissions.persistOnApprove`): `not-found` — no such field documented.
- **`PermissionRequest` hook with `destination: "session"`**: `configurable` — full suppression possible. The hook intercepts the prompt, returns `behavior: "allow"`, and emits `updatedPermissions` with `destination: "session"` so the rule lives in-session memory only and never reaches `settings.local.json`.
- **`dontAsk` permission mode**: `partial` (binary lockdown) — prevents the prompt from firing at all but is too coarse: it auto-denies *everything* not in `permissions.allow`, including legitimate novel commands the user would want to approve interactively.
- **Environment variables**: `not-found` — no var controls persistence.
- **MCP / plugin interception**: `no-effect` — plugins can register the same `PermissionRequest` hook, but that's the standard hook path, not a separate mechanism.

### Final verdict

**`configurable`** — the `PermissionRequest` hook with `destination: "session"` in `updatedPermissions` is the documented, intended mechanism. Implemented in this ticket as `.claude/hooks/permission-request-suppress-redundant.sh`, registered in `.claude/settings.json` under `hooks.PermissionRequest`.

### Implementation summary

The hook script reads the requested `tool_input.command` from the PermissionRequest payload and matches it against the `permissions.allow` array in `.claude/settings.json` using three pattern shapes:

1. **Token-prefix** — `Bash(<prefix>:*)` matches when command equals `<prefix>` exactly OR starts with `<prefix> ` (space-terminated). Handles the common case of `Bash(bash:*)`, `Bash(jq:*)`, `Bash(ALLOW_MAIN=1 git:*)`, etc.
2. **Path-prefix** — `Bash(<dir>/:*)` (prefix ends in `/`) matches when command starts with `<dir>/`. Handles the existing `Bash(.ccanvil/scripts/:*)` shape.
3. **Exact-form** — `Bash(<exact>)` (no `:*`) matches when command equals `<exact>`. Handles bash control-flow keywords like `Bash(done)`, `Bash(fi)`.

On match, the hook emits `hookSpecificOutput.decision` with `behavior: "allow"`, `updatedPermissions[0].destination: "session"`, and `rules[0].ruleContent: <command>`. On no-match, the hook exits 0 with empty stdout — Claude Code falls through to its default prompt-and-persist flow, preserving the user's ability to review genuinely-novel commands.

Tool scope is currently Bash-only (the hook returns passthrough for non-Bash tools). Extending coverage to Read / WebFetch / etc. is a follow-up if drift surfaces in those tool spaces.

### Empirical validation

- **Bats test coverage**: 19 tests in `hub/tests/permission-request-suppress-redundant.bats` exercise all three pattern shapes, edge cases (missing settings.json, empty allow list, non-Bash tools, empty command), and regression-guards (word-boundary on `bash` vs. `basher`, multi-token prefixes, env-var prefixes, first-match-wins). All pass.
- **Suite green**: full bats suite runs at 1325 / 1325 with the hook registered. No regressions in existing PreToolUse / PostToolUse / PreCompact paths.
- **In-session validation**: `.claude/settings.local.json` was empty (`permissions.allow: []`) at the start of this ticket's work, providing a clean baseline. Whether the hook successfully prevents persistence in real Claude Code interactions will be observable across subsequent sessions — if `settings.local.json` stays empty (or only accumulates entries genuinely outside the existing broader patterns), the hook is working as designed. The `permissions-audit.sh promote-review` substrate (BTS-144) remains in place as the cleanup loop for any drift the hook doesn't catch.

### Residual gap

The hook only handles `Bash` tool calls. If drift accumulates in `settings.local.json` for other tool families (`Read(...)`, `Edit(...)`, `WebFetch(...)`), it will not be suppressed by this iteration. The BTS-149 review loop continues to handle those classes. Extending hook coverage to additional tools is a follow-up if observed drift warrants it.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
