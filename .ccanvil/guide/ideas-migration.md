# Migrating to the Linear-backed `/idea` system

This guide walks a downstream node through adopting the new idea pipeline shipped in `ideas-to-linear`. Before this change, `/idea` captures lived in a tracked `docs/ideas.md` and every capture eventually pressured a direct-to-main commit. After this change:

- Captures route through `.ccanvil/scripts/operations.sh` to one of two providers: a local gitignored JSONL log, or Linear Triage via MCP.
- `/idea` never touches git — no commits, no branches.
- The hub ships the common Linear provider defaults; each node opts in per its own `.claude/ccanvil.local.json`.

## 1. Pull the update

```bash
/ccanvil-pull
```

Picks up the new `docs-check.sh` subcommands, the rewritten `/idea` skill, and the shared provider defaults in `.claude/ccanvil.json`.

## 2. Decide the provider

**Default — Local provider.** Captures write to `.ccanvil/ideas.log` (JSONL, gitignored). Zero network, zero external dependency, zero config. Good for private repos, experimental projects, or anything where ideas don't need to escape the machine.

**Opt-in — Linear provider.** Captures create issues in Linear's Triage queue with an `idea` label and an `Idea` status. Use when the project's backlog already lives in Linear and you want ideas to join that flow naturally.

A node can switch between the two later by re-running `idea-setup` — the state is just a file.

## 3. Run `idea-setup`

**Local:**

```bash
bash .ccanvil/scripts/docs-check.sh idea-setup --provider local
```

**Linear:**

```bash
bash .ccanvil/scripts/docs-check.sh idea-setup \
  --provider linear \
  --team "<Linear team name>" \
  --project "<Linear project name>"
```

This writes (or deep-merges into) `.claude/ccanvil.local.json` with the right shape and adds `.ccanvil/ideas.log`, `.ccanvil/ideas-pending.log`, and `docs/ideas.md` to `.gitignore` (idempotent — safe to re-run).

## 4. Linear only — create the custom statuses

Statuses in Linear are team-scoped. If your node routes to the same team as the hub (Blocktech Solutions / BTS), the `Idea` and `Icebox` statuses already exist and you can skip this step.

Otherwise, create both statuses manually in the Linear UI:

1. Open **Team Settings → <your team> → Issue statuses & automations**.
2. Click **+** in the **Backlog** category. Name it `Idea`. Save.
3. Click **+** in the **Backlog** category again. Name it `Icebox`. Save.

(Linear's MCP currently doesn't expose status creation — this is the one unavoidable manual step. `idea-setup`'s output reminds you of it.)

## 5. Migrate legacy `docs/ideas.md`

If your node still has a tracked `docs/ideas.md` from before the migration:

```bash
bash .ccanvil/scripts/docs-check.sh idea-migrate
```

Behavior:

- **Local provider nodes**: parses the markdown checkbox entries, appends each as a JSONL line to `.ccanvil/ideas.log`, `git rm`s the old file, and ensures `.gitignore` covers the new stores.
- **Linear provider nodes**: the same command will move entries to the local store. If you want those entries promoted to Linear, run `idea-migrate --extract` and iterate the emitted intents through the `/idea` skill — or use `/idea triage` once the entries surface there. For most nodes the historical entries have already been triaged; preserving them locally in log form is usually enough.

`idea-migrate` is idempotent — rerunning when `docs/ideas.md` is absent exits 0 with "Nothing to migrate".

## 6. Smoke-test a capture

```
/idea test capture via the new flow
```

- **Local**: confirm a new line appeared in `.ccanvil/ideas.log`.
- **Linear**: confirm a new issue appeared in Linear Triage with status `Idea` and label `idea`.

If Linear is configured but a capture falls through to `.ccanvil/ideas-pending.log`, the MCP call failed (usually auth expiry). Fix the MCP connection and run `/idea sync` to drain the pending entries.

## Troubleshooting

**`/idea` exits with "missing Linear config"** — `routing.idea = "linear"` is set but `providers.linear.{project, team}` is missing. Re-run `idea-setup --provider linear --team ... --project ...`.

**Broadcast prints a "docs/ideas.md still tracked" hint for the node** — that node hasn't run `idea-migrate` yet. Each node migrates itself; `broadcast` only surfaces the need.

**Statuses don't exist in the target Linear team** — see step 4. `save_issue` will reject the capture until the statuses exist.

**Want to change providers later?** Just re-run `idea-setup` with different flags. The command is idempotent and deep-merges with the existing config.

<!-- NODE-SPECIFIC-START -->
<!-- Add project-specific content below this line. -->
<!-- Hub content above is updated via /ccanvil-pull. -->
