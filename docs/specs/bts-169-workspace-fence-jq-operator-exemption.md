# Feature: guard-workspace.sh exempts jq `//` operator from path scan

> Feature: bts-169-workspace-fence-jq-operator-exemption
> Work: linear:BTS-169
> Created: 1777173168
> Status: Complete

## Summary

`guard-workspace.sh` tokenizes the inbound Bash command and treats any token starting with `/` as an absolute-path candidate. The jq alternative-default operator `//` (e.g., `.priority // null`, `.foo // "?"`) is a literal token starting with `/` — the path scan flags it as outside-workspace and the hook returns exit 2, blocking the command. This false-positive surfaced twice in the 2026-04-26 backlog-annihilation session and once mid-BTS-150 today; the workaround so far has been to restructure jq filters with `if/then/else` syntax or stage output through a tmpfile. Fix: exempt pure-slash tokens (`//`, `///`, etc.) from the path scan since they cannot be meaningful filesystem paths under any normal interpretation.

## Job To Be Done

**When** I run a Bash command containing a jq filter that uses the `//` alternative-default operator,
**I want** `guard-workspace.sh` to recognize `//` as a non-path token and skip it during the workspace fence check,
**So that** legitimate jq filters run without contortion (no `if/then/else` rewrite, no tmpfile staging) and the workspace fence still catches genuine outside-workspace path arguments to `rm`/`cp`/`mv`/`bash`/`cat`/etc.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** `guard-workspace.sh` exits 0 (allow) when given a command containing the `//` jq operator in a context where no other tokens violate the workspace fence. Concrete fixture: `bash -c "jq '.foo // null' file.json"` — the `//` token is present but no genuine outside-workspace path appears.
- [ ] **AC-2:** `guard-workspace.sh` continues to exit 2 (block) when given a command with a real outside-workspace absolute path. Regression-guard: `rm /etc/passwd` still blocks; `cp /var/log/foo /tmp/bar` still blocks.
- [ ] **AC-3:** `guard-workspace.sh` exits 0 for `///` (triple-slash) and `////` (quad-slash) tokens — these have no path semantics either. Drift-guard against partial fixes.
- [ ] **AC-4:** `guard-workspace.sh` continues to exit 2 for tokens like `//foo/bar` (slash-prefixed but with non-slash content). The fix only exempts *pure-slash* tokens; tokens that start with `//` followed by content are still subject to the workspace check. (POSIX permits `//` as a filesystem prefix; we don't allow it to escape workspace scoping.)
- [ ] **AC-5:** Bare `/` token (already handled by existing `/?*` case pattern that requires ≥1 char after the slash) continues to be skipped — no regression in the existing edge case.
- [ ] **AC-6:** Test coverage: a new `.bats` test file or addition to `hub/tests/guard-hooks.bats` covers AC-1 through AC-5 with deterministic fixtures (no live invocation; pipe synthetic JSON to the hook script).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | Modified — add pure-slash skip before the path scan |
| `hub/tests/guard-hooks.bats` (or new file) | Modified/Created — new tests for AC-1 through AC-5 |

## Dependencies

- **Requires:** none.
- **Blocked by:** none.

## Out of Scope

- **Full jq-operator exemption.** Only `//` is the recurring false-positive. Other jq operators (`|`, `,`, `?`, `as`) don't tokenize as slash-prefixed strings, so they aren't subject to this scan in the first place. No need for a broader jq-aware tokenizer.
- **POSIX `//` filesystem prefix support.** POSIX allows `//foo` as a vendor-defined prefix (e.g., Cygwin uses `//c/...`). We don't accommodate it here — the workspace fence is strict on principle, and operators using `//foo`-style paths can prefix `ALLOW_OUTSIDE_WORKSPACE=1`. The exemption strictly applies to pure-slash tokens.
- **Restructuring the workspace fence's tokenizer.** This is a one-line skip-rule, not a tokenizer overhaul.
- **Other guard-workspace false-positives** (e.g., `--cap-drop=//foo` flag tokens, regex-character classes that contain literal `/`). Out of scope; capture as separate ideas if observed.

## Implementation Notes

- **The fix.** Add one regex check inside the `for token in $NORMALIZED` loop, immediately before the `case "$token" in` statement: `[[ "$token" =~ ^/+$ ]] && continue`. This skips any token that is exclusively slashes (`/`, `//`, `///`, etc.) before the path-shape detection runs. The bare `/` case is already handled by the existing `/?*` pattern requiring ≥1 char after the slash, but the regex skip is more explicit and groups all pure-slash variants together.
- **Why regex over case pattern.** Bash `case` patterns can match `//` directly (`//) ;;`), but the regex `^/+$` covers `/`, `//`, `///`, ... in one expression. Cleaner and self-documenting via `+` meaning "one or more."
- **Test pattern.** Follow the existing `hub/tests/guard-hooks.bats` style: pipe a JSON envelope `{"tool_input": {"command": "<cmd>"}}` through the hook script, assert exit code, optionally assert stderr message. Use the seq-aware curl stub pattern from `hub/tests/linear-query.bats` only if multi-roundtrip fixtures are needed (they aren't here).
- **Performance.** The regex check is one comparison per token; tokens are typically <100 per command. Negligible overhead.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
