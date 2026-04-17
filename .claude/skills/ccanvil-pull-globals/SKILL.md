---
name: ccanvil-pull-globals
description: Pull hub-owned ccanvil-* global commands into ~/.claude/commands/. Opt-in refresh; never touches user-owned files.
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
