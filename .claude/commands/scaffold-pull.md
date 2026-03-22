Pull updates from the scaffold hub into this project.

All deterministic operations (copy, hash, lockfile, logging) are handled by the script. Claude's role is LIMITED to judgment calls: conflict resolution and merge proposals.

## Step 0: Bootstrap check (deterministic)

If `scripts/scaffold-sync.sh` itself has changed in the hub (check with `diff`), copy the new version first — the old script may lack commands needed by the pull:
```bash
scaffold_source=$(jq -r '.scaffold_source' .claude/scaffold.lock | sed "s|^~|$HOME|")
diff -q scripts/scaffold-sync.sh "$scaffold_source/scripts/scaffold-sync.sh" || cp "$scaffold_source/scripts/scaffold-sync.sh" scripts/scaffold-sync.sh
```

## Step 1: Pre-check and plan (deterministic)

```bash
./scripts/scaffold-sync.sh pre-check
./scripts/scaffold-sync.sh pull-plan
```

Read the JSON output. It contains an array of `{file, action, reason}` objects.

## Step 2: Execute auto-updates (deterministic)

If the plan contains `auto-update` entries:
```bash
./scripts/scaffold-sync.sh pull-auto
```

This copies all clean files, updates the lockfile, and logs — in one call. Do NOT manually `cp` or `lock-update`.

## Step 3: Handle section-merges (deterministic)

For each file with action `section-merge`:
```bash
./scripts/scaffold-sync.sh pull-apply <file> section-merge
```

Show the user what changed (hub sections updated, node sections preserved). No Claude judgment needed — the delimiter-based merge is deterministic.

## Step 4: Handle conflicts (JUDGMENT CALL)

For each file with action `conflict`:
1. Show the diff: `./scripts/scaffold-sync.sh diff <file>`
2. Present four options:
   - **Keep local** → `./scripts/scaffold-sync.sh pull-apply <file> keep-local`
   - **Take scaffold** → `./scripts/scaffold-sync.sh pull-apply <file> take-scaffold`
   - **Merge** → Claude reads both versions, proposes a combined version, writes it to a temp file, user approves → `./scripts/scaffold-sync.sh pull-apply <file> write-merged <temp-file>`
   - **Show full diff** → display side-by-side, then ask again

**This is the ONLY step where Claude exercises judgment** — proposing merged content.

## Step 5: Handle new files (deterministic with user confirmation)

For each file with action `new`:
1. Show the file's first few lines from the scaffold
2. If user accepts → `./scripts/scaffold-sync.sh pull-apply <file> accept-new`
3. If user declines → skip

## Step 6: Handle removed files (user confirmation)

For each file with action `removed`:
1. Ask user: keep locally or delete?
2. Keep → `./scripts/scaffold-sync.sh pull-apply <file> keep-local`
3. Delete → `./scripts/scaffold-sync.sh pull-apply <file> delete`

## Step 7: Finalize (deterministic)

```bash
./scripts/scaffold-sync.sh pull-finalize
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
<!-- Hub content above is updated via /scaffold-pull. -->
