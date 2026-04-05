Demote a scaffold-managed file to local-only override.

This is a fully deterministic operation. No Claude judgment needed.

## Steps

1. The user provides a file path as an argument: `/ccanvil-demote .claude/rules/workflow.md`

2. Confirm with the user: "This will mark `<file>` as a local override. Future scaffold pulls will show diffs instead of auto-updating. Proceed?"

3. **(DETERMINISTIC)** Run the full demote workflow:
```bash
./.ccanvil/scripts/ccanvil-sync.sh demote <file>
```

This handles: status verification, lockfile update, and logging — all in one call.

4. Report the result. Mention they can re-sync by running `/ccanvil-pull` and choosing "Take scaffold" for this file.

## Rules
- NEVER run `lock-update` or `log` manually. The `demote` command handles everything.
- If the file status is not `clean`, the script will error with a clear message.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
