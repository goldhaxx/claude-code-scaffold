# Feature: Refine DANGER classifier to recognize bash control-flow keywords as non-DANGER

> Feature: bts-154-classifier-bash-keywords
> Work: linear:BTS-154
> Created: 1777162008
> Status: Complete

## Summary

The DANGER classifier in `permissions-audit.sh` flags bare bash control-flow keywords (e.g., `Bash(done)`) as DANGER via the `loop-primitive` regex. These keywords are bash grammar — they terminate `for`/`while`/`until` blocks and cannot execute anything on their own. The current behavior generates false-positive entries in `/permissions-review` that have no remediation other than `accept_danger`. Add a pre-check that exempts the standard bash control-flow keyword set (`Bash(<keyword>)` and `Bash(<keyword>:*)` shapes) so the classifier passes on grammar tokens before reaching DANGER patterns.

## Job To Be Done

**When** I run `permissions-audit.sh check` or `/permissions-review`,
**I want to** see only entries that represent real risk surface,
**So that** my review queue isn't polluted by structural false-positives that always resolve to `accept_danger`.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `Bash(done)` and `Bash(fi)` (bare keyword shapes) classify as **safe** (not DANGER) and contribute 0 to `.danger` count.
- [ ] **AC-2:** `Bash(for:*)`, `Bash(while:*)`, `Bash(if:*)`, `Bash(do:*)`, `Bash(then:*)`, `Bash(else:*)`, `Bash(elif:*)` (keyword-with-wildcard shapes) classify as **safe**. None contribute to `.danger`.
- [ ] **AC-3:** Recognized keyword set includes: `for`, `while`, `until`, `if`, `then`, `else`, `elif`, `fi`, `do`, `done`, `case`, `esac`, `in`, `function`, `select`, `time`. Each in both bare and `:*` form.
- [ ] **AC-4:** Substring-suffix shapes do NOT match the keyword set. `Bash(done-something)`, `Bash(fish)`, `Bash(forever)` all classify by their normal patterns (UNREVIEWED if novel, DANGER if matching another rule). Word-anchor the keyword set.
- [ ] **AC-5:** Truly dangerous shapes adjacent to keywords still classify as DANGER. `Bash(for f; rm -rf /)` (compound-operator) → DANGER. `Bash(do echo > /etc/passwd)` (redirect) → DANGER. Keyword exemption applies only to the bare-token / `:*`-suffix shapes, not arbitrary content that happens to start with a keyword.
- [ ] **AC-6 (regression):** The previous `loop primitives flagged as DANGER` test fixture (`Bash(for f:*)`, `Bash(do echo:*)`, `Bash(done)`) now classifies as 0 DANGER (BTS-154 inverts the prior behavior). Test renamed/contract-flipped to assert the new non-DANGER outcome with a comment referencing BTS-154.
- [ ] **AC-7 (edge):** `accept_danger` log entries for now-safe keywords (e.g., the existing `Bash(done)` entry in `.claude/permissions-log.json`) remain valid and don't trigger errors. The classifier returns "safe" for the entry — no DANGER classification means the `accept_danger` override path simply isn't reached. The log entry becomes a stale-but-harmless record (cleanup is operator's choice via `/permissions-review`).

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/permissions-audit.sh` | Modified — add `BASH_KEYWORD_SAFELIST` and pre-check in `check_danger` |
| `hub/tests/permissions-audit.bats` | Modified — flip the existing loop-primitives test, add positive coverage for bare/`:*` shapes and word-anchor edge case |

## Dependencies

- **Requires:** Existing `permissions-audit.sh check` substrate (BTS-134/143/144).
- **Blocked by:** none.

## Out of Scope

- Removing the existing `accept_danger: true` entry for `Bash(done)` from `.claude/permissions-log.json`. Operator cleanup via `/permissions-review` after ship.
- Refactoring the broader `loop-primitive` regex beyond what AC-6's contract-flip requires. The regex stays as a fallback for non-keyword shapes that might match `^for `/`^do `/`^done` literally (e.g., a user writing `Bash(for x in $(curl bad-url))`).
- BTS-150 (suppressing specific-form persistence at Claude Code's source) is a separate concern.

## Implementation Notes

- **Pre-check pattern:** add a `is_safe_bash_keyword()` function that runs before `check_danger`. If `inner` matches `^(<keyword-alternation>)(:\*)?$`, return safe immediately. Word-anchor with `^...$` to prevent substring matches (AC-4).
- **Keyword set as regex group:** `^(for|while|until|if|then|else|elif|fi|do|done|case|esac|in|function|select|time)(:\*)?$`. Sorted longest-first to avoid alternation matching the prefix (e.g., `do` matching before `done`); standard regex engines try alternatives left-to-right but the `$` anchor makes order safe in practice — verify with the AC-4 substring guard.
- **Test pattern:** mirror the existing `permissions-audit.bats` setup (`$FIXTURE` settings.json, `run bash "$SCRIPT" check`). Use `set -e` per BTS-127 for `@test`s with ≥2 jq -e assertions.
- **Family pattern (BTS-156/155/157/153):** path-agnostic regex + word-anchor + comprehensive bats × variants. This ticket fits the same shape — single shape gate, single-PR scope.
- **Loop-primitive interaction:** the existing `loop-primitive|^for |^do |^done` pattern at line 122 of `permissions-audit.sh` should still fire for shapes that aren't bare-keyword (e.g., a permission that happens to start with `for ` followed by inline content). Pre-check runs first, so the keyword-shape case never reaches loop-primitive.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
