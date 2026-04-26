# Feature: /idea triage skill prose: jq -R @sh missing -r flag breaks --priority dispatch

> Feature: bts-176-idea-jq-shsh-rawflag
> Work: linear:BTS-176
> Created: 1777183729
> Status: Complete

## Summary

`/idea` skill prose (Triage section, lines 165 and 169) shell-quotes priority + duplicate-of values via `jq -R @sh` — missing the `-r` flag. The bare `-R` (raw input) wraps the result in JSON quotes, so `printf '%s' "3" | jq -R @sh` returns the literal text `"'3'"` rather than `'3'`. When eval'd into `linear-query.sh save-issue --priority "'3'"`, the inner argument arrives at save-issue as the literal string `'3'` (single-quotes preserved), and `jq --argjson v "$priority"` (line 510 of save-issue) rejects it as invalid JSON. The promote and merge dispatch paths in `/idea triage` silently fail; the operator must bypass the skill and call `linear-query.sh save-issue` directly. Fix is one character per occurrence: change `-R` to `-Rr` so the output is raw.

## Job To Be Done

**When** I run `/idea triage` and approve a `promote` or `merge` outcome,
**I want** the skill's eval-dispatched `linear-query.sh save-issue` invocation to receive a numeric `--priority` (or string `--duplicate-of` ticket key) that survives the shell round-trip,
**So that** the agentic dispatch path works end-to-end without falling back to a manual `linear-query.sh` invocation.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `.claude/skills/idea/SKILL.md` line 165 (promote dispatcher) reads `p=$(printf '%s' "$PRIORITY" | jq -Rr @sh)` — i.e., the `-Rr` variant, not `-R`. Verified by exact-line grep.
- [ ] **AC-2:** `.claude/skills/idea/SKILL.md` line 169 (merge dispatcher) reads `t=$(printf '%s' "$TARGET_ID" | jq -Rr @sh)` — i.e., the `-Rr` variant, not `-R`. Verified by exact-line grep.
- [ ] **AC-3:** Drift-guard bats test asserts `grep -q 'jq -R @sh' .claude/skills/idea/SKILL.md` returns NON-zero (the buggy pattern is absent from the skill).
- [ ] **AC-4:** Drift-guard bats test asserts `grep -c 'jq -Rr @sh' .claude/skills/idea/SKILL.md` returns ≥ 3 (parent-id from BTS-162 + the two patched sites in this ship).
- [ ] **AC-5:** Live-validation gate — run `bash .ccanvil/scripts/linear-query.sh save-issue --id BTS-176 --state '0dc23450-abcf-4c08-a9d3-bcf787c62fbd' --priority $(echo "3" | jq -Rr @sh | xargs)` succeeds (exit 0). Already proven during this ticket's pre-spec capture; regression check during impl.
- [ ] **AC-6:** Edge — full end-to-end re-test of the original repro: `eval "$cmd --priority $p"` where `cmd` is the resolved `ticket.transition <id> backlog` invocation and `p=$(printf '%s' "3" | jq -Rr @sh)`. Save-issue accepts the priority and returns `{id, title}` JSON. (Manual one-shot, not a bats test — too many moving parts; documents the smoke-test for /review.)

## Affected Files

| File | Change |
|------|--------|
| `.claude/skills/idea/SKILL.md` | Modified — change `jq -R @sh` to `jq -Rr @sh` on lines 165 and 169 |
| `hub/tests/idea-skill-jq-rawflag.bats` | New — drift-guards for AC-3 and AC-4 |

## Dependencies

- **Requires:** none. Pure prose fix in skill.
- **Blocked by:** none.

## Out of Scope

- **Sync-replay quoting consistency.** Line 214 (`eval "$cmd --priority $priority"`) and line 216 (`eval "$cmd --duplicate-of $target"`) in the sync section pass values without shell-quoting at all. Pending-log values are validated numeric (priority) and ticket-key-shaped (target), so the unquoted form works today but is inconsistent with the triage section. Could be unified, but that's a separate "consistency hygiene" concern — out of scope here.
- **Substrate hardening in `linear-query.sh save-issue`.** Could defensively unwrap `'3'` → `3` before `jq --argjson`. Adds complexity without clear benefit; the right fix is at the caller. Out of scope.
- **`/permissions-review`.** Verified: doesn't reference `jq -R @sh`, `--priority`, or `--duplicate-of`. No fix needed there.

## Implementation Notes

- **Pattern reference.** Lines 77, 79, and 213 of the same skill already use `jq -Rr @sh` correctly (all from BTS-162's `--parent-id` quoting). The fix is to bring lines 165 and 169 into parity with that established pattern.
- **Why both flags matter.** `-R` makes jq treat input as raw text (not JSON). `-r` makes jq emit raw output (no JSON quoting around result). Together: read-text-write-text. `@sh` then transforms that text into a shell-safe single-quoted form. With only `-R`, the output is `"'3'"` (JSON-wrapped shell-quoted form), which becomes a literal `'3'` string after eval — breaking `jq --argjson` downstream.
- **Drift-guard strategy.** Pure assertion-on-content tests. No fixture setup needed. Mirror the pattern from `hub/tests/idea-safe-markdown-rule.bats` (BTS-125) and `hub/tests/idea-template-flags.bats` (BTS-172) — drift-guards on skill-prose changes.
- **Live-API risk.** AC-5 is the live-validation gate per `.claude/rules/tdd.md` — the original repro proves the fix works against real save-issue dispatch. One live call, ~2 seconds.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
