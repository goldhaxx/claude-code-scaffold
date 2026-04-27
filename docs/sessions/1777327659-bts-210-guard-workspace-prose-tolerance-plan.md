# Implementation Plan: guard-workspace tolerates trailing prose punctuation

> Feature: bts-210-guard-workspace-prose-tolerance
> Work: linear:BTS-210
> Created: 1777327302
> Spec hash: 3f8533d7
> Based on: docs/spec.md

## Objective

Loosen the BTS-173 slash-command allowlist regex in `.claude/hooks/guard-workspace.sh` to tolerate a trailing run of prose punctuation, so tokens like `/stasis).` and `/idea,` pass through cleanly when the leading portion matches a known slash-command.

## Sequence

### Step 1: Red — write failing bats test for the trailing-punctuation tolerance

* **Test:** Create `hub/tests/guard-workspace-prose-tolerance.bats` with one `@test` per AC-1 punctuation form: pipe `{"tool_input":{"command":"echo /stasis)."}}` to the hook and assert exit 0. Cover `/stasis).`, `/idea,`, `/spec.`, `/land:`, `/pr;`, `/radar!`, `/recall?`, `/review)`, `/plan]`. Plus AC-3 negation: `echo /etc/foo` blocks (exit 2). Plus AC-4 regression: bare `/idea` passes. Plus AC-5: `/idea/sub).` blocks.
* **Implement:** Test file only. Hook source unchanged.
* **Files:** `hub/tests/guard-workspace-prose-tolerance.bats` (new).
* **Verify:** Run the new bats — AC-1 cases FAIL (current regex anchors at `$`, so `/stasis).` doesn't match the allowlist and falls through to the path-shape block). AC-3/4/5 cases should already pass with the current logic (regression check).

### Step 2: Green — extend the BTS-173 regex to tolerate trailing punct

* **Test:** Same bats from Step 1.
* **Implement:** Change line 104 of `.claude/hooks/guard-workspace.sh` from `[[ "$token" =~ ^/([a-zA-Z][a-zA-Z0-9_-]{0,29})$ ]]` to `[[ "$token" =~ ^/([a-zA-Z][a-zA-Z0-9_-]{0,29})[.,\;:\!\?\)\]>\"\'\`\]*$ \]\]*`. Capture group `${BASH_REMATCH\[1\]}`continues to extract the slash-command name; the punctuation run is OUTSIDE the capture so the existing allowlist comparison`" $candidate "\*\` is unaffected.
* **Files:** `.claude/hooks/guard-workspace.sh` (single regex on line 104).
* **Verify:** `bash hub/tests/guard-workspace-prose-tolerance.bats` — all tests pass. Then `bash .ccanvil/scripts/bats-report.sh --parallel` confirms full suite green at ≥ 1737.

### Step 3: Refactor — comment update + AC-2 doc-string

* **Test:** Suite stays green.
* **Implement:** Update the BTS-173 comment block above line 104 to note the BTS-210 punct-tolerance extension. Document the tolerated punct set inline. No logic change.
* **Files:** `.claude/hooks/guard-workspace.sh` (comment only).
* **Verify:** Re-run the bats suite. Green.

### Step 4: Doc — update [command-reference.md](<http://command-reference.md>)

* **Test:** N/A (docs).
* **Implement:** Add a one-line note under the `guard-workspace.sh` section in `.ccanvil/guide/command-reference.md` calling out BTS-210's tolerance for trailing prose punctuation on the slash-command allowlist match. Reference BTS-173 for the underlying allowlist and BTS-202 for the analogous guard-destructive sibling concern.
* **Files:** `.ccanvil/guide/command-reference.md`.
* **Verify:** Grep confirms the BTS-210 note is present and the BTS-173 reference is preserved.

## Risks

* **Punct-set under-coverage.** If operators commonly use a punct char not in the tolerated set (e.g., backtick `` ` `` in code spans), the fix would still false-positive on those forms. Mitigation: include backtick in the tolerated set (already in the proposed regex `[.,;:!?)\]>"'\`\]\*\`). Re-evaluate after one session of dogfood; ramp punct set if friction surfaces.
* **Allowlist regex change accidentally widens path-shape acceptance.** The captured group is the slash-command name only; trailing punct is OUTSIDE the capture. The downstream `*" $candidate "*` allowlist match uses only the capture group. Risk is structurally low. The bats AC-3 case (`/etc/foo` still blocks) is the regression guard.
* **Bash regex syntax compatibility.** Some special chars (`?`, `!`, `)`, `]`) need escaping inside the character class. Test against bash 3.2 (macOS default) AND bash 5+ during Step 2 verify. Use the `bats-report.sh --parallel` run as the smoke.

## Definition of Done

- [ ] All acceptance criteria from spec pass (AC-1 through AC-7)
- [ ] All existing tests still pass (≥ 1737 baseline + 12 new from this ship)
- [ ] No type errors (bats lint via `bats-lint.sh`)
- [ ] Code reviewed (run /review)

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
