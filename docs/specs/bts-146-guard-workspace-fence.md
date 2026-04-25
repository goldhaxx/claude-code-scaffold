# Feature: guard-workspace fence

> Feature: bts-146-guard-workspace-fence
> Work: linear:BTS-146
> Created: 1777080454
> Status: Complete

## Summary

Sequel to BTS-142. The autonomy-first permissions rewrite opened up broad command-namespace wildcards (`Bash(rm:*)`, `Bash(cp:*)`, `Bash(mv:*)`, `Bash(chmod:*)`, `Bash(chown:*)`, `Bash(bash:*)`) trusting "the hook layer to catch the genuinely dangerous cases" — but the hook layer didn't enforce a workspace boundary. Add a new PreToolUse hook `guard-workspace.sh` that blocks file-mutation verbs when any absolute or tilde-prefixed path argument falls outside the workspace (`$HOME/projects/`) or whitelisted system temp dirs. Bypass via `ALLOW_OUTSIDE_WORKSPACE=1`.

## Job To Be Done

**When** Claude is about to run a file-mutation command (rm/cp/mv/chmod/chown/bash) referencing a system path or user-directory path,
**I want to** the hook layer to block the operation by default and surface a deterministic bypass affordance,
**So that** broad command-namespace allow-listing remains safe — mutations are scoped to `~/projects/`, system paths require explicit consent.

## Acceptance Criteria

- [ ] **AC-1:** `rm /etc/foo` → block (status 2, stderr names the violating path).
- [ ] **AC-2:** `cp ~/Downloads/x ~/projects/ccanvil/y` → block (source outside workspace).
- [ ] **AC-3:** `cp ~/projects/a ~/projects/b` → allow (status 0, both inside workspace).
- [ ] **AC-4:** `chmod 755 /usr/local/bin/foo` → block.
- [ ] **AC-5:** `chown user ~/Library/foo` → block.
- [ ] **AC-6:** `bash ~/Documents/script.sh` → block (script path outside workspace).
- [ ] **AC-7:** `bash -c "rm /etc/foo"` → block (quoted inline command, path still extracted).
- [ ] **AC-8:** `rm /tmp/foo` → allow (POSIX temp whitelisted).
- [ ] **AC-9:** `rm /private/var/folders/xx/yy/T/test` → allow (macOS `mktemp -d` location whitelisted).
- [ ] **AC-10:** `rm relative/path.txt` → allow (relative paths assumed CWD-relative; CWD is always inside workspace during Claude work).
- [ ] **AC-11:** `bash .ccanvil/scripts/foo.sh` → allow (relative script path).
- [ ] **AC-12:** `cat /etc/passwd` → allow (verb not in gated list — read-only ops untouched).
- [ ] **AC-13:** `ALLOW_OUTSIDE_WORKSPACE=1 rm /etc/foo` → allow (bypass works, consistent with `ALLOW_DESTRUCTIVE=1` / `ALLOW_MAIN=1` patterns).
- [ ] **AC-14:** Hook registered in `.claude/settings.json` `hooks.PreToolUse[Bash]` block alongside `protect-main.sh`, `guard-force-push.sh`, `guard-destructive.sh`. Broadcasts to nodes via `ccanvil-sync.sh broadcast`.
- [ ] **AC-15:** Block message names the offending path, the workspace boundary, and the bypass syntax. Format: `BLOCKED: path '<token>' is outside the workspace ($HOME/projects/).` followed by `  To bypass: ALLOW_OUTSIDE_WORKSPACE=1 <command>`.
- [ ] **AC-16:** New bats cases in `hub/tests/guard-hooks.bats` covering AC-1 through AC-13; full bats suite stays green (no regressions in the existing 1035 cases).

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-workspace.sh` | New — PreToolUse hook implementing the fence |
| `.claude/settings.json` | Modified — register guard-workspace.sh in PreToolUse[Bash] hook chain |
| `hub/tests/guard-hooks.bats` | Modified — add 13+ test cases covering AC-1..AC-13 |

## Dependencies

- **Requires:** BTS-142 (autonomy-first rewrite — already shipped). The broad wildcards are the reason this fence is needed.
- **Blocked by:** Nothing.

## Out of Scope

- **`mkdir` and `touch` verbs** — symmetric to `rm` for file creation. Punt to follow-on; v1 sticks with Zach's explicit verb list (rm/cp/mv/chmod/chown/bash).
- **Subshell expansion blind spots** — `rm $(find / -name foo)` will still detect `/` as an absolute path and block the whole command. Variable indirection (`rm $SOMEPATH`) won't be expanded by the hook; the literal token `$SOMEPATH` doesn't start with `/` or `~/` so it'd pass. This is a known limitation; document it in the hook header.
- **Relative-path traversal (`../../../../etc/x`)** — bypasses absolute-path check. Catching it requires resolving against CWD. Doable but adds complexity. Skip for v1.
- **Read-only ops outside workspace** (`cat /etc/passwd`, `head /var/log/x`) — not blocked. Scope explicitly limited to mutation verbs per BTS-146 description.
- **Workspace path configurability** — hardcoded `$HOME/projects/` for v1. If forks need other workspace roots, capture as follow-on (would read from `.claude/ccanvil.json` or env var).

## Implementation Notes

- Same shape as `guard-destructive.sh` / `guard-force-push.sh`: read JSON from stdin, jq-extract `.tool_input.command`, exit 0 to allow / exit 2 to block.
- **Bypass first:** if `$COMMAND =~ ALLOW_OUTSIDE_WORKSPACE=1` → exit 0. Same pattern as the existing guards.
- **Verb gate:** if command doesn't contain a gated verb at a word boundary (`(^|[separator])(rm|cp|mv|chmod|chown|bash)([space]|$)`) → exit 0. Conservative regex — also matches `git rm` / `git mv`, but path check below handles the false-positive case (those typically operate on workspace paths).
- **Tokenize:** strip quotes via `tr -d '"' | tr -d "'"`, then word-split with `for token in $NORMALIZED`. Quote-stripping makes `bash -c "rm /etc/foo"` extract `/etc/foo` as a token after split.
- **Whitelist check:** absolute-path tokens (start with `/`) checked against allow-list (`$HOME/projects/`, `/tmp/`, `/private/tmp/`, `/var/folders/`, `/private/var/folders/`, `/dev/null`, `/dev/stdin`, `/dev/stdout`, `/dev/stderr`). Tilde-path tokens (start with `~/`) checked against `~/projects/`. Use `case` statement with glob prefix patterns — same pattern as existing hook string matches.
- **First violation wins:** stop on first out-of-workspace path; surface that token in the BLOCKED message. Matches existing hook UX.
- **Test pattern:** strict-mode bats per `.claude/rules/tdd.md`. Use the same JSON-piping pattern as the existing `guard-destructive` cases. New test section in `guard-hooks.bats`, header `# guard-workspace.sh — workspace fence (BTS-146)`.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
