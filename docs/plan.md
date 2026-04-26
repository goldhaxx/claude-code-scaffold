# Implementation Plan: BTS-150 — Investigate suppressing redundant settings.local.json persistence

> Feature: bts-150-suppress-redundant-permission-persistence
> Work: linear:BTS-150
> Created: 1777171830
> Spec hash: 4ed38b72
> Based on: docs/spec.md

## Objective

Determine whether Claude Code exposes a knob that suppresses auto-persistence of redundant exact-form permissions to `settings.local.json` when a broader allow pattern already covers them. Document the verdict and either apply the configuration with empirical validation, or formally accept periodic `/permissions-review` cleanup as the permanent design.

## Sequence

Investigation tickets are not TDD — there's no failing test to write before research. Steps are research → synthesize → branch on verdict → document.

### Step 1: Literature search via claude-code-guide agent

- **Test:** N/A — research step. Output is a structured findings doc inline in the spec.
- **Implement:** Spawn `claude-code-guide` agent with the BTS-150 description verbatim plus a focused brief: "Investigate whether any Claude Code surface (settings field, hook event, env var, MCP interception, plugin) suppresses the prompt-and-persist behavior when a broader allow pattern already covers an exact-form Bash invocation. Specifically: (a) does any settings field control auto-persistence of approved exact-forms? (b) is there a hook event between user-approval and the write to settings.local.json? (c) does any env var govern the matcher's promote-to-local behavior? Report verdict per surface (`configurable` / `no-effect` / `partial` / `not-found`) with citations. Hard-cap: 3 distinct sources minimum, search depth bounded by relevance — no rabbit-holing into unrelated permission docs."
- **Files:** None yet — agent returns findings into the conversation.
- **Verify:** Agent returns at least 3 distinct sources cited. If the agent reports < 3 sources or only generic permission docs (no targeted finding), re-invoke with narrower brief or proceed with verdict=`not-found` per the spec's hard-cap policy.

### Step 2: Synthesize verdict from research

- **Test:** Verdict must be exactly one of `configurable` / `not-configurable` / `partial`. Binary classification — no "maybe."
- **Implement:** Read agent findings. Apply the rule: any single knob that fully suppresses the symptom → `configurable`. No knob found and no hook/env path → `not-configurable`. Knob exists but only covers a subset (e.g., suppresses prompt but not persistence, or vice versa) → `partial`.
- **Files:** None yet — verdict is a state variable feeding Step 3.
- **Verify:** State the verdict explicitly in chat before proceeding to Step 3 so the user can dissent if the synthesis seems off.

### Step 3a (only if verdict is `configurable` or `partial`): apply the configuration

- **Test:** AC-2 requires before/after diff of `settings.local.json` showing zero new entries after a deliberate novel `bash <script>` invocation.
- **Implement:**
  1. Capture `settings.local.json` snapshot: `cp .claude/settings.local.json /tmp/bts-150-before.json`.
  2. Apply the configuration to `.claude/settings.json` (or wherever the knob lives).
  3. Trigger a deliberately-novel `bash <script>` invocation that matches `Bash(bash:*)` in `settings.json` but isn't currently in `settings.local.json`. Pick a one-shot read-only command (e.g., `bash -c 'echo bts-150-validation'`) — must NOT be one we'll routinely use, so the validation evidence is unambiguous.
  4. After approval-or-passthrough, capture `settings.local.json` again: `cp .claude/settings.local.json /tmp/bts-150-after.json`.
  5. `diff /tmp/bts-150-before.json /tmp/bts-150-after.json` — expect empty output (zero new entries).
- **Files:** `.claude/settings.json` (modified), evidence captured inline in spec.
- **Verify:** Diff is empty. If non-empty, the knob didn't fully suppress — downgrade verdict to `partial` and proceed to 3b for residual coverage.

### Step 3b (only if verdict is `not-configurable` or `partial`): document the accepted design

- **Test:** AC-3 / AC-4 require a one-paragraph note in `.ccanvil/guide/command-reference.md` under the `permissions-audit.sh` section.
- **Implement:** Append a paragraph to `command-reference.md` near the existing `permissions-audit.sh` table, structured as: (1) what the gap is (Claude Code auto-persists redundant exact-forms despite broader patterns), (2) why suppression is unavailable / partial (cite the BTS-150 investigation findings), (3) what the operator should do (run `/permissions-review` on the cadence it surfaces — typically session boundaries via `/stasis`/`/recall` nudges), (4) link back to `docs/specs/bts-150-suppress-redundant-permission-persistence.md` for the full investigation.
- **Files:** `.ccanvil/guide/command-reference.md` (modified).
- **Verify:** Read back the appended paragraph. Confirm it cites the spec, names the cadence, and doesn't duplicate existing text.

### Step 4: Write Investigation Notes section in the spec archive

- **Test:** AC-5 requires sources consulted, candidate knobs, verdicts per knob, final verdict — minimum 3 sources.
- **Implement:** Append an `## Investigation Notes` section to `docs/specs/bts-150-suppress-redundant-permission-persistence.md` (the archive file, since `docs/spec.md` is removed at `complete`-time). Structure:
  ```
  ## Investigation Notes

  ### Sources consulted
  1. <url or reference> — <one-line description of what was found>
  2. ...
  3. ...

  ### Candidate knobs evaluated
  - <knob name>: <verdict — configurable / no-effect / partial / not-found>. <one-line rationale>

  ### Final verdict
  `<configurable | not-configurable | partial>` — <one-paragraph rationale>

  ### Empirical validation (if verdict ∈ {configurable, partial})
  Before/after diff of settings.local.json over the validation window. Result: <empty | non-empty>.
  ```
