# Feature: Gate `rm -rf` (recursive + force) in guard-destructive.sh

> Feature: bts-156-gate-rm-rf
> Work: linear:BTS-156
> Created: 1777151296
> Status: Complete

## Summary

Extend `guard-destructive.sh` with a recursive-AND-force `rm` gate. Today the hook intercepts four destructive `git` verbs and three catastrophic `chmod` numeric modes; `rm` has zero coverage there. `Bash(rm:*)` is permitted broadly and `guard-workspace.sh`'s path-fence only catches paths outside `~/projects/`. Inside the workspace, `rm -rf .` runs silently. This spec adds a path-agnostic block on the recursive-force shape, requiring `ALLOW_DESTRUCTIVE=1` to bypass — same envelope as the existing chmod 777 / git reset --hard gates.

## Job To Be Done

**When** an agent or operator issues a `rm` command that combines recursive (`-r`/`-R`/`--recursive`) AND force (`-f`/`--force`),
**I want to** have the hook block it by default and require an explicit `ALLOW_DESTRUCTIVE=1` prefix to proceed,
**So that** catastrophic recursive wipes of the workspace, tmp directories, or symlinked-out targets cannot happen without operator-typed opt-in.

## Acceptance Criteria

- [ ] **AC-1:** Given a Bash invocation `rm -rf <path>`, when the hook fires, then it exits 2 and stderr contains `BLOCKED:` and the bypass hint.
- [ ] **AC-2:** Combined-flag variants are all blocked: `rm -fr`, `rm -rfv`, `rm -Rfv`, `rm -fR`, `rm -Rf`. Each form exits 2.
- [ ] **AC-3:** Long-form variants are blocked: `rm --recursive --force <path>` and `rm --force --recursive <path>` (either order).
- [ ] **AC-4:** Bypass works: `ALLOW_DESTRUCTIVE=1 rm -rf <path>` exits 0 (the existing line-15 short-circuit covers this — verified by test).
- [ ] **AC-5:** Recursive-only is allowed: `rm -r <path>` and `rm -R <path>` exit 0 (interactive-by-default; not the catastrophic shape).
- [ ] **AC-6:** Force-only is allowed: `rm -f <file>` and `rm --force <file>` exit 0 (targeted; not recursive).
- [ ] **AC-7:** Plain `rm <files...>` (no flags) exits 0.
- [ ] **AC-8 (edge):** Flag clusters that LOOK recursive-force but aren't, e.g. `rm -i -f` (interactive + force, no -r) and `rm -v -r` (verbose + recursive, no -f), exit 0.
- [ ] **AC-9 (edge):** Commands that mention `rm` as a substring in another verb (`form -rf`, `arm -rf`) are NOT matched — the regex anchors `rm` as a whole word.
- [ ] **AC-10 (path-agnostic):** Block fires regardless of path. `rm -rf /tmp/foo` and `rm -rf ./foo` and `rm -rf ~/projects/x` all exit 2 (the workspace fence catches first when applicable; this is a second layer).
- [ ] **AC-11 (existing gates intact):** All pre-BTS-156 guard-hooks tests pass without modification — the new branch is additive.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-destructive.sh` | Add rm-recursive-force gate after the chmod block (line ~55) |
| `hub/tests/guard-hooks.bats` | Add ~10 tests covering AC-1 through AC-10 |

## Dependencies

- **Requires:** Nothing. The hook is already wired into `settings.json` PreToolUse for Bash; the bypass envelope already exists at line 15.
- **Blocked by:** Nothing.

## Out of Scope

- `find -delete` / `find -exec rm` — tracked by BTS-155.
- `cat` workspace fence — tracked by BTS-153.
- `rm` symlink-following risk (resolving symlinks before checking the fence) — separate hardening, not in scope here. The recursive-force gate fires on shape regardless of path, which is the primary mitigation.
- `xargs rm -rf`, `find ... | xargs rm`, or other indirect invocations — these are pipe-composed; the hook only sees the literal command string, so an opaque pipeline reaching `rm -rf` via xargs would not match. Out of scope; document the gap in implementation notes.

## Implementation Notes

- Follow the same shape as the chmod numeric-mode block at lines 47-55: regex match → echo BLOCKED → echo bypass hint → exit 2.
- Use TWO regex branches: one for clustered short flags (`-rf`, `-fr`, `-rfv`, etc.), one for separated long flags (`--recursive ... --force` in either order). The combined regex below from BTS-156's proposal is the starting point but should be refined to prevent the AC-8/AC-9 false-positives:
  ```bash
  # Cluster: a single -flag chunk containing both r/R and f
  if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*)([[:space:]]|$) ]]; then …
  # Long: --recursive and --force both present (either order)
  if [[ "$COMMAND" =~ (^|[[:space:]])rm[[:space:]] ]] && [[ "$COMMAND" =~ --recursive ]] && [[ "$COMMAND" =~ --force ]]; then …
  ```
- Word-anchor `rm` with `(^|[[:space:]])` to avoid `arm` / `form` substring hits (AC-9).
- Lowercase `f` is force; lowercase `r` and uppercase `R` are both recursive — handle both in the cluster regex.
- Test pattern: mirror `guard-destructive: blocks chmod 777` block (hub/tests/guard-hooks.bats:169-196) — `input='{"tool_name":"Bash","tool_input":{"command":"..."}}'`, `echo "$input" | bash "$DESTRUCTIVE_HOOK"`, assert exit code + stderr substring.
