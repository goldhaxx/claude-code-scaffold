# Feature: guard-workspace bare-slash false-positive

> Feature: bts-147-guard-workspace-bare-slash
> Work: linear:BTS-147
> Created: 1777083046
> Status: In Progress

## Summary

`guard-workspace.sh` (BTS-146) tokenizes commands and checks every absolute-path token against a workspace whitelist. Its case glob `/*)` matches a bare `/` — so any command with a literal standalone `/` token (jq format strings like `'\(.a) / \(.b)'`, shell math `$((a/b))` after splitting, or simple `cat / dev/null` typos) trips the absolute-path check and gets blocked. Discovered stasis-time when a `bash .ccanvil/scripts/context-budget.sh ... | jq -r '\(.totals.tokens) / \(.context.budget)'` invocation was blocked. One-line fix: change the glob to `/?*)` so the absolute-path branch only fires on `/` + at least one more character.

## Job To Be Done

**When** a Bash command contains a literal standalone `/` token (typically inside a jq format string or shell expression),
**I want to** the workspace fence to ignore it,
**So that** routine pipeline plumbing isn't blocked and `ALLOW_OUTSIDE_WORKSPACE=1` is no longer needed as a daily workaround.

## Acceptance Criteria

- [ ] **AC-1:** When the hook receives a command whose only `/`-prefixed token is a bare `/` (e.g., `bash script | jq '\(.a) / \(.b)'`), it exits 0.
- [ ] **AC-2:** When the hook receives a command containing a real out-of-workspace path (e.g., `rm /etc/foo`), it still exits 2 with the existing BLOCKED message.
- [ ] **AC-3:** When the hook receives a command containing both a bare `/` token AND an out-of-workspace path (e.g., `cat /etc/foo | jq '\(.a) / \(.b)'`), it still exits 2 (real path wins, bare `/` ignored).
- [ ] **AC-4:** All existing BTS-146 bats cases (16) continue to pass without modification.
- [ ] **AC-5:** `ALLOW_OUTSIDE_WORKSPACE=1` bypass still works on commands containing a bare `/`.
- [ ] **AC-6:** Edge — a command with a single-char absolute token like `/a` is still subjected to the prefix whitelist (the fix excludes only the bare `/`, not all short paths).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | Modified — line 61 case glob `/*)` → `/?*)` |
| `hub/tests/guard-hooks.bats` | Modified — add regression cases for AC-1, AC-3, AC-6 |

## Dependencies

- **Requires:** BTS-146 (guard-workspace hook) — already shipped.
- **Blocked by:** Nothing.

## Out of Scope

- Other tokenization gaps documented in the hook header (variable indirection, relative-path traversal, subshell expansion).
- Refactoring the tokenizer to be quote-aware. The bare-`/` fix is surgical; broader tokenization is a separate concern.

## Implementation Notes

- Shell glob semantics: `/?*` = `/` + any single char + zero or more = `/` + ≥1 character. Bare `/` does NOT match.
- Verify by hand: in bash, `case "/" in /?*) echo match;; *) echo nomatch;; esac` prints `nomatch`. `case "/x" in /?*) echo match;; esac` prints `match`.
- Test in `hub/tests/guard-hooks.bats` next to the existing BTS-146 block. Use the same `mk_input` helper and `WORKSPACE_HOOK` constant.
- This is the dogfood validation of BTS-146: the hook flagged its own bug in production within minutes of shipping.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
