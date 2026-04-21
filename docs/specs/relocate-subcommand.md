# Feature: ccanvil-sync.sh relocate <new-path>

> Feature: relocate-subcommand
> Created: 1776712500
> Status: Draft

## Summary

Claude Code keys conversation history by a path-encoded directory under `~/.claude/projects/` (slashes → dashes). When a user `mv`s a project directory, that keying breaks: the old history dir is stranded under its pre-move path-encoded name, and embedded `cwd` fields in each `.jsonl` session file still reference the old absolute path. Today, Claude manually runs `mv` on the history dir plus a `sed` pass over the `.jsonl` files to re-associate. This spec adds a `relocate` subcommand that does both deterministically, invoked from the new project location after `mv`. This is Feature 3 of 3 in BTS-74 (sync-determinism-batch).

## Job To Be Done

**When** I have moved a project directory on disk (`mv ~/old-location ~/new-location`),
**I want** one command that renames `~/.claude/projects/<old-encoded>` to `<new-encoded>` and rewrites `cwd` in every `.jsonl` inside,
**So that** Claude Code's conversation history continues to work in the new location without manual `sed` ceremony.

## Acceptance Criteria

Each criterion is independently testable. Binary pass/fail.

- [ ] **AC-1:** Given the current working directory `/new/path` and a prior history dir at `~/.claude/projects/-old-encoded-path` with one `.jsonl` file whose entries contain `"cwd":"/old/path"`, when `ccanvil-sync.sh relocate /old/path` runs, then `~/.claude/projects/-old-encoded-path` is renamed to `~/.claude/projects/-new-encoded-path` and the `.jsonl` file's `cwd` fields are rewritten to `/new/path`.
- [ ] **AC-2:** Path encoding: absolute path `/Users/zach/projects/foo` → encoded dir name `-Users-zach-projects-foo` (every `/` replaced with `-`, leading `-` preserved). The command must use this same encoding for both lookup and rename.
- [ ] **AC-3:** Multi-file rewrite: when the history dir contains N `.jsonl` session files, each is rewritten. Files that do not contain the old path are unchanged (including byte-identical `mtime`).
- [ ] **AC-4:** Idempotency: re-running `relocate <old-path>` after success is a no-op — the source dir no longer exists, so the command exits 0 with a message like `"No history dir found at ~/.claude/projects/-old-encoded-path (already relocated?)"`.
- [ ] **AC-5:** Collision safety: if both `~/.claude/projects/<old-encoded>` and `~/.claude/projects/<new-encoded>` exist, the command exits non-zero with an explanatory error and makes NO changes (neither rename nor cwd rewrite).
- [ ] **AC-6:** Input validation: if the provided `<old-path>` is not an absolute path (does not start with `/`), exit non-zero with a usage error; no rename attempted.
- [ ] **AC-7:** `cwd` matching: the rewrite only replaces occurrences of `"cwd":"<old-path>"` (JSON-field form) — unrelated strings containing `<old-path>` as a substring in message content must NOT be rewritten. Implementation uses either a jq-per-line rewrite or a sed pattern anchored to `"cwd":"` and the exact old path.
- [ ] **AC-8:** Non-destructive on failure: if the rename succeeds but a cwd rewrite fails partway (e.g., disk full), the command emits a warning and exits non-zero. The already-renamed dir is left in place (we do not re-rename to avoid compounding damage).
- [ ] **AC-9:** Regression: all existing bats tests pass.

## Affected Files

| File | Change |
|------|--------|
| `.ccanvil/scripts/ccanvil-sync.sh` | Modified — add `cmd_relocate` function + dispatch case |
| `hub/tests/relocate-subcommand.bats` | New — bats tests for AC-1..AC-8 |

## Dependencies

- **Requires:** nothing outside the existing script infrastructure. Does NOT require a lockfile (unlike most subcommands) since the operation is about Claude Code history, not hub sync.
- **Blocked by:** nothing. BTS-74 Features 1 and 2 are already merged.

## Out of Scope

- Rewriting the project registry (`registry.json`) path field — registry entries already use `~`-prefix portable paths, so they are unaffected by project-root moves within `$HOME`.
- Rewriting any `.claude/ccanvil.json`, `.ccanvil/ccanvil.lock`, or git repo paths — all node-side files use paths relative to the node root, not absolute.
- Auto-invocation from `register` or any other subcommand — `relocate` is an explicit user action after `mv`.
- Windows path handling — encoding convention on Windows differs; out of scope for this spec.
- Rewriting `cwd` in any file other than `.jsonl` under the renamed dir.

## Implementation Notes

- **Signature:** `ccanvil-sync.sh relocate <old-absolute-path>`. New path is inferred from `$(pwd)` — the command is run from the new location.
- **Encoding function:** extract into a helper `encode_project_path() { echo "${1//\//-}" | sed 's/^-/-/'; }` — simple slash-to-dash with the leading dash preserved. Test independently via AC-2.
- **Rename step:** `mv "$old_dir" "$new_dir"` with the collision pre-check from AC-5 and absence-check from AC-4.
- **Cwd rewrite step:** use `sed -i ''` (BSD) with fallback to `sed -i` (GNU) — same pattern already used in `docs-check.sh`'s idea-update. Pattern: anchor on `"cwd":"<old-path>"`, replace with `"cwd":"<new-path>"`. Escape the paths for sed via existing helper or simple `sed` substitution (paths contain `/`, so use a different delimiter such as `|`).
- **Pattern to follow:** keep the function under 40 lines. Model the dispatch case on simple subcommands like `registry` or `status`.
- **Test harness:** create a temp `~/.claude/projects/-<encoded>` dir with one fixture `.jsonl` file containing 2 entries (one with matching cwd, one without). Invoke `relocate` from a temp new-path. Assert dir rename, cwd rewrite, and non-match preservation.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
