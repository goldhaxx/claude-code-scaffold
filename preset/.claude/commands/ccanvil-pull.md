Pull updates from the scaffold hub into this project.

All deterministic operations (copy, hash, lockfile, logging) are handled by the script. Claude's role is LIMITED to judgment calls: conflict resolution and merge proposals.

## Step 1: Pre-check and plan (deterministic)

```bash
./.ccanvil/scripts/ccanvil-sync.sh pre-check
./.ccanvil/scripts/ccanvil-sync.sh pull-plan
```

Pre-check verifies both repos are clean and auto-bootstraps the sync script if the hub has a newer version (prints "BOOTSTRAPPED" and exits — re-run the command).

Read the JSON output. It contains an array of `{file, action, reason}` objects. Actions:
- `auto-update` — scaffold changed, local is clean. Safe to apply automatically.
- `adopt-clean` — new file in scaffold, identical local copy exists. Tracked automatically.
- `section-merge` — both changed, file has delimiter. Hub section updated, node section preserved.
- `conflict` — both changed, no delimiter. Requires human decision.
- `adopt-conflict` — new in scaffold, different local copy exists. Requires human decision.
- `new` — new file in scaffold, doesn't exist locally.
- `removed` — file removed from scaffold.

## Step 2: Execute auto-updates (deterministic)

If the plan contains `auto-update` entries:
```bash
./.ccanvil/scripts/ccanvil-sync.sh pull-auto
```

This handles both `auto-update` and `adopt-clean` files in one pass — copies, updates lockfile, logs. Do NOT manually `cp` or `lock-update`.

## Step 3: Handle section-merges (deterministic)

For each file with action `section-merge`:
```bash
./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> section-merge
```

Show the user what changed (hub sections updated, node sections preserved). No Claude judgment needed — the delimiter-based merge is deterministic.

## Step 4: Handle conflicts (JUDGMENT CALL)

For each file with action `conflict`:
1. Show the diff: `./.ccanvil/scripts/ccanvil-sync.sh diff <file>`
2. Present four options:
   - **Keep local** → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> keep-local`
   - **Take scaffold** → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> take-scaffold`
   - **Merge** → Claude reads both versions, proposes a combined version, writes it to a temp file, user approves → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> write-merged <temp-file>`
   - **Show full diff** → display side-by-side, then ask again

**This is the ONLY step where Claude exercises judgment** — proposing merged content.

## Step 5: Handle new files (deterministic with user confirmation)

For each file with action `new`:
1. Show the file's first few lines from the scaffold
2. If user accepts → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> accept-new`
3. If user declines → skip

## Step 6: Handle removed files (user confirmation)

For each file with action `removed`:
1. Ask user: keep locally or delete?
2. Keep → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> keep-local`
3. Delete → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> delete`

## Step 7: Finalize (deterministic)

```bash
./.ccanvil/scripts/ccanvil-sync.sh pull-finalize
```

This commits all changes with a structured message listing every synced file. The commit is browsable on GitHub.

Report what happened: N auto-updated, N section-merged, N conflicts resolved, N new files, N skipped.

## Rules
- NEVER run `cp`, `jq`, `shasum`, or `lock-update` manually. Use compound commands.
- NEVER auto-update a file that has local changes — the script enforces this.
- ALWAYS show the user what will change before writing.
- For merge conflicts, Claude proposes the merge but the user must approve.
- Do NOT manually commit sync changes — `pull-finalize` handles the commit.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
