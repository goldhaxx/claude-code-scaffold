# Feature: Gate `find -delete` and `find -exec/-execdir/-okdir` in guard-destructive.sh

> Feature: bts-155-gate-find-destructive
> Work: linear:BTS-155
> Created: 1777152482
> Status: In Progress

## Summary

Close the structural gap where `find` reaches mutation verbs through embedded operators that bypass the leading-verb regex. Add a path-agnostic destructive-find gate to `guard-destructive.sh`: when `find` is the leading verb and any of `-delete`, `-exec`, `-execdir`, `-okdir` appears, block by default with `ALLOW_DESTRUCTIVE=1` bypass. Also add `find` to `guard-workspace.sh`'s gated-verb regex so traversal-with-absolute-paths-outside-workspace also tripis the workspace fence. Same shape model as BTS-156's `rm -rf` gate.

## Job To Be Done

**When** an agent or operator issues a `find` command that combines traversal with a mutation/exec operator (`-delete`, `-exec`, `-execdir`, `-okdir`),
**I want to** have the hook block by default and require an explicit `ALLOW_DESTRUCTIVE=1` prefix to proceed,
**So that** in-workspace recursive deletes (`find . -delete`) and embedded destructive execs (`find . -exec rm {} +`) cannot fire silently.

## Acceptance Criteria

- [ ] **AC-1:** `find . -delete` exits 2 with `BLOCKED:` and bypass hint in stderr.
- [ ] **AC-2:** `find . -exec rm {} +` exits 2.
- [ ] **AC-3:** `find . -exec rm {} \;` exits 2.
- [ ] **AC-4:** `find . -execdir chmod 644 {} +` exits 2.
- [ ] **AC-5:** `find . -okdir rm {} \;` exits 2.
- [ ] **AC-6 (bypass):** `ALLOW_DESTRUCTIVE=1 find . -delete` exits 0 (existing line-15 short-circuit).
- [ ] **AC-7 (read-only allowed):** `find . -name '*.log'`, `find . -type f`, `find . -print` all exit 0 — no destructive operator present.
- [ ] **AC-8 (edge):** `find . -name '-delete' -print` exits 0 — `-delete` is a name pattern argument, not the action operator. (Tokenization gotcha; the regex must require word boundaries.)
- [ ] **AC-9 (word anchor):** Commands where `find` appears as substring (`xfind`, `find_files`) do NOT match — regex requires word boundary. `xfind . -delete` exits 0.
- [ ] **AC-10 (workspace fence):** `find /etc -name '*.conf'` exits 2 via `guard-workspace.sh` — `find` is now in the gated-verb regex, so out-of-workspace path tokens trip the fence. Bypass: `ALLOW_OUTSIDE_WORKSPACE=1`.
- [ ] **AC-11 (workspace fence allowed):** `find /tmp -name '*.log'` exits 0 — `/tmp` is whitelisted.
- [ ] **AC-12 (existing gates intact):** All pre-BTS-155 guard-hooks tests pass without modification.

## Affected Files

| File | Change |
|------|--------|
| `.claude/hooks/guard-destructive.sh` | Add destructive-find gate after the rm-recursive-force block |
| `.claude/hooks/guard-workspace.sh` | Add `find` to gated-verb regex (line 31) |
| `hub/tests/guard-hooks.bats` | ~12 tests covering AC-1 through AC-11 |
| `.ccanvil/guide/hooks.md` | Update the guard-destructive row to mention the new find gate |

## Dependencies

- **Requires:** BTS-156 shipped (sets the path-agnostic destructive-shape pattern this builds on).
- **Blocked by:** Nothing.

## Out of Scope

- **Variable indirection.** `find $TARGET -delete` with `$TARGET=...` set at runtime: static tokenizer can't see the expansion. Documented limitation, same as the existing rm/cp/mv set.
- **Symbolic-mode chmod via -exec.** `find . -exec chmod a+w {} +` — symbolic modes are intentionally allowed in the existing chmod gate; we follow that convention here.
- **Shell pipe / xargs composition.** `find . -type f | xargs rm -rf` is not a `find -exec` form; it's a `find ... | xargs rm` pipeline. The `rm -rf` in the literal string is caught by BTS-156's gate. No new logic needed.
- **`-prune` / `-quit`.** Not destructive; no gate needed.

## Implementation Notes

- **guard-destructive.sh:** add a path-agnostic gate mirroring BTS-156's `rm -rf` block. Match `find` as the leading verb (word-anchored to avoid `xfind`), then check for any of `-delete | -exec | -execdir | -okdir` as a flag token (word-anchored to avoid `'-delete'` as a name pattern arg):
  ```bash
  if [[ "$COMMAND" =~ (^|[[:space:]\;\|\&])find[[:space:]] ]] \
     && [[ "$COMMAND" =~ (^|[[:space:]])(-delete|-exec|-execdir|-okdir)([[:space:]]|$) ]]; then
    echo "BLOCKED: find with -delete or -exec/-execdir/-okdir traverses then mutates." >&2
    echo "  To bypass: ALLOW_DESTRUCTIVE=1 find ..." >&2
    exit 2
  fi
  ```
- **guard-workspace.sh:** add `find` to line 31's verb regex: `(rm|cp|mv|chmod|chown|bash|find)`. This enables the existing path-fence to fire on out-of-workspace find traversal (AC-10). No other changes needed in that file.
- **Test pattern:** mirror existing guard-hooks bats blocks. Use `set -e` on any test with ≥2 grep -q assertions per BTS-127.
- The `xfind` false-positive note (AC-9) is automatically handled by the `(^|[[:space:]\;\|\&])` left anchor — same as BTS-156's `rm` anchoring.
