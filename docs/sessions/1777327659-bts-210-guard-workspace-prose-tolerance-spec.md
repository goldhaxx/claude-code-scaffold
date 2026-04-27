# Feature: guard-workspace tolerates trailing prose punctuation on slash-command tokens

> Feature: bts-210-guard-workspace-prose-tolerance
> Work: linear:BTS-210
> Created: 1777327158
> Status: In Progress

## Summary

`guard-workspace.sh` blocks `/idea` and other slash-command captures when the body contains a slash-command token followed by prose punctuation — `/stasis).`, `/idea,`, `/spec.` — because BTS-173's allowlist regex (`^/<slash-command>$`) anchors at end-of-token and rejects any trailing characters. The token then falls through to path-shape detection, gets flagged as outside the workspace, and the hook blocks. Triggered ≥3× in the prior session alone (commit messages, idea bodies, spec dispatches), each requiring an `ALLOW_OUTSIDE_WORKSPACE=1` bypass that pollutes the audit trail.

This ship loosens the BTS-173 allowlist regex to tolerate a trailing run of common prose punctuation — period, comma, semicolon, colon, exclamation, question mark, closing bracket/paren/angle, quote chars — AFTER the slash-command name. The fix is allowlist-scoped: tokens that don't match a known slash-command (e.g., `/etc/foo`, `/var/log).`) still go through unchanged path-shape detection. No general path-shape loosening.

## Job To Be Done

**When** I write a slash-command reference in prose (commit message, idea body, spec, comment) followed by natural punctuation,
**I want to** have the workspace guard recognize the slash-command portion and pass the token through,
**So that** prose narrative doesn't trigger BLOCKED messages and force `ALLOW_OUTSIDE_WORKSPACE=1` bypasses on legitimate writes.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Slash-command tokens with trailing punctuation pass cleanly. Tokens of the form `/<known-slash-command><punct-run>` do NOT trigger the workspace block. Verified for: `/stasis).`, `/idea,`, `/spec.`, `/land:`, `/pr;`, `/radar!`, `/recall?`, `/review)`, `/plan]`, `/permissions-review>`, `/idea"`, `/spec'`.
- [ ] **AC-2:** Tolerated punctuation set is the trailing run of these characters AFTER the slash-command name: `.` `,` `;` `:` `!` `?` `)` `]` `>` `"` `'`. Multiple in sequence are fine (`/stasis).`, `/idea,").`). Token MUST start with `/<known-slash-command>` for tolerance to apply.
- [ ] **AC-3:** Slash-prefixed tokens that don't match a known slash-command still go through path-shape detection. Verified blocking still works for: `/etc/foo`, `/usr/local/bin`, `/var/log`, `/Users/other/path`, `/etc).` (etc isn't a slash-command). Allowlist-scoped fix; path-shape detection unchanged.
- [ ] **AC-4:** Bare `/idea` (no trailing punctuation) still passes via the existing exact-match path. Regression-clean — no behavior change for the BTS-173 happy path.
- [ ] **AC-5:** Multi-segment slash paths with prose punctuation still block. `/idea/sub).` is NOT a known slash-command (the allowlist matches single-segment names only); the token falls through to path-shape detection and blocks correctly.
- [ ] **AC-6:** New bats test `hub/tests/guard-workspace-prose-tolerance.bats` covers AC-1 through AC-5. Each tolerated punctuation char from AC-2 gets at least one test; AC-3 and AC-5 each get a representative blocking case to confirm the negation.
- [ ] **AC-7:** Full bats suite remains green: `bash .ccanvil/scripts/bats-report.sh --parallel` reports `PASS: <count>, FAIL: 0, TOTAL: <count>` with `<count>` ≥ 1737 (current baseline).

## Affected Files

| File | Change |
| -- | -- |
| `.claude/hooks/guard-workspace.sh` | Loosen BTS-173 allowlist regex to tolerate a trailing run of prose punctuation: `^/([a-zA-Z][a-zA-Z0-9_-]{0,29})[.,;:!?)\]>"'\`\]\*$\`. |
| `hub/tests/guard-workspace-prose-tolerance.bats` | New bats: AC-1 (tolerance per punct char), AC-3 (non-allowlist path tokens still block), AC-4 (bare slash-command regression), AC-5 (multi-segment still blocks). |

## Dependencies

* **Requires:** BTS-173 (slash-command allowlist substrate in `guard-workspace.sh`). Already shipped.
* **Blocked by:** Nothing.

## Out of Scope

* Leading prose punctuation like `(/stasis)` — current tokenization treats `(/stasis)` as a single token that doesn't START with `/`, so it doesn't match the BTS-173 regex at all. Rare in practice (operators usually write `(/stasis)` as `( /stasis )` or with spaces). Defer to a follow-up if friction emerges.
* Refactoring the BTS-173 allowlist-build helper to share with `guard-destructive.sh`. Sibling concern (BTS-202 covers guard-destructive); this fix is local to `guard-workspace.sh`.
* Generalized path-shape detection rewrite (the larger architectural narrowing the ticket body proposes — verb-context, redirect-context, filesystem-existence). Would be a separate, much larger spec; this ship is the targeted prose-tolerance patch that closes the immediate friction.

## Implementation Notes

* **Single regex change.** The existing BTS-173 match is `[[ "$token" =~ ^/([a-zA-Z][a-zA-Z0-9_-]{0,29})$ ]]`. Extend to `[[ "$token" =~ ^/([a-zA-Z][a-zA-Z0-9_-]{0,29})[.,\;:\!\?\)\]>\"\'\`\]\*$ \]\]`. The captured group `${BASH_REMATCH\[1\]}\` still extracts the slash-command name correctly because the punct run is OUTSIDE the capture.
* **Side-effect-free for non-allowlist tokens.** A token like `/etc).` matches the loosened regex shape but `etc` isn't in the slash-command allowlist, so the helper still falls through to path-shape detection. The fix changes ONLY the allowlist match boundary, not what tokens become candidates.
* **Bats fixture pattern.** Reuse the existing pattern from `hub/tests/guard-workspace-*.bats` — pipe a JSON envelope `{"tool_input":{"command":"<test-command>"}}` to the hook script and assert exit code 0 (allow) or 2 (block).
* **Live verify.** Run an `/idea` capture with body `Surfaced during /stasis).` and observe no BLOCKED message in the hook log. Validates the fix end-to-end.
* **Anchor on BTS-202.** Sibling ticket for the analogous guard-destructive false-positive on `jq -r` + `rm -f` combo. Same shape (prose-as-path), different guard. Don't refactor in this ship — keep ships independent.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
