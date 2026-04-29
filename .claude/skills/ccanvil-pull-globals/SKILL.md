---
name: ccanvil-pull-globals
description: Pull hub-owned ccanvil-* global commands into ~/.claude/commands/. Opt-in refresh; never touches user-owned files.
manifest:
  id: ccanvil-pull-globals
  purpose: Refresh hub-owned `ccanvil-*` global commands in `~/.claude/commands/` from the hub's `global-commands/` directory. Opt-in only — never invoked by broadcast or init. Conflicts surface a diff and require explicit `--force` to overwrite; user-owned (non-`ccanvil-*`) files are never touched.
  routes-by: /ccanvil-pull-globals
  input:
    - "optional: --force (overwrite local-modified ccanvil-* files)"
  output:
    - "stdout: human-readable summary (copied count, skipped count, conflicts list)"
    - "filesystem: ~/.claude/commands/ccanvil-*.md updated when no conflicts or --force passed"
  depends-on:
    - ccanvil-sync.sh
  side-effect:
    - writes-global-commands-when-no-conflict-or-forced
  failure-mode:
    - "conflicts-detected | exit=0 | visible=stdout-diff-and-resolution-options | mitigation=re-run-with---force-or-merge-manually"
  contract:
    - opt-in-only
    - non-destructive-by-default
    - touches-only-ccanvil-prefix-files
  anchor:
    - BTS-252 (manifest seed)
---

Refresh global Claude Code commands owned by the ccanvil hub.

## Steps

1. Run: `bash .ccanvil/scripts/ccanvil-sync.sh pull-globals`
2. Parse the JSON output: `{copied, skipped, conflicts}`.
3. If the user passed `--force` (as an argument to this skill), pass it through: `pull-globals --force`.

## Reporting

- If `copied > 0`: list the files that were newly copied or overwritten.
- If `skipped > 0`: mention the count (already up to date).
- If `conflicts > 0`: show the diffs (already printed to stderr by the script) and suggest:
  - Accept hub version: re-run with `--force`
  - Keep local version: no action needed
  - Merge manually: edit `~/.claude/commands/<file>` and re-run

## Rules

- Only `ccanvil-*.md` files in `~/.claude/commands/` are managed by this command. All other files in that directory are user-owned and never touched.
- This is opt-in — never invoked automatically by broadcast or init.
- Non-destructive by default: conflicts are reported, not auto-resolved. `--force` is the explicit overwrite.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