- **Files:** `docs/specs/bts-150-suppress-redundant-permission-persistence.md` (modified — append-only; preserves the original spec body above).
- **Verify:** `grep -c '^[0-9]\.' docs/specs/bts-150-suppress-redundant-permission-persistence.md` returns ≥ 3 in the Sources section. Final verdict line matches Step 2's classification.

### Step 5: AC-6 drift-guard verification

- **Test:** AC-6 requires `permissions-audit.sh promote-review --json | jq '.counts.total'` returns a deterministic value (not an error).
- **Implement:** Run the command. Confirm exit 0 and a numeric `.counts.total` field. No code change — pure verification that this ticket didn't break the upstream BTS-144/149 substrate.
- **Files:** None — verification only. Output captured in chat.
- **Verify:** Exit 0, output is valid JSON with `.counts.total` numeric.

### Step 6: Update preset documentation (skill rule 7)

This step applies because Step 3a may modify `.claude/settings.json` (a preset config) and Step 3b modifies `.ccanvil/guide/command-reference.md` (the hub guide). Both changes are hub-wide — they propagate downstream via `ccanvil-sync.sh` to other ccanvil nodes.

- **Test:** N/A — doc step.
- **Implement:**
  - If Step 3a fired (settings change): the `.claude/settings.json` change IS the preset infrastructure modification — no separate guide update needed if the change is just a knob value (no new convention). If the change introduces a new convention, add a one-paragraph note to `.ccanvil/guide/index.md` or the relevant section file.
  - If Step 3b fired (accepted-design note): the change is already in `command-reference.md` — that's the guide update.
  - If verdict was `configurable` AND the new convention is hub-wide: also note it in the hub section of `CLAUDE.md` under the `## Do Not` or relevant section (e.g., "Don't manually edit `settings.local.json` — let `/permissions-review` handle it; the suppression knob in settings.json prevents redundant entries").
- **Files:** Possibly `.ccanvil/guide/index.md` (if Step 3a introduces convention), possibly `CLAUDE.md` hub section (if convention is hub-wide).
- **Verify:** Read back the changes. Confirm they don't duplicate Step 3b's `command-reference.md` paragraph.

## Risks

- **Investigation balloon.** Research can rabbit-hole indefinitely. Mitigation: spec's hard-cap of 30 minutes for the search phase. If Step 1 returns nothing in two passes, default to `not-configurable` and ship the accepted-design note. Cost of a wrong "not-configurable" is one revisit when a future Claude Code release adds the knob — cheap.
- **False-positive `configurable` verdict.** Agent might find a knob that *looks* like it suppresses but actually doesn't (only suppresses prompts, not persistence — or vice versa). Mitigation: Step 3a's empirical validation is the truth-check. If diff is non-empty, downgrade to `partial` and document the residual gap. **This is exactly the live-validate-plan-flagged-API-shape pattern from feedback memory** — the validation step is mandatory, not optional.
- **Empirical validation hard to trigger.** A "deliberately novel" `bash <script>` invocation requires Claude Code to actually go through its prompt-and-persist flow — which depends on session state, current settings.local.json content, and the matcher's behavior. Mitigation: prefer commands that are obviously novel (specific timestamps, BTS-150-tagged echo strings) over commands that might already be cached. If validation can't be triggered cleanly in one attempt, document the validation gap as a residual `partial` finding rather than retrying indefinitely.
- **Settings.local.json drift during the session.** This very session may add new entries to `settings.local.json` from non-BTS-150 commands (e.g., the agent invocation, jq calls, etc.), polluting the before/after diff. Mitigation: snapshot `before` immediately before the deliberate invocation, capture `after` immediately after, and diff only those two snapshots — not against arbitrary historical state.
- **Hub doc update cascades.** If Step 6 modifies `.ccanvil/guide/index.md` or `CLAUDE.md`, downstream ccanvil nodes will see the change on next `ccanvil-sync.sh pull`. Mitigation: keep the change tightly scoped — one paragraph max, no convention reshuffling. If the verdict is `not-configurable`, prefer keeping the note inside `command-reference.md` (already a hub-managed file) rather than introducing new top-level conventions.

## Definition of Done

- [ ] All 6 acceptance criteria from spec pass.
- [ ] Investigation Notes section appended to spec archive with ≥ 3 sources cited.
- [ ] Verdict explicitly stated and justified.
- [ ] If `configurable` or `partial`: settings change applied AND empirical validation captured (before/after diff = empty).
- [ ] If `not-configurable` or `partial`: accepted-design paragraph in `.ccanvil/guide/command-reference.md`.
- [ ] AC-6 drift-guard passes (`promote-review --json` returns valid JSON).
- [ ] All existing tests still pass (`bash .ccanvil/scripts/bats-report.sh --parallel`).
- [ ] No new files in `dist/`, `generated/`, or other excluded paths.
- [ ] /review run on the diff (substrate / docs touch — per skip-/review feedback memory, doc-only diffs MAY skip /review, but if Step 3a applied a settings change, /review runs).

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
