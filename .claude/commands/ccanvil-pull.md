Pull updates from the hub into this project.

All deterministic operations (copy, hash, lockfile, logging) are handled by the script. Claude's role is LIMITED to judgment calls: conflict resolution and merge proposals.

## Step 0: Pre-pull assessment (deterministic + judgment)

```bash
./.ccanvil/scripts/ccanvil-sync.sh changelog
```

Read the JSON output. If `status` is `"up-to-date"`, tell the user "Already up to date with hub" and **stop** — skip all subsequent steps.

If `status` is `"behind"`, present the assessment:
1. Show the commit range and count: "Hub has **N** commits since last sync (`from` → `to`)"
2. Summarize the changes in a table with columns: **Change** | **Impact**
   - Group commits by feature/area (JUDGMENT CALL — Claude interprets commit messages)
   - Impact is one of: cosmetic, config, rules, scripts, commands, workflow
3. Run `context-budget.sh check --text` and note the current budget status as a baseline.
4. Ask the user: "Proceed with pull?" — **wait for confirmation** before continuing to Step 1.

This is a checkpoint. Do NOT proceed to Step 1 until the user confirms.

## Step 1: Pre-check and plan (deterministic)

```bash
./.ccanvil/scripts/ccanvil-sync.sh pre-check
./.ccanvil/scripts/ccanvil-sync.sh pull-plan
```

Pre-check verifies both repos are clean and auto-bootstraps the sync script if the hub has a newer version (prints "BOOTSTRAPPED" and exits — re-run the command).

Read the JSON output. It contains an array of `{file, action, reason}` objects. Actions:
- `auto-update` — hub changed, local is clean. Safe to apply automatically.
- `adopt-clean` — new file in hub, identical local copy exists. Tracked automatically.
- `section-merge` — both changed, file has delimiter. Hub section updated, node section preserved.
- `conflict` — both changed, no delimiter. Requires human decision.
- `adopt-conflict` — new in hub, different local copy exists. Requires human decision.
- `new` — new file in hub, doesn't exist locally.
- `removed` — file removed from hub.

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
   - **Take hub** → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> take-hub`
   - **Merge** → Claude reads both versions, proposes a combined version, writes it to a temp file, user approves → `./.ccanvil/scripts/ccanvil-sync.sh pull-apply <file> write-merged <temp-file>`
   - **Show full diff** → display side-by-side, then ask again

**This is the ONLY step where Claude exercises judgment** — proposing merged content.

## Step 5: Handle new files (deterministic with user confirmation)

For each file with action `new`:
1. Show the file's first few lines from the hub
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

## Step 8: Post-pull verification (deterministic)

```bash
./.ccanvil/scripts/context-budget.sh check --text
```

Report the budget status. If it changed from the Step 0 baseline (e.g., WARNING → HEALTHY or HEALTHY → WARNING), call it out explicitly. This catches pulls that improve or degrade the context budget.

## Rules
- NEVER run `cp`, `jq`, `shasum`, or `lock-update` manually. Use compound commands.
- NEVER auto-update a file that has local changes — the script enforces this.
- ALWAYS show the user what will change before writing.
- For merge conflicts, Claude proposes the merge but the user must approve.
- Do NOT manually commit sync changes — `pull-finalize` handles the commit.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
